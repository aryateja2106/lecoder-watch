// wol.ts — Wake-on-LAN, so "power that machine back on" works from the wrist.
//
// The phone cannot send the packet itself: WoL is a raw UDP broadcast on the local
// segment, and a sleeping machine has no TCP stack to accept anything. What the phone
// can do is ask a daemon that is already awake on the same LAN to shout for it — which
// is why this lives in meshd and not in the app. /health hands out this machine's MAC
// while it is up, so the phone caches it and can name it to a peer later with no setup.
//
// Limits worth knowing before blaming the code: WoL never crosses a router (a Tailscale
// peer three hops away cannot wake anything), the target must have "Wake for network
// access" / WoL enabled in its firmware or energy settings, and a machine that is fully
// powered off only listens if its NIC keeps standby power.
import os from "node:os";

const WOL_PORT = 9;   // the discard port, where magic packets conventionally go
const REPEATS = 3;    // UDP drops silently and the packet is 102 bytes; three is free

// Virtual interfaces have MACs and IPv4 addresses but no LAN behind them, so waking
// through one is a guaranteed no-op. Tailscale's utun/tailscale devices are the trap
// this list exists for: on a Mac they often sort before en0.
const VIRTUAL_IFACE = /^(lo|utun|tailscale|awdl|llw|bridge|gif|stf|anpi|ap\d|vmnet|docker|veth|virbr|br-|tun|tap)/i;

/** Six 0xFF bytes then the MAC sixteen times over: 102 bytes, and that is the protocol. */
export function magicPacket(mac: string): Uint8Array {
  const bytes = parseMac(mac);
  const out = new Uint8Array(6 + 16 * 6);
  out.fill(0xff, 0, 6);
  for (let i = 0; i < 16; i++) out.set(bytes, 6 + i * 6);
  return out;
}

/** Accepts colon or dash form, any case. Anything else throws rather than waking nothing. */
function parseMac(mac: string): Uint8Array {
  const parts = String(mac ?? "").trim().split(/[:-]/);
  if (parts.length !== 6 || !parts.every((p) => /^[0-9a-fA-F]{2}$/.test(p))) {
    throw new Error(`invalid MAC address: ${JSON.stringify(String(mac ?? ""))} (want aa:bb:cc:dd:ee:ff)`);
  }
  return Uint8Array.from(parts, (p) => parseInt(p, 16));
}

/**
 * Emit the magic packet three times to `broadcast:9`. Fire-and-forget by nature: a
 * sleeping machine cannot acknowledge anything, so a resolved promise means "sent",
 * never "awake". The caller polls /health to learn whether it worked.
 *
 * Two destinations, deduped: the one asked for, plus this LAN's directed broadcast.
 * That is not belt-and-braces — an unbound socket on macOS refuses 255.255.255.255
 * outright (EHOSTUNREACH, verified on 26.0) because the limited broadcast has no route,
 * while 192.168.x.255 goes out fine. Linux takes the limited broadcast happily. Six
 * 102-byte datagrams cost nothing, and covering both means neither platform is the one
 * where wake silently does nothing.
 */
export async function sendWake(mac: string, broadcast = "255.255.255.255"): Promise<void> {
  const packet = magicPacket(mac);           // validate before we bother opening a socket
  const targets = [...new Set([broadcast, directedBroadcast()])].filter(Boolean) as string[];
  const sock = await Bun.udpSocket({});
  const failures: string[] = [];
  let sent = 0;
  try {
    sock.setBroadcast(true);                 // SO_BROADCAST; without it every send below is EACCES
    for (const target of targets) {
      for (let i = 0; i < REPEATS; i++) {
        try { sock.send(packet, WOL_PORT, target); sent++; }
        catch (e: any) { failures.push(`${target}: ${e?.code ?? e?.message ?? e}`); break; }
      }
    }
    await Bun.sleep(0);                      // let the loop flush before the close below
  } finally {
    sock.close();
  }
  if (sent === 0) throw new Error(`wake: no magic packet left this machine (${failures.join("; ") || "no broadcast address"})`);
}

/**
 * This LAN's broadcast address (address | ~netmask). The magic packet has to be a
 * broadcast because a sleeping machine answers no ARP, so there is no address to unicast
 * to; the directed form is the one that works on every platform we run on.
 */
function directedBroadcast(): string | null {
  const iface = primaryIface();
  if (!iface) return null;
  const ip = iface.info.address.split(".").map(Number);
  const mask = String(iface.info.netmask ?? "").split(".").map(Number);
  if (ip.length !== 4 || mask.length !== 4 || [...ip, ...mask].some((n) => !Number.isInteger(n))) return null;
  return ip.map((octet, i) => octet | (~mask[i] & 0xff)).join(".");
}

/** All-zero is what a virtual NIC reports; 02:00:00:00:00:00 is macOS's redaction. */
function usableMac(mac: string): boolean {
  return /^[0-9a-f]{2}(:[0-9a-f]{2}){5}$/.test(mac) && mac !== "00:00:00:00:00:00" && mac !== "02:00:00:00:00:00";
}

/**
 * macOS hands unentitled processes 02:00:00:00:00:00 from getifaddrs(), which is what
 * node/bun's networkInterfaces() surfaces — a placeholder that wakes nothing. ifconfig
 * still prints the address the interface is actually using, and that is the one to
 * target: with Private Wi-Fi Address on, the sleeping NIC listens for the randomised
 * address, not the one printed on the box.
 */
function macFromIfconfig(iface: string): string | null {
  if (process.platform !== "darwin") return null;
  try {
    const out = Bun.spawnSync(["/sbin/ifconfig", iface]).stdout?.toString() ?? "";
    const m = out.match(/^\s*ether\s+([0-9a-f]{2}(?::[0-9a-f]{2}){5})/im);
    return m && usableMac(m[1].toLowerCase()) ? m[1].toLowerCase() : null;
  } catch { return null; }
}

// One spawn per minute at worst. The answer only changes when the machine joins a
// different network (a new private Wi-Fi address), so a short TTL beats both a
// per-request fork and a value cached for the daemon's whole life.
const MAC_TTL_MS = 60_000;
let macCache: { at: number; mac: string | null } | null = null;

/**
 * The MAC a peer should aim a magic packet at: the first non-internal IPv4 interface
 * that looks like real hardware and is really on a network. Null when there is none (a
 * container, or a box reachable only over Tailscale) — the honest answer, since waking
 * it is impossible from here anyway.
 */
export function primaryMac(): string | null {
  const now = Date.now();
  if (macCache && now - macCache.at < MAC_TTL_MS) return macCache.mac;
  const iface = primaryIface();
  const reported = String(iface?.info.mac ?? "").toLowerCase();
  const mac = !iface ? null : usableMac(reported) ? reported : macFromIfconfig(iface.name);
  macCache = { at: now, mac };
  return mac;
}

/**
 * The primary interface's IPv4 address and netmask — what /health shares so a phone
 * can compute this machine's directed broadcast later and judge whether a wake peer
 * is actually on the same LAN. Null when there is no real interface, same as
 * primaryMac(): the honest answer for a container or a Tailscale-only box.
 */
export function primaryIPv4(): { address: string; netmask: string } | null {
  const iface = primaryIface();
  if (!iface) return null;
  return { address: iface.info.address, netmask: String(iface.info.netmask ?? "") };
}

/** The one interface this machine is actually on a LAN through, or null. */
function primaryIface(): { name: string; info: os.NetworkInterfaceInfo } | null {
  for (const [name, addrs] of Object.entries(os.networkInterfaces())) {
    if (VIRTUAL_IFACE.test(name)) continue;
    // A 169.254 address means DHCP never answered: the NIC exists but is on no LAN.
    const ipv4 = (addrs ?? []).find((a) => a.family === "IPv4" && !a.internal && !a.address.startsWith("169.254."));
    if (ipv4) return { name, info: ipv4 };
  }
  return null;
}

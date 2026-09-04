// redact.ts — every string that leaves this Mac for a phone, a watch, Apple's push
// servers or the events file passes through redact() first.
//
// Why: agents and shells print secrets. `cat .env`, a failing curl with its bearer
// header, a stack trace with a connection string. Before 0.6 those bytes went to the
// Lock Screen (through APNs), into ~/.mesh/agent-events.jsonl, and to the watch. Now
// they are replaced before any of that, and every distinct secret seen is counted in a
// ledger keyed by a fingerprint — never the secret — so the owner can rotate it.
//
// Rules of the module:
//  - The fingerprint is the first 6 hex of sha256(secret). Not reversible for anything
//    with real entropy; enough to match a redacted line to a ledger row.
//  - A redacted value keeps only the prefix that names its kind (`ghp_`, `sk-ant-`),
//    so a reader knows WHAT was hidden without seeing any of it.
//  - Known secrets (this daemon's own token, every peer token in hosts.json, the
//    process's *_TOKEN/*_KEY/*_SECRET env values) are matched EXACTLY. That is what
//    catches a 64-hex mesh token without redacting every sha256 checksum a build prints.
//  - redact() is pure. record() is the only side effect, and only meshd calls it; the
//    bridge process posts its findings to meshd over loopback so one process owns the
//    ledger file.
import { createHash } from "node:crypto";
import { mkdir, readFile, rename, writeFile, chmod } from "node:fs/promises";
import { homedir } from "node:os";
import { dirname, join } from "node:path";

export type Channel = "event" | "output" | "bridge" | "hook";
export type Finding = { kind: string; hint: string; fp: string };
export type ExposureStatus = "open" | "rotated" | "ignored";
export type Exposure = {
  fp: string;
  kind: string;
  hint: string;
  first: string;
  last: string;
  count: number;
  channels: Channel[];
  status: ExposureStatus;
};

/// Each rule's regex either matches the whole secret, or has two groups:
/// group 1 = context kept verbatim (`Bearer `, `https://user:`), group 2 = the secret.
/// `keep` = how many leading characters of the secret stay visible (its kind prefix).
type Rule = { kind: string; re: RegExp; keep: number; groups?: true };

const RULES: Rule[] = [
  { kind: "private-key", re: /-----BEGIN [A-Z ]*PRIVATE KEY-----[\s\S]*?-----END [A-Z ]*PRIVATE KEY-----/g, keep: 0 },
  { kind: "aws-access-key", re: /\b(?:AKIA|ASIA)[A-Z0-9]{16}\b/g, keep: 4 },
  { kind: "github-token", re: /\bgithub_pat_[A-Za-z0-9_]{22,255}\b/g, keep: 11 },
  { kind: "github-token", re: /\bgh[opusr]_[A-Za-z0-9]{36,255}\b/g, keep: 4 },
  { kind: "anthropic-key", re: /\bsk-ant-[A-Za-z0-9_-]{20,}/g, keep: 7 },
  { kind: "openai-key", re: /\bsk-(?:proj-|svcacct-|admin-)?[A-Za-z0-9_-]{20,}/g, keep: 3 },
  { kind: "slack-token", re: /\bxox[abprs]-[A-Za-z0-9-]{10,}/g, keep: 5 },
  { kind: "google-api-key", re: /\bAIza[0-9A-Za-z_-]{35}\b/g, keep: 4 },
  { kind: "stripe-key", re: /\b[sr]k_(?:live|test)_[A-Za-z0-9]{16,}\b/g, keep: 8 },
  { kind: "hf-token", re: /\bhf_[A-Za-z0-9]{30,}\b/g, keep: 3 },
  { kind: "npm-token", re: /\bnpm_[A-Za-z0-9]{36}\b/g, keep: 4 },
  { kind: "jwt", re: /\beyJ[A-Za-z0-9_-]{8,}\.eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\b/g, keep: 3 },
  { kind: "bearer", re: /(\bBearer\s+)([A-Za-z0-9._~+/=-]{16,})/g, keep: 0, groups: true },
  // `•` is excluded so an already-redacted value is never matched again (re-redacting a
  // stored event must be a no-op, or its fingerprint drifts away from the ledger's).
  { kind: "url-credentials", re: /(\b[a-z][a-z0-9+.-]*:\/\/[^\s:@/•]+:)([^\s@/•\[\]]+)(?=@)/gi, keep: 0, groups: true },
  // `API_KEY=…`, `password: …`, `"token": "…"` — a value of 16+ characters after a
  // secret-shaped name. Paths are excluded below (looksLikePath) so
  // `TOKEN_FILE=/Users/x/.mesh/token` stays readable.
  { kind: "assignment", re: /(\b(?:api[_-]?key|secret|token|passw(?:or)?d|auth(?:orization)?)[A-Za-z0-9_]*\s*[=:]\s*["']?)([A-Za-z0-9_\-.+/=]{16,})/gi, keep: 0, groups: true },
];

const MASK = "••••••";

function fingerprint(secret: string): string {
  return createHash("sha256").update(secret, "utf8").digest("hex").slice(0, 6);
}

function looksLikePath(value: string): boolean {
  if (/^[./~$]/.test(value)) return true;
  // Two or more slashes and nothing base64-ish about it: a path, not a key.
  const slashes = (value.match(/\//g) ?? []).length;
  return slashes >= 2 && !/[+=]/.test(value);
}

// ---------- known secrets (exact match) ----------
// hint → value. The hint is what the ledger shows (`MESHD_TOKEN`, `hosts.json`); the
// value never leaves this map.
const known = new Map<string, string>();
let knownRe: RegExp | null = null;

function escapeRe(s: string): string {
  return s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

/// Register secrets to match exactly. Values shorter than 12 characters are ignored:
/// they would redact ordinary words, and a token that short is the doctor's problem.
export function addKnownSecrets(entries: Iterable<[hint: string, value: string]>): void {
  for (const [hint, value] of entries) {
    if (!value || value.length < 12) continue;
    known.set(value, hint);
  }
  const values = [...known.keys()].sort((a, b) => b.length - a.length);
  knownRe = values.length ? new RegExp(values.map(escapeRe).join("|"), "g") : null;
}

/// The process env's secret-shaped variables, for addKnownSecrets.
export function envSecrets(env: NodeJS.ProcessEnv = process.env): Array<[string, string]> {
  const out: Array<[string, string]> = [];
  for (const [name, value] of Object.entries(env)) {
    if (!value) continue;
    if (/(TOKEN|SECRET|PASSWORD|PASSWD|API_KEY|PRIVATE_KEY|ACCESS_KEY)$/i.test(name)) out.push([name, value]);
  }
  return out;
}

// ---------- redact ----------
export function redact(text: string): { text: string; findings: Finding[] } {
  const direct = redactOnce(text);
  if (direct.findings.length || !/\r(?!\n)/.test(text)) return direct;
  // A shell's line editor redraws a long typed line with " \r" at the wrap column,
  // splitting a token in two (seen live: `ghp_ABCDEFGHIJKLMNOPQRST \rUVWXYZ…`). Match
  // the flattened text; when that finds something, the flattened text is what ships —
  // a wrap marker is cosmetic, a leaked token is not.
  const flattened = redactOnce(text.replace(/ ?\r(?!\n)/g, ""));
  return flattened.findings.length ? flattened : direct;
}

function redactOnce(text: string): { text: string; findings: Finding[] } {
  if (!text) return { text, findings: [] };
  const findings: Finding[] = [];
  let out = text;
  if (knownRe) {
    out = out.replace(knownRe, (secret) => {
      const fp = fingerprint(secret);
      findings.push({ kind: "known-secret", hint: known.get(secret) ?? "known", fp });
      return `${MASK}[${fp}]`;
    });
  }
  for (const rule of RULES) {
    out = out.replace(rule.re, (match: string, g1?: string, g2?: string) => {
      // Without capture groups the replacer's 2nd/3rd arguments are the offset and
      // the whole input, so grouping is declared per rule, never inferred.
      const grouped = rule.groups === true && typeof g2 === "string";
      const secret = grouped ? g2 : match;
      if (rule.kind === "assignment" && looksLikePath(secret)) return match;
      const fp = fingerprint(secret);
      const shown = secret.slice(0, rule.keep);
      findings.push({ kind: rule.kind, hint: shown || (grouped ? (g1 ?? "").trim() : rule.kind), fp });
      return `${grouped ? g1 : ""}${shown}${MASK}[${fp}]`;
    });
  }
  return { text: out, findings };
}

/// A private key printed to a terminal spans many lines, and the bridge sees one line
/// at a time: this remembers that a BEGIN was seen and hides everything up to END.
export function createLineRedactor(): (line: string) => { text: string; findings: Finding[] } {
  let inKey = false;
  return (line: string) => {
    if (inKey) {
      if (/-----END [A-Z ]*PRIVATE KEY-----/.test(line)) inKey = false;
      return { text: "", findings: [] };
    }
    if (/-----BEGIN [A-Z ]*PRIVATE KEY-----/.test(line) && !/-----END/.test(line)) {
      inKey = true;
      const fp = fingerprint(line);
      return { text: `-----PRIVATE KEY ${MASK}[${fp}]-----`, findings: [{ kind: "private-key", hint: "PEM", fp }] };
    }
    return redact(line);
  };
}

// ---------- ledger ----------
const LEDGER_PATH = process.env.MESHD_EXPOSURES_PATH ?? join(homedir(), ".mesh", "exposures.json");
let ledger: Map<string, Exposure> | null = null;
let writing: Promise<void> = Promise.resolve();

async function loadLedger(): Promise<Map<string, Exposure>> {
  if (ledger) return ledger;
  const raw = await readFile(LEDGER_PATH, "utf8").catch(() => "");
  const map = new Map<string, Exposure>();
  if (raw) {
    try {
      for (const item of JSON.parse(raw) as Exposure[]) if (item?.fp) map.set(item.fp, item);
    } catch { /* a corrupt ledger starts over; the secrets are not in it anyway */ }
  }
  ledger = map;
  return map;
}

function persist(map: Map<string, Exposure>): Promise<void> {
  // Serialized, atomic (temp + rename), mode 600: the ledger names kinds and
  // fingerprints only, but it still says which providers this Mac holds keys for.
  writing = writing.then(async () => {
    await mkdir(dirname(LEDGER_PATH), { recursive: true, mode: 0o700 });
    const tmp = `${LEDGER_PATH}.tmp`;
    await writeFile(tmp, JSON.stringify([...map.values()], null, 2), { mode: 0o600 });
    await chmod(tmp, 0o600);
    await rename(tmp, LEDGER_PATH);
  }).catch(() => {});
  return writing;
}

/// Sightings of the same secret on the same polled channel inside `dedupeMs` count once:
/// the output route is polled every 0.5–2 s, and a key sitting on screen for a minute is
/// one exposure, not sixty.
const recent = new Map<string, number>();

/// Count findings. Same fingerprint → same row, count +1, channel added.
export async function record(findings: Finding[], channel: Channel, dedupeMs = 0): Promise<void> {
  if (!findings.length) return;
  const map = await loadLedger();
  const nowMs = Date.now();
  const now = new Date(nowMs).toISOString();
  let changed = false;
  for (const f of findings) {
    if (dedupeMs > 0) {
      const key = `${channel}:${f.fp}`;
      const seen = recent.get(key);
      if (seen !== undefined && nowMs - seen < dedupeMs) continue;
      recent.set(key, nowMs);
      if (recent.size > 5000) recent.delete(recent.keys().next().value as string);
    }
    changed = true;
    const row = map.get(f.fp);
    if (row) {
      row.count += 1;
      row.last = now;
      if (!row.channels.includes(channel)) row.channels.push(channel);
    } else {
      map.set(f.fp, { fp: f.fp, kind: f.kind, hint: f.hint, first: now, last: now, count: 1, channels: [channel], status: "open" });
    }
  }
  if (changed) await persist(map);
}

/// redact + record in one call — what every production choke point uses.
export async function redactAndRecord(text: string, channel: Channel, dedupeMs = 0): Promise<string> {
  const { text: clean, findings } = redact(text);
  if (findings.length) record(findings, channel, dedupeMs).catch(() => {});
  return clean;
}

export async function listExposures(): Promise<{ count: number; open: number; items: Exposure[] }> {
  const map = await loadLedger();
  const items = [...map.values()].sort((a, b) => (a.last < b.last ? 1 : -1));
  return { count: items.length, open: items.filter((i) => i.status === "open").length, items };
}

export async function setExposureStatus(fp: string, status: ExposureStatus): Promise<Exposure | null> {
  if (!["open", "rotated", "ignored"].includes(status)) return null;
  const map = await loadLedger();
  const row = map.get(fp);
  if (!row) return null;
  row.status = status;
  await persist(map);
  return row;
}

// ---------- HTTP surface (mounted by server.ts) ----------
function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });
}

/// GET /exposures · POST /exposures/<fp> {status} · POST /exposures/record {findings, channel}
/// (the last one is how the bridge, a separate process, reports into this ledger).
export async function handleExposures(req: Request, url: URL): Promise<Response | null> {
  if (url.pathname === "/exposures" && req.method === "GET") return json(await listExposures());
  if (url.pathname === "/exposures/record" && req.method === "POST") {
    const body = (await req.json().catch(() => ({}))) as { findings?: Finding[]; channel?: Channel };
    const findings = Array.isArray(body.findings)
      ? body.findings.filter((f) => f && /^[0-9a-f]{6}$/.test(String(f.fp))).map((f) => ({ kind: String(f.kind).slice(0, 40), hint: String(f.hint).slice(0, 40), fp: String(f.fp) }))
      : [];
    await record(findings, body.channel === "bridge" ? "bridge" : "hook");
    return json({ ok: true, recorded: findings.length });
  }
  const m = url.pathname.match(/^\/exposures\/([0-9a-f]{6})$/);
  if (m && req.method === "POST") {
    const body = (await req.json().catch(() => ({}))) as { status?: string };
    const row = await setExposureStatus(m[1], body.status as ExposureStatus);
    return row ? json(row) : json({ ok: false, error: "no such exposure or bad status" }, 404);
  }
  return null;
}

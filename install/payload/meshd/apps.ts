// apps.ts — the apps an agent built for you, served and installed from this Mac.
//
// Two routes for two kinds of user. A web app (kind "pwa") is a folder of static files at
// ~/.mesh/apps/<slug>/site/, served at /a/<slug>-<key>/ WITHOUT the bearer token, because
// Safari cannot send one and "Add to Home Screen" needs a plain URL; the 8-hex key in the
// path is what stands in for auth — unguessable, and only ever shown to the owner. A native
// app (kind "native") is a built .app the `mesh apps install` CLI pushes onto the paired
// iPhone (devicectl) or a booted simulator (simctl); POST /built-apps/<slug>/install shells out to
// that one implementation so the phone button and the terminal do the identical thing.
//
// A native app the CLI also packaged as an .ipa gets the same token-free /a/<slug>-<key>/
// folder: manifest.plist + the .ipa + icon.png, which is exactly what iOS's own
// `itms-services://?action=download-manifest&url=…` installer wants. iOS only fetches that
// manifest over HTTPS with a public certificate, so the absolute URLs inside it come from
// `otaBase` in ~/.mesh/apps.json — `mesh apps ota --enable` sets it to this machine's
// Tailscale Serve name — and never from the plain-HTTP LAN address.
//
// The CLI (install/payload/bin/mesh) owns writing ~/.mesh/apps; this file only reads it.
import { readdir, readFile, realpath, stat } from "node:fs/promises";
import { homedir } from "node:os";
import { extname, join, resolve, sep } from "node:path";

export type AppMeta = {
  slug: string;
  name: string;
  kind: "pwa" | "native";
  key?: string;       // path key (pwa always; native once an .ipa was packaged)
  url?: string;       // pwa: the LAN URL the CLI printed
  app?: string;       // native: path to the built .app
  bundleId?: string;  // native
  ipa?: string;       // native: file name of the packaged .ipa inside the app folder
  icon?: string;      // native: file name of the icon png, when the bundle had one
  version?: string;   // native: CFBundleShortVersionString
  updated?: string;
};

const MESH_HOME = process.env.MESH_HOME ?? join(homedir(), ".mesh");
const APPS_DIR = process.env.MESH_APPS_DIR ?? join(MESH_HOME, "apps");
const APPS_CONFIG = join(MESH_HOME, "apps.json");

/// The HTTPS origin iOS may fetch install manifests from, or null when wireless install
/// is off. Read per request: `mesh apps ota` edits the file while the daemon runs.
async function otaBase(): Promise<string | null> {
  const raw = await readFile(APPS_CONFIG, "utf8").catch(() => "");
  try {
    const base = String(JSON.parse(raw)?.otaBase ?? "").replace(/\/+$/, "");
    return /^https:\/\/[^/\s]+$/.test(base) ? base : null;
  } catch {
    return null;
  }
}

const esc = (s: string) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");

/// Apple's wireless-install manifest: one item, the package, and the icon when there is one.
function manifestPlist(root: string, m: AppMeta): string {
  const asset = (kind: string, file: string) =>
    `<dict><key>kind</key><string>${kind}</string><key>url</key><string>${esc(root)}/${esc(file)}</string></dict>`;
  const assets = asset("software-package", m.ipa!) +
    (m.icon ? asset("display-image", m.icon) + asset("full-size-image", m.icon) : "");
  return `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>items</key><array><dict>
<key>assets</key><array>${assets}</array>
<key>metadata</key><dict><key>bundle-identifier</key><string>${esc(m.bundleId ?? "")}</string><key>bundle-version</key><string>${esc(m.version ?? "1.0")}</string><key>kind</key><string>software</string><key>title</key><string>${esc(m.name)}</string></dict>
</dict></array></dict></plist>
`;
}

function itmsUrl(root: string): string {
  return `itms-services://?action=download-manifest&url=${encodeURIComponent(`${root}/manifest.plist`)}`;
}

/// The page behind /a/<slug>-<key>/ for a native app: one Install button, opened in Safari
/// on the phone. Says so plainly when the origin is not HTTPS, because iOS will refuse.
function installPage(root: string, m: AppMeta, https: boolean): string {
  const sub = [m.version ? `v${m.version}` : "", m.bundleId ?? ""].filter(Boolean).join(" · ");
  const note = https
    ? `<p>iOS asks to install; the app then appears on the Home Screen. First install on a phone needs Developer Mode on (Settings → Privacy &amp; Security).</p>`
    : `<p class="warn">This page is served over plain HTTP, and iOS only installs from HTTPS. On the machine run <code>mesh apps ota --enable</code> (Tailscale) and open the address it prints instead.</p>`;
  return `<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Install ${esc(m.name)}</title>
<style>body{font:17px -apple-system,system-ui,sans-serif;margin:0;padding:48px 24px;text-align:center;color:#111;background:#fff}img{width:96px;height:96px;border-radius:22px}h1{font-size:26px;margin:16px 0 4px}p{color:#666;font-size:14px;line-height:1.45;max-width:360px;margin:12px auto}.b{display:block;margin:28px auto 0;padding:15px 20px;border-radius:14px;background:#0a84ff;color:#fff;text-decoration:none;font-weight:600;max-width:320px}.warn{color:#b45309}code{font-size:13px}</style>
${m.icon ? `<img src="${esc(m.icon)}" alt="">` : ""}
<h1>${esc(m.name)}</h1><p>${esc(sub)}</p>
<a class="b" href="${esc(itmsUrl(root))}">Install on this iPhone</a>
${note}`;
}
const SLUG = /^[a-z0-9][a-z0-9-]{1,40}$/;
const KEY = /^[0-9a-f]{8}$/;

const TYPES: Record<string, string> = {
  ".html": "text/html; charset=utf-8",
  ".js": "application/javascript; charset=utf-8",
  ".mjs": "application/javascript; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".json": "application/json; charset=utf-8",
  ".webmanifest": "application/manifest+json; charset=utf-8",
  ".png": "image/png",
  ".jpg": "image/jpeg",
  ".jpeg": "image/jpeg",
  ".svg": "image/svg+xml",
  ".ico": "image/x-icon",
  ".webp": "image/webp",
  ".woff2": "font/woff2",
  ".woff": "font/woff",
  ".txt": "text/plain; charset=utf-8",
  ".wasm": "application/wasm",
  ".map": "application/json; charset=utf-8",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });
}

async function readMeta(slug: string): Promise<AppMeta | null> {
  if (!SLUG.test(slug)) return null;
  const raw = await readFile(join(APPS_DIR, slug, "meta.json"), "utf8").catch(() => "");
  if (!raw) return null;
  try {
    const m = JSON.parse(raw) as AppMeta;
    if (m?.slug !== slug || (m.kind !== "pwa" && m.kind !== "native")) return null;
    return m;
  } catch {
    return null;
  }
}

export type AppRow = Omit<AppMeta, "app" | "key" | "ipa" | "icon"> & {
  install?: string;   // native + .ipa + otaBase: the itms-services:// URL the phone opens
};

/// Every app the CLI registered, newest first. Native rows carry no .app path (the
/// phone has no use for a Mac filesystem path); the key never travels except inside a url.
/// `install` is present only when the phone can really use it: an .ipa exists AND the
/// machine has an HTTPS origin for it.
export async function listApps(host: string, port: number): Promise<{ apps: AppRow[]; otaBase: string | null }> {
  const names = await readdir(APPS_DIR).catch(() => [] as string[]);
  const base = await otaBase();
  const apps: AppRow[] = [];
  for (const slug of names) {
    const m = await readMeta(slug);
    if (!m) continue;
    const row: AppRow = { slug: m.slug, name: m.name, kind: m.kind, bundleId: m.bundleId, version: m.version, updated: m.updated };
    if (m.kind === "pwa" && m.key) row.url = m.url ?? `http://${host}:${port}/a/${m.slug}-${m.key}/`;
    if (m.kind === "native" && m.key && m.ipa && base) {
      const root = `${base}/a/${m.slug}-${m.key}`;
      row.url = `${root}/`;
      row.install = itmsUrl(root);
    }
    apps.push(row);
  }
  apps.sort((a, b) => String(b.updated ?? "").localeCompare(String(a.updated ?? "")));
  return { apps, otaBase: base };
}

/// A native app's wireless-install folder: /, manifest.plist, the .ipa and the icon.
/// The manifest's absolute URLs use otaBase when set, else the origin this request came
/// in on (X-Forwarded-* from a reverse proxy, then Host) — a client can only steer the
/// URLs handed back to itself, so trusting those headers here costs nothing.
async function serveNative(req: Request | undefined, slug: string, key: string, meta: AppMeta, rest: string): Promise<Response> {
  const dir = join(APPS_DIR, slug);
  const base = (await otaBase()) ?? (() => {
    const h = req?.headers;
    const proto = h?.get("x-forwarded-proto") ?? "http";
    const host = h?.get("x-forwarded-host") ?? h?.get("host") ?? "127.0.0.1";
    return `${proto}://${host}`;
  })();
  const root = `${base}/a/${slug}-${key}`;
  const file = decodeURIComponent(rest).replace(/^\/+/, "");
  if (file === "") return new Response(installPage(root, meta, base.startsWith("https://")), { headers: { "content-type": "text/html; charset=utf-8", "cache-control": "no-cache" } });
  if (file === "manifest.plist") return new Response(manifestPlist(root, meta), { headers: { "content-type": "application/xml; charset=utf-8", "cache-control": "no-cache" } });
  // Only the two files the CLI wrote — never anything else in the folder (meta.json).
  if (file !== meta.ipa && file !== meta.icon) return json({ error: "not found" }, 404);
  const st = await stat(join(dir, file)).catch(() => null);
  if (!st?.isFile()) return json({ error: "not found" }, 404);
  const type = file.endsWith(".png") ? "image/png" : "application/octet-stream";
  return new Response(Bun.file(join(dir, file)), { headers: { "content-type": type, "content-length": String(st.size), "cache-control": "no-cache" } });
}

/// /a/<slug>-<key>/<path> → a file under ~/.mesh/apps/<slug>/site/ (web app), or the
/// wireless-install folder of a packaged native app. Wrong key, unknown slug or a path
/// that escapes the site folder all answer the same 404 — nothing tells a guesser which
/// part was wrong.
export async function serveApp(pathname: string, req?: Request): Promise<Response | null> {
  const m = pathname.match(/^\/a\/([a-z0-9][a-z0-9-]{1,40})-([0-9a-f]{8})(\/.*)?$/);
  if (!m) return null;
  const [, slug, key, rest] = m;
  if (!KEY.test(key)) return json({ error: "not found" }, 404);
  const meta = await readMeta(slug);
  if (!meta || !meta.key || meta.key !== key) return json({ error: "not found" }, 404);
  if (meta.kind === "native" && !meta.ipa) return json({ error: "not found" }, 404);
  if (rest === undefined) {
    // Relative asset URLs in the page need the trailing slash.
    return new Response(null, { status: 302, headers: { location: `/a/${slug}-${key}/` } });
  }
  if (meta.kind === "native") return serveNative(req, slug, key, meta, rest);
  const site = join(APPS_DIR, slug, "site");
  let rel = decodeURIComponent(rest).replace(/^\/+/, "");
  if (rel === "" || rel.endsWith("/")) rel += "index.html";
  const target = resolve(site, rel);
  if (target !== site && !target.startsWith(site + sep)) return json({ error: "not found" }, 404);
  let real: string;
  try { real = await realpath(target); } catch { return json({ error: "not found" }, 404); }
  const siteReal = await realpath(site).catch(() => site);
  if (real !== siteReal && !real.startsWith(siteReal + sep)) return json({ error: "not found" }, 404);
  const st = await stat(real).catch(() => null);
  if (!st) return json({ error: "not found" }, 404);
  if (st.isDirectory()) return new Response(null, { status: 302, headers: { location: `${pathname.replace(/\/?$/, "/")}` } });
  const type = TYPES[extname(real).toLowerCase()] ?? "application/octet-stream";
  return new Response(Bun.file(real), {
    headers: {
      "content-type": type,
      // The page itself must revalidate so a republished app shows up; assets can cache.
      "cache-control": type.startsWith("text/html") ? "no-cache" : "public, max-age=300",
    },
  });
}

/// POST /built-apps/<slug>/install {target: "device"|"sim"} → runs `mesh apps install`, the
/// single implementation the terminal uses too. The CLI's last stdout line is the verdict.
export async function installApp(slug: string, target: string, meshBin: string): Promise<{ ok: boolean; error?: string; detail?: string }> {
  const meta = await readMeta(slug);
  if (!meta) return { ok: false, error: "no such app" };
  if (meta.kind !== "native") return { ok: false, error: "web apps are opened, not installed — use the url" };
  const args = [meshBin, "apps", "install", slug];
  if (target === "sim") args.push("--sim");
  const proc = Bun.spawn(args, { stdout: "pipe", stderr: "pipe" });
  const timer = setTimeout(() => proc.kill(), 120_000);
  const [out, err] = await Promise.all([new Response(proc.stdout).text(), new Response(proc.stderr).text()]);
  const code = await proc.exited;
  clearTimeout(timer);
  const last = out.trim().split("\n").filter(Boolean).at(-1) ?? "";
  if (code === 0) return { ok: true, detail: last };
  return { ok: false, error: last || err.trim().split("\n").at(-1) || `mesh apps install exited ${code}` };
}

/// Mounted by server.ts AFTER the auth gate: GET /built-apps, POST /built-apps/<slug>/install.
/// (`/apps` is taken: it lists and activates Mac applications — see input.ts.)
/// (serveApp is mounted BEFORE it — see the comment at the top.)
export async function handleApps(req: Request, url: URL, ctx: { host: string; port: number; meshBin: string }): Promise<Response | null> {
  if (url.pathname === "/built-apps" && req.method === "GET") return json(await listApps(ctx.host, ctx.port));
  const m = url.pathname.match(/^\/built-apps\/([a-z0-9][a-z0-9-]{1,40})\/install$/);
  if (m && req.method === "POST") {
    const body = (await req.json().catch(() => ({}))) as { target?: string };
    const target = body.target === "sim" ? "sim" : "device";
    const result = await installApp(m[1], target, ctx.meshBin);
    return json(result, result.ok ? 200 : 400);
  }
  return null;
}

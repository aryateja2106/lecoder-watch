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
// The CLI (install/payload/bin/mesh) owns writing ~/.mesh/apps; this file only reads it.
import { readdir, readFile, realpath, stat } from "node:fs/promises";
import { homedir } from "node:os";
import { extname, join, resolve, sep } from "node:path";

export type AppMeta = {
  slug: string;
  name: string;
  kind: "pwa" | "native";
  key?: string;       // pwa: the path key
  url?: string;       // pwa: the LAN URL the CLI printed
  app?: string;       // native: path to the built .app
  bundleId?: string;  // native
  updated?: string;
};

const MESH_HOME = process.env.MESH_HOME ?? join(homedir(), ".mesh");
const APPS_DIR = process.env.MESH_APPS_DIR ?? join(MESH_HOME, "apps");
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

/// Every app the CLI registered, newest first. Native rows carry no .app path (the
/// phone has no use for a Mac filesystem path); the key never travels except inside url.
export async function listApps(host: string, port: number): Promise<{ apps: Array<Omit<AppMeta, "app" | "key">> }> {
  const names = await readdir(APPS_DIR).catch(() => [] as string[]);
  const apps: Array<Omit<AppMeta, "app" | "key">> = [];
  for (const slug of names) {
    const m = await readMeta(slug);
    if (!m) continue;
    const url = m.kind === "pwa" && m.key ? (m.url ?? `http://${host}:${port}/a/${m.slug}-${m.key}/`) : undefined;
    apps.push({ slug: m.slug, name: m.name, kind: m.kind, url, bundleId: m.bundleId, updated: m.updated });
  }
  apps.sort((a, b) => String(b.updated ?? "").localeCompare(String(a.updated ?? "")));
  return { apps };
}

/// /a/<slug>-<key>/<path> → a file under ~/.mesh/apps/<slug>/site/. Wrong key, unknown
/// slug or a path that escapes the site folder all answer the same 404 — nothing tells
/// a guesser which part was wrong.
export async function serveApp(pathname: string): Promise<Response | null> {
  const m = pathname.match(/^\/a\/([a-z0-9][a-z0-9-]{1,40})-([0-9a-f]{8})(\/.*)?$/);
  if (!m) return null;
  const [, slug, key, rest] = m;
  if (!KEY.test(key)) return json({ error: "not found" }, 404);
  const meta = await readMeta(slug);
  if (!meta || meta.kind !== "pwa" || meta.key !== key) return json({ error: "not found" }, 404);
  if (rest === undefined) {
    // Relative asset URLs in the page need the trailing slash.
    return new Response(null, { status: 302, headers: { location: `/a/${slug}-${key}/` } });
  }
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

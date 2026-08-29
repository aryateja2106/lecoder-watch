// File browsing for meshd — the part of "remote desktop" that works on a headless
// box. Pure Node/Bun filesystem calls, so it behaves identically on macOS and Linux
// with no X server, no VNC and no extra packages.
//
//   GET  /fs?path=/home/arya        -> { path, parent, entries: [...] }
//   GET  /fs/read?path=…[&max=]     -> { path, text, truncated } | binary download
//   POST /fs/mkdir  { path }
//   POST /fs/move   { from, to }
//   GET  /files                     -> browser page
//
// No path jail: this daemon already runs arbitrary shell for anyone holding the
// token, so restricting paths would be theatre rather than a boundary. Symlinks are
// reported, not followed, so a listing cannot wander somewhere surprising.
import { homedir } from "node:os";
import { join, dirname, resolve, basename } from "node:path";
import { readdir, stat, lstat, mkdir, rename, readFile } from "node:fs/promises";

const TEXT_LIMIT = 256 * 1024;

function json(data: any, status = 200) {
  return new Response(JSON.stringify(data), { status, headers: { "content-type": "application/json" } });
}

type Entry = {
  name: string;
  path: string;
  kind: "dir" | "file" | "link";
  size: number;
  modifiedISO: string | null;
};

async function listDirectory(target: string) {
  const path = resolve(target || homedir());
  const info = await stat(path).catch(() => null);
  if (!info) return { ok: false, error: `no such path: ${path}` };
  if (!info.isDirectory()) return { ok: false, error: `not a directory: ${path}` };

  const names = await readdir(path);
  const entries = await Promise.all(names.map(async (name): Promise<Entry | null> => {
    const full = join(path, name);
    // lstat, so a broken or looping symlink is a row rather than an exception.
    const s = await lstat(full).catch(() => null);
    if (!s) return null;
    return {
      name,
      path: full,
      kind: s.isSymbolicLink() ? "link" : s.isDirectory() ? "dir" : "file",
      size: s.size,
      modifiedISO: s.mtime ? s.mtime.toISOString() : null,
    };
  }));

  const rows = entries.filter((e): e is Entry => e !== null)
    // Directories first, then case-insensitive by name — the order a human expects.
    .sort((a, b) => (a.kind === "dir") === (b.kind === "dir")
      ? a.name.localeCompare(b.name, undefined, { sensitivity: "base" })
      : a.kind === "dir" ? -1 : 1);

  return { ok: true, path, parent: path === "/" ? null : dirname(path), home: homedir(), entries: rows };
}

async function readTextFile(target: string, max: number) {
  const path = resolve(target);
  const info = await stat(path).catch(() => null);
  if (!info || !info.isFile()) return json({ error: `not a file: ${path}` }, 404);

  const limit = Math.min(Math.max(max, 1024), TEXT_LIMIT);
  const buffer = await readFile(path);
  const slice = buffer.subarray(0, limit);
  // A NUL in the first slice means binary; hand it back as a download instead of
  // pretending it is text.
  if (slice.includes(0)) {
    return new Response(buffer, {
      headers: {
        "content-type": "application/octet-stream",
        "content-disposition": `attachment; filename="${basename(path).replace(/"/g, "")}"`,
      },
    });
  }
  return json({
    path,
    size: info.size,
    text: new TextDecoder().decode(slice),
    truncated: buffer.length > slice.length,
  });
}

export async function handleFiles(req: Request, url: URL): Promise<Response | null> {
  const path = url.pathname;

  if (path === "/files" && req.method === "GET") {
    const page = Bun.file(join(import.meta.dir, "files.html"));
    if (!(await page.exists())) return json({ error: "files.html missing" }, 404);
    return new Response(page, { headers: { "content-type": "text/html; charset=utf-8" } });
  }
  if (path === "/fs" && req.method === "GET") {
    const result = await listDirectory(url.searchParams.get("path") ?? homedir());
    return json(result, result.ok ? 200 : 404);
  }
  if (path === "/fs/read" && req.method === "GET") {
    const target = url.searchParams.get("path");
    if (!target) return json({ error: "path required" }, 400);
    return await readTextFile(target, Number(url.searchParams.get("max") ?? "65536") || 65536);
  }
  if (path === "/fs/mkdir" && req.method === "POST") {
    const body = (await req.json().catch(() => ({}))) as any;
    if (typeof body?.path !== "string" || !body.path) return json({ error: "path required" }, 400);
    await mkdir(resolve(body.path), { recursive: true });
    return json({ ok: true, path: resolve(body.path) }, 201);
  }
  if (path === "/fs/move" && req.method === "POST") {
    const body = (await req.json().catch(() => ({}))) as any;
    if (typeof body?.from !== "string" || typeof body?.to !== "string") {
      return json({ error: "from and to required" }, 400);
    }
    const to = resolve(body.to);
    // Refuse to clobber: a rename that silently destroys the destination is the kind
    // of thing you only notice afterwards.
    if (await Bun.file(to).exists()) return json({ error: `destination exists: ${to}` }, 409);
    await rename(resolve(body.from), to);
    return json({ ok: true, from: resolve(body.from), to });
  }
  return null;
}

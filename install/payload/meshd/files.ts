// File browsing for meshd — the part of "remote desktop" that works on a headless
// box. Pure Node/Bun filesystem calls, so it behaves identically on macOS and Linux
// with no X server, no VNC and no extra packages.
//
//   GET  /fs?path=/home/arya        -> { path, parent, entries: [...] }
//   GET  /fs/read?path=…[&max=][&raw=1] -> { path, text, truncated } | binary download
//   POST /fs/write?path=…             raw bytes -> { ok, path, bytes, sha256 }
//   POST /fs/mkdir  { path }
//   POST /fs/move   { from, to }
//   GET  /files                     -> browser page
//
// No path jail: this daemon already runs arbitrary shell for anyone holding the
// token, so restricting paths would be theatre rather than a boundary. Symlinks are
// reported, not followed, so a listing cannot wander somewhere surprising.
import { homedir } from "node:os";
import { join, dirname, resolve, basename, sep } from "node:path";
import { readdir, stat, lstat, mkdir, rename, readFile, unlink } from "node:fs/promises";

const TEXT_LIMIT = 256 * 1024;
const HASH_LIMIT = 64 * 1024 * 1024;
const WRITE_MAX = Number(process.env.MESHD_FS_WRITE_MAX) || 512 * 1024 * 1024;

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

function expandPath(target: string) {
  return resolve(target.startsWith("~/") ? join(homedir(), target.slice(2)) : target);
}

async function binaryResponse(path: string, size: number, body: Blob | Uint8Array) {
  const headers: Record<string, string> = {
    "content-type": "application/octet-stream",
    "content-disposition": `attachment; filename="${basename(path).replace(/"/g, "")}"`,
  };
  if (size <= HASH_LIMIT) {
    headers["x-mesh-sha256"] = new Bun.CryptoHasher("sha256")
      .update(new Uint8Array(await Bun.file(path).arrayBuffer())).digest("hex");
  }
  return new Response(body, { headers });
}

async function readTextFile(target: string, max: number, raw: boolean) {
  const path = expandPath(target);
  const info = await stat(path).catch(() => null);
  if (!info || !info.isFile()) return json({ error: `not a file: ${path}` }, 404);

  if (raw) return await binaryResponse(path, info.size, Bun.file(path));

  const limit = Math.min(Math.max(max, 1024), TEXT_LIMIT);
  const buffer = await readFile(path);
  const slice = buffer.subarray(0, limit);
  // A NUL in the first slice means binary; hand it back as a download instead of
  // pretending it is text.
  if (slice.includes(0)) {
    return await binaryResponse(path, info.size, buffer);
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
    return await readTextFile(target, Number(url.searchParams.get("max") ?? "65536") || 65536, url.searchParams.get("raw") === "1");
  }
  if (path === "/fs/write" && req.method === "POST") {
    const target = url.searchParams.get("path");
    if (!target) return json({ error: "path required" }, 400);
    const dest = expandPath(target);
    const meshHome = resolve(homedir(), ".mesh");
    if (dest === meshHome || dest.startsWith(meshHome + sep)) {
      return json({ error: "refusing to write inside ~/.mesh" }, 403);
    }
    if (await Bun.file(dest).exists() && url.searchParams.get("overwrite") !== "1") {
      return json({ error: `destination exists: ${dest}` }, 409);
    }
    const parent = dirname(dest);
    const parentInfo = await stat(parent).catch(() => null);
    if (!parentInfo) {
      if (url.searchParams.get("mkdirs") !== "1") return json({ error: `no such directory: ${parent}` }, 404);
      await mkdir(parent, { recursive: true });
    } else if (!parentInfo.isDirectory()) {
      return json({ error: `no such directory: ${parent}` }, 404);
    }
    const length = Number(req.headers.get("content-length"));
    if (Number.isFinite(length) && length > WRITE_MAX) return json({ error: `file exceeds ${WRITE_MAX} byte limit` }, 413);

    const part = `${dest}.part-${process.pid}`;
    const hasher = new Bun.CryptoHasher("sha256");
    let bytes = 0;
    // Stream to a sibling .part file and rename into place, so a half-written upload never
    // masquerades as the file. Bun.write(path, ReadableStream) silently wrote nothing on
    // Bun 1.3 (bytes:0, sha of empty) — the FileSink loop below is what actually streams.
    const sink = Bun.file(part).writer();
    try {
      if (req.body) {
        for await (const chunk of req.body as AsyncIterable<Uint8Array>) {
          bytes += chunk.byteLength;
          if (bytes > WRITE_MAX) {
            await sink.end();
            return json({ error: `file exceeds ${WRITE_MAX} byte limit` }, 413);
          }
          hasher.update(chunk);
          sink.write(chunk);
        }
      }
      await sink.end();
      await rename(part, dest);
      return json({ ok: true, path: dest, bytes, sha256: hasher.digest("hex") }, 201);
    } finally {
      await unlink(part).catch(() => {});
    }
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

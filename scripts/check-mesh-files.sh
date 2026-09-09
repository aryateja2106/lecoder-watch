#!/bin/sh
# files.ts self-check: text previews must not slurp whole files into heap, and the
# phone's fsList query encoding must not leave +/&/= raw (URL parsing corrupts them).
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
command -v bun >/dev/null 2>&1 || { echo "check-mesh-files: SKIP (bun not installed)"; exit 0; }
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cd "$ROOT/install/payload/meshd"

bun -e '
import { handleFiles } from "./files.ts";
import { mkdir, writeFile, chmod } from "node:fs/promises";
import { join } from "node:path";

const u = (p) => new URL("http://x" + p);
const dir = join(process.cwd(), ".check-mesh-files-" + process.pid);
await mkdir(dir, { recursive: true });

const bigPath = join(dir, "big.txt");
await writeFile(bigPath, "a".repeat(500_000));

const readUrl = "http://x/fs/read?path=" + encodeURIComponent(bigPath) + "&max=4096";
const res = await handleFiles(new Request(readUrl), new URL(readUrl));
const body = await res.json();
if (!body.truncated) throw new Error("a 500 KB file with max=4096 must be truncated");
if (body.text.length !== 4096) throw new Error(`expected 4096 bytes of text, got ${body.text.length}`);

const binPath = join(dir, "bin.dat");
await writeFile(binPath, Buffer.from([0, 1, 2, 3, 4, 5]));
const binUrl = "http://x/fs/read?path=" + encodeURIComponent(binPath);
const binRes = await handleFiles(new Request(binUrl), new URL(binUrl));
if (binRes.headers.get("content-type") !== "application/octet-stream") {
  throw new Error("binary file must stream as octet-stream");
}
const streamed = await new Response(binRes.body).arrayBuffer();
if (streamed.byteLength !== 6) throw new Error(`binary stream length ${streamed.byteLength}, want 6`);

const plusDir = join(dir, "C++ Projects");
await mkdir(plusDir);
const listUrl = "http://x/fs?path=" + encodeURIComponent(plusDir);
const listed = await handleFiles(new Request(listUrl), new URL(listUrl));
const list = await listed.json();
if (!list.ok || list.entries.length !== 0) {
  throw new Error("listing a + path must succeed when percent-encoded: " + JSON.stringify(list));
}

console.log("check-mesh-files: OK");
'

# Implementation guard: readTextFile must not call readFile on the whole file.
grep -q 'await open(path, "r")' "$ROOT/install/payload/meshd/files.ts" || {
  echo "FAIL: files.ts no longer bounds reads with open()"
  exit 1
}
if grep -q 'readFile(path)' "$ROOT/install/payload/meshd/files.ts"; then
  echo "FAIL: files.ts still calls readFile(path) — unbounded slurp may have returned"
  exit 1
fi

# Client half: +/&/= must not ride through urlQueryAllowed on fsList.
grep -q 'fsQueryAllowed' "$ROOT/Shared/MeshClient.swift" || {
  echo "FAIL: MeshClient.fsList no longer uses fsQueryAllowed"
  exit 1
}
grep -q 'remove(charactersIn: "+&=")' "$ROOT/Shared/MeshClient.swift" || {
  echo "FAIL: fsQueryAllowed must strip +, &, and = from allowed query chars"
  exit 1
}
echo "check-mesh-files: MeshClient wired"

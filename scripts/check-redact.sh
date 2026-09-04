#!/bin/sh
# redact.ts self-check: one fixture per rule is replaced and fingerprinted, benign
# strings that merely look secret-shaped (a sha256 checksum, a git SHA, a path assigned
# to TOKEN_FILE) are left alone, the ledger counts distinct secrets once per polled
# window, and the HTTP surface answers. A rule that "looks right" and silently matches
# nothing — or everything — is exactly what this pins down.
#
# The TypeScript below is a quoted heredoc: nothing in it is shell-expanded. The repo
# root reaches it through the environment.
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
command -v bun >/dev/null 2>&1 || { echo "check-redact: SKIP (bun not installed)"; exit 0; }
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cat >"$TMP/check.ts" <<'EOF'
const { redact, addKnownSecrets, envSecrets, createLineRedactor, record, listExposures, setExposureStatus, handleExposures } = await import(`${process.env.MESH_ROOT}/install/payload/meshd/redact.ts`);

let failed = 0;
function expect(name: string, ok: boolean, detail = "") {
  if (!ok) { failed++; console.log("FAIL " + name + (detail ? "  " + detail : "")); }
}
/// `secret` is the substring that must not survive; `mustKeep` the context that must.
function redacted(kind: string, hint: string, line: string, mustKeep: string, secret: string) {
  const r = redact(line);
  const f = r.findings.find((x) => x.kind === kind);
  expect(kind + " found", Boolean(f), JSON.stringify(r));
  if (f) expect(kind + " hint", f.hint === hint, f.hint + " != " + hint);
  expect(kind + " masked", !r.text.includes(secret) && r.text.includes("••••••["), r.text);
  expect(kind + " keeps context", r.text.includes(mustKeep), r.text + " lacks " + mustKeep);
  if (f) expect(kind + " fingerprint", /^[0-9a-f]{6}$/.test(f.fp), f.fp);
}
function untouched(name: string, line: string) {
  const r = redact(line);
  expect(name + " untouched", r.text === line && r.findings.length === 0, JSON.stringify(r));
}

const meshToken = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";
addKnownSecrets([["MESHD_TOKEN", meshToken], ["hosts.json", "peer-token-value-abcdefghij"], ["short", "tiny"]]);

redacted("github-token", "ghp_", "token ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghij123456 pushed", "pushed", "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghij123456");
redacted("github-token", "github_pat_", "github_pat_11ABCDEFG0abcdefghijklmnopqrstuvwxyz0123456789ABCDEFGHIJ", "github_pat_", "11ABCDEFG0abcdefghijklmnopqrstuvwxyz");
redacted("aws-access-key", "AKIA", "AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE", "AWS_ACCESS_KEY_ID=", "IOSFODNN7EXAMPLE");
redacted("anthropic-key", "sk-ant-", "ANTHROPIC_API_KEY=sk-ant-api03-abcdefghijklmnopqrstuvwxyz0123456789ABCDEF", "ANTHROPIC_API_KEY=sk-ant-", "api03-abcdefghijklmnopqrstuvwxyz");
redacted("openai-key", "sk-", "OPENAI_API_KEY=sk-proj-abcdefghijklmnopqrstuvwxyz0123456789", "OPENAI_API_KEY=sk-", "proj-abcdefghijklmnopqrstuvwxyz");
redacted("slack-token", "xoxb-", "xoxb-123456789012-abcdefghijkl", "xoxb-", "123456789012-abcdefghijkl");
redacted("google-api-key", "AIza", "AIzaSyA1234567890abcdefghijklmnopqrstuv", "AIza", "SyA1234567890abcdefghijklmnopqrstuv");
// Built at runtime: a literal that looks like a live Stripe key trips GitHub push protection.
redacted("stripe-key", "sk_live_", "sk_" + "live_" + "abcdefghijklmnopqrstuvwxyz", "sk_live_", "abcdefghijklmnopqrstuvwxyz");
redacted("hf-token", "hf_", "HF_TOKEN=hf_ABCDEFGHIJKLMNOPQRSTUVWXYZabcd012345", "HF_TOKEN=hf_", "ABCDEFGHIJKLMNOPQRSTUVWXYZabcd012345");
redacted("npm-token", "npm_", "npm_abcdefghijklmnopqrstuvwxyz0123456789", "npm_", "abcdefghijklmnopqrstuvwxyz0123456789");
redacted("jwt", "eyJ", "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dozjgNryP4J3jVmNHl0w5N_XgL0n3I9PlFUP0THsR8U", "eyJ", "eyJzdWIiOiIxMjM0NTY3ODkwIn0");
redacted("bearer", "Bearer", "Authorization: Bearer abcdefghijklmnopqrstuvwxyz012345", "Authorization: Bearer ", "abcdefghijklmnopqrstuvwxyz012345");
redacted("url-credentials", "postgres://user:", "postgres://user:s3cretPassw0rd@db.example.com:5432/app", "@db.example.com:5432/app", "s3cretPassw0rd");
redacted("assignment", "api_key =", "api_key = abcdefghijklmnop1234", "api_key = ", "abcdefghijklmnop1234");
redacted("known-secret", "MESHD_TOKEN", "curl -H 'Authorization: Bearer " + meshToken + "'", "curl -H 'Authorization: Bearer ", meshToken);
redacted("known-secret", "hosts.json", "peer says peer-token-value-abcdefghij ok", "peer says", "peer-token-value-abcdefghij");
redacted("private-key", "private-key", "-----BEGIN RSA PRIVATE KEY-----\nMIIEow\nAB\n-----END RSA PRIVATE KEY-----", "••••••[", "MIIEow");
untouched("sha256 checksum", "sha256: 9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08  file.tgz");
untouched("git sha", "commit 3142986a1b2c3d4e5f60718293a4b5c6d7e8f901");
untouched("path assignment", "TOKEN_FILE=/Users/x/.mesh/token");
untouched("short known", "tiny value stays");
untouched("prose", "--flag=value ordinary prose with a token word and a password mention");
untouched("empty", "");

// The whole redacted output must never contain any fixture secret.
const everything = redact("ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghij123456 " + meshToken + " AKIAIOSFODNN7EXAMPLE").text;
expect("no secret survives", !/ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghij123456|AKIAIOSFODNN7EXAMPLE/.test(everything) && !everything.includes(meshToken), everything);

// env secrets: only secret-shaped names, non-empty values
const env = envSecrets({ HF_TOKEN: "x", ANTHROPIC_API_KEY: "y", PATH: "/bin", EMPTY_TOKEN: "" } as any);
expect("envSecrets picks names", env.length === 2 && env.every(([n]) => n === "HF_TOKEN" || n === "ANTHROPIC_API_KEY"), JSON.stringify(env));

// multi-line PEM through the line redactor
const lr = createLineRedactor();
const pem = ["-----BEGIN OPENSSH PRIVATE KEY-----", "b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQ", "-----END OPENSSH PRIVATE KEY-----", "echo after"].map(lr);
expect("pem begin masked", pem[0].text.includes("PRIVATE KEY ••••••[") && pem[0].findings.length === 1, JSON.stringify(pem[0]));
expect("pem body hidden", pem[1].text === "" && pem[2].text === "", JSON.stringify([pem[1], pem[2]]));
expect("after pem passes", pem[3].text === "echo after", pem[3].text);
const wrapped = redact("echo TOKEN_IS ghp_ABCDEFGHIJKLMNOPQRST \rUVWXYZabcdefghij123456 done");
expect("wrapped echo redacted (plain redact)", wrapped.findings.length === 1 && !wrapped.text.includes("UVWXYZabcdefghij123456") && wrapped.text.includes("ghp_••••••["), JSON.stringify(wrapped));
expect("plain line keeps its CR", redact("plain \rline").text === "plain \rline");

// Re-redacting redacted text must change nothing: stored events are cleaned again on every
// read, and a fingerprint that drifts no longer matches its ledger row.
for (const line of [
  "postgres://user:s3cretPassw0rd@db.example.com:5432/app",
  "Authorization: Bearer abcdefghijklmnopqrstuvwxyz012345",
  "api_key = abcdefghijklmnop1234",
  "token ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghij123456 pushed",
  "curl -H 'Authorization: Bearer " + meshToken + "'",
  "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dozjgNryP4J3jVmNHl0w5N_XgL0n3I9PlFUP0THsR8U",
]) {
  const once = redact(line).text;
  const twice = redact(once);
  expect("idempotent: " + line.slice(0, 24), twice.text === once && twice.findings.length === 0, once + " -> " + twice.text);
}

// ledger: distinct fingerprints, dedupe window on polled channels, status changes
const f1 = redact("ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghij123456").findings;
await record(f1, "event");
await record(f1, "event");
await record(f1, "output", 60_000);
await record(f1, "output", 60_000); // inside the window: not counted
const l1 = await listExposures();
expect("one row", l1.count === 1 && l1.open === 1, JSON.stringify(l1));
expect("count is 3 (2 events + 1 output)", l1.items[0]?.count === 3, JSON.stringify(l1.items[0]));
expect("channels", JSON.stringify(l1.items[0]?.channels) === JSON.stringify(["event", "output"]), JSON.stringify(l1.items[0]?.channels));
const rotated = await setExposureStatus(f1[0].fp, "rotated");
expect("rotated", rotated?.status === "rotated" && (await listExposures()).open === 0);
expect("bad status rejected", (await setExposureStatus(f1[0].fp, "nope" as any)) === null);
// HTTP surface
const list = await handleExposures(new Request("http://x/exposures"), new URL("http://x/exposures"));
expect("GET /exposures", list?.status === 200 && (await list!.json()).count === 1);
const rec = await handleExposures(new Request("http://x/exposures/record", { method: "POST", body: JSON.stringify({ channel: "bridge", findings: [{ kind: "jwt", hint: "eyJ", fp: "abcdef" }, { kind: "x", hint: "y", fp: "not-hex" }] }) }), new URL("http://x/exposures/record"));
expect("POST /exposures/record filters bad fps", rec?.status === 200 && (await rec!.json()).recorded === 1);
expect("bridge channel recorded", (await listExposures()).items.some((i) => i.fp === "abcdef" && i.channels[0] === "bridge"));
const miss = await handleExposures(new Request("http://x/exposures/abc123", { method: "POST", body: "{\"status\":\"rotated\"}" }), new URL("http://x/exposures/abc123"));
expect("unknown fp 404", miss?.status === 404);
expect("ledger file is private", ((await import("node:fs")).statSync(process.env.MESHD_EXPOSURES_PATH!).mode & 0o777) === 0o600);

if (failed) { console.log("check-redact: " + failed + " failure(s)"); process.exit(1); }
console.log("check-redact: OK (17 rules, ledger, HTTP surface)");
EOF
MESH_ROOT="$ROOT" MESHD_EXPOSURES_PATH="$TMP/exposures.json" bun "$TMP/check.ts"

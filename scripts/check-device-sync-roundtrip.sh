#!/bin/sh
# Two devices register and seal a mailbox through a loopback stub.
# Each key file lives in its own temp state directory. The recipient
# reloads that file and opens the ciphertext. A home directory and a
# mesh directory are refused. This check does not call Supabase, require
# swiftc, or dial anything except the stub.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ROUND="$ROOT/experiments/device-sync/round-trip.ts"
KEY="$ROOT/experiments/device-sync/key-file.ts"
SEND="$ROOT/experiments/device-sync/send.ts"
SEAL="$ROOT/experiments/sealed-mailbox/seal.ts"
OPEN="$ROOT/experiments/sealed-mailbox/open.ts"
TMP="$(mktemp -d)"
HOME_DIR="$TMP/home"
STATE_A="$TMP/device-a"
STATE_B="$TMP/device-b"
STUB_DIR="$TMP/stub"
cleanup() {
  rm -rf "$TMP"
}
trap cleanup EXIT

command -v node >/dev/null 2>&1 || {
  echo "FAIL: check-device-sync-roundtrip: node is not installed"
  exit 1
}

for f in "$ROUND" "$KEY" "$SEND" "$SEAL" "$OPEN"; do
  [ -f "$f" ] || { echo "FAIL: check-device-sync-roundtrip: missing $f"; exit 1; }
done

if grep -E -n 'supabase|createClient|@supabase|ai-gateway|gateway\.ai|8899|hosts\.json|homedir|\.mesh|child_process|node:http|node:net|node:https|fetch\(|process\.env|swiftc|os\.hostname|networkInterfaces' "$ROUND"; then
  echo "FAIL: check-device-sync-roundtrip: round trip reaches the network, a mesh path, or the environment"
  exit 1
fi

if grep -F -n -e 'fixture-token-not-a-secret' -e '203.0.113.10' -e 'fixture-mac' -e '/Users/' "$ROUND"; then
  echo "FAIL: check-device-sync-roundtrip: round trip hardcodes a fixture secret or a Users path"
  exit 1
fi

if grep -n -E 'experiments/device-sync/round-trip|postDeviceSync|openMailbox' \
  "$ROOT/project.yml" \
  "$ROOT"/MeshDesktop/*.swift \
  "$ROOT"/Shared/*.swift \
  "$ROOT"/install/payload/meshd/server.ts \
  "$ROOT"/install/payload/meshd/pair.ts \
  "$ROOT"/install/payload/meshd/telemetry.ts >/dev/null 2>&1; then
  echo "FAIL: check-device-sync-roundtrip: the shipping menu bar calls the round trip"
  exit 1
fi

mkdir -p "$HOME_DIR"
chmod 700 "$HOME_DIR"

env -u MESHD_STATE -u USERPROFILE \
  HOME="$HOME_DIR" \
  STATE_A="$STATE_A" \
  STATE_B="$STATE_B" \
  STUB_DIR="$STUB_DIR" \
  TMP="$TMP" \
  ROOT="$ROOT" \
  NODE_NO_WARNINGS=1 \
  node --experimental-strip-types <<'END_CHECK'
const http = require("node:http");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { postDeviceSync, openMailbox } = require(process.env.ROOT + "/experiments/device-sync/round-trip.ts");
const { loadDeviceKey } = require(process.env.ROOT + "/experiments/device-sync/key-file.ts");

const TOKEN = "fixture-token-not-a-secret";
const ADDRESS = "203.0.113.10";
const HOST = "fixture-mac";
const stateA = process.env.STATE_A;
const stateB = process.env.STATE_B;
const homeDir = process.env.HOME;
const stubDir = process.env.STUB_DIR;
const tmp = process.env.TMP;

function fail(message) {
  console.error(`FAIL: check-device-sync-roundtrip: ${message}`);
  process.exit(1);
}

function scalarEncodings(privateKey) {
  const jwk = privateKey.export({ format: "jwk" });
  if (typeof jwk.d !== "string") fail("device private key has no scalar");
  const raw = Buffer.from(jwk.d, "base64url");
  if (raw.length !== 32) fail("device private key is not 32 bytes");
  const pem = String(privateKey.export({ format: "pem", type: "pkcs8" }));
  const pemBody = pem.replace(/-----[A-Z ]+-----/g, "").replace(/\s+/g, "");
  return { raw, texts: [jwk.d, raw.toString("base64"), raw.toString("hex"), pemBody] };
}

function modeBits(target) {
  const st = fs.lstatSync(target);
  if (st.isSymbolicLink()) fail("a state path is a symlink");
  return st.mode & 0o777;
}

function inside(parent, child) {
  const rel = path.relative(parent, path.resolve(child));
  return rel !== "" && !rel.startsWith("..") && !path.isAbsolute(rel);
}

function expectClosed(run, message) {
  try {
    run();
  } catch (error) {
    if (!(error instanceof Error) || error.message !== message) {
      throw new Error(`expected ${message}`);
    }
    return;
  }
  throw new Error(`${message} did not fail`);
}

(async () => {
  if ([stateA, stateB, homeDir, stubDir, tmp].some((value) => typeof value !== "string" || value.length === 0)) {
    fail("temp directories were not set");
  }
  if (fs.existsSync(stateA) || fs.existsSync(stateB)) fail("state directory existed before the key file module created it");
  if (!inside(tmp, stateA) || !inside(tmp, stateB) || !inside(tmp, homeDir)) {
    fail("a working directory is outside the temp directory");
  }
  if (inside(homeDir, stateA) || inside(homeDir, stateB)) fail("a state directory is under home");
  for (const dir of [stateA, stateB, homeDir, tmp]) {
    if (dir.split(path.sep).includes(".mesh")) fail("a working directory is a mesh directory");
  }

  const plaintext = {
    token: TOKEN,
    fleet: [{ host: HOST, ip: ADDRESS, port: 8898, token: TOKEN }],
  };

  const stored = [];
  const server = http.createServer((req, res) => {
    const chunks = [];
    req.on("data", (chunk) => chunks.push(chunk));
    req.on("end", () => {
      const body = Buffer.concat(chunks);
      stored.push({
        method: req.method,
        url: req.url,
        host: req.headers.host,
        headers: req.headers,
        body,
      });
      if (req.method === "POST" && (req.url === "/devices" || req.url === "/mailbox")) {
        res.writeHead(204);
        res.end();
        return;
      }
      res.writeHead(404);
      res.end();
    });
  });

  await new Promise((resolve, reject) => {
    server.once("error", reject);
    server.listen(0, "127.0.0.1", resolve);
  });
  const bound = server.address();
  if (bound === null || typeof bound === "string") fail("stub did not bind a tcp port");
  if (bound.address !== "127.0.0.1") fail("stub did not bind loopback");
  if (bound.port === 8899) fail("stub bound port 8899");

  const base = `http://127.0.0.1:${bound.port}`;
  const originalFetch = globalThis.fetch;
  globalThis.fetch = async (url, init) => {
    let target;
    try {
      target = new URL(String(url));
    } catch {
      fail("sender dialed a URL outside the stub");
    }
    if (target.protocol !== "http:" || target.hostname !== "127.0.0.1" || target.port !== String(bound.port)) {
      fail("sender dialed a URL outside the stub");
    }
    return originalFetch(url, init);
  };

  async function expectRefused(label, dir) {
    const before = stored.length;
    let caught = 0;
    try {
      await postDeviceSync({
        base,
        senderStateDir: dir,
        recipientStateDir: stateB,
        label: "Kitchen Mac",
        platform: "macos",
        plaintext,
      });
    } catch (error) {
      caught += 1;
      if (!(error instanceof Error) || error.message !== "device key state directory is not allowed") {
        fail(`${label} raised a different error`);
      }
    }
    if (caught !== 1) fail(`${label} was accepted`);
    if (stored.length !== before) fail(`${label} reached the stub`);
  }

  await expectRefused("home directory", homeDir);
  await expectRefused("mesh directory", path.join(homeDir, ".mesh"));
  if (fs.existsSync(path.join(homeDir, "device.key"))) fail("a key file was written under home");
  if (fs.existsSync(path.join(homeDir, ".mesh"))) fail("a mesh directory was created");

  const first = await postDeviceSync({
    base,
    senderStateDir: stateA,
    recipientStateDir: stateB,
    label: "Kitchen Mac",
    platform: "macos",
    plaintext,
  });
  const reverse = await postDeviceSync({
    base,
    senderStateDir: stateB,
    recipientStateDir: stateA,
    label: "Wrist",
    platform: "watchos",
    plaintext,
  });

  if (first.senderPublicKey === reverse.senderPublicKey) fail("the two devices share a public key");
  if (reverse.senderPublicKey !== first.recipientPublicKey) {
    fail("device B did not register the key the mailbox was sealed to");
  }
  if (reverse.recipientPublicKey !== first.senderPublicKey) {
    fail("device A was not the recipient of device B's mailbox");
  }

  const keyA = path.join(stateA, "device.key");
  const keyB = path.join(stateB, "device.key");
  for (const key of [keyA, keyB]) {
    if (!fs.lstatSync(key).isFile()) fail("device.key is not a regular file");
  }
  if (modeBits(stateA) !== 0o700 || modeBits(stateB) !== 0o700) fail("state directory is not mode 700");
  if (modeBits(keyA) !== 0o600 || modeBits(keyB) !== 0o600) fail("device.key is not mode 600");
  if (fs.readFileSync(keyA).length !== 64 || fs.readFileSync(keyB).length !== 64) {
    fail("device.key is not 64 bytes");
  }

  const loadedA = loadDeviceKey({ stateDir: stateA });
  const loadedB = loadDeviceKey({ stateDir: stateB });
  if (loadedA.export({ format: "jwk" }).x !== first.senderPublicKey) {
    fail("reloaded sender public key does not match the registration");
  }
  if (loadedB.export({ format: "jwk" }).x !== first.recipientPublicKey) {
    fail("reloaded recipient public key does not match the seal target");
  }

  const encodings = [scalarEncodings(loadedA), scalarEncodings(loadedB)];
  const machine = os.hostname();

  function assertClean(label, text, raw) {
    if (text.includes(TOKEN)) fail(`${label} contains the mesh token`);
    if (text.includes(ADDRESS)) fail(`${label} contains the IP`);
    if (text.includes(HOST)) fail(`${label} contains the hostname`);
    for (const encoding of encodings) {
      for (const secret of encoding.texts) {
        if (secret.length > 0 && text.includes(secret)) fail(`${label} contains the private key`);
      }
    }
    if (raw) {
      if (machine.length >= 4 && text.includes(machine)) fail(`${label} contains the machine hostname`);
      for (const encoding of encodings) {
        if (raw.includes(encoding.raw)) fail(`${label} contains the raw private key`);
      }
    }
  }

  if (stored.length !== 4) fail(`expected 4 requests, saw ${stored.length}`);
  const posts = [
    ["POST", "/devices", first.registration],
    ["POST", "/mailbox", first.mailbox],
    ["POST", "/devices", reverse.registration],
    ["POST", "/mailbox", reverse.mailbox],
  ];
  for (let i = 0; i < posts.length; i += 1) {
    const hit = stored[i];
    const [method, url, body] = posts[i];
    if (hit.method !== method || hit.url !== url) fail(`request ${i} was not ${method} ${url}`);
    if (hit.body.toString("utf8") !== body) fail(`stub did not store request ${i}`);
    if (hit.host !== `127.0.0.1:${bound.port}`) fail("request host is not the stub");
    if (hit.headers.authorization !== undefined) fail("stub saw an Authorization header");
    if (hit.headers["content-type"] !== "application/json") fail("body was not stored as JSON");
    assertClean("stub body", hit.body.toString("utf8"), hit.body);
    assertClean("stub url", `http://${hit.host}${hit.url}`, null);
    const headerText = Object.entries(hit.headers)
      .filter(([name]) => name.toLowerCase() !== "host")
      .map(([name, value]) => `${name}:${Array.isArray(value) ? value.join(",") : value}`)
      .join("\n");
    assertClean("stub header", headerText, null);
  }

  for (const body of [first.registration, reverse.registration]) {
    const registration = JSON.parse(body);
    if (Object.keys(registration).join(",") !== "label,platform,public_key") {
      fail("registration keys are not label, platform, and public_key");
    }
  }
  if (JSON.parse(first.registration).label !== "Kitchen Mac" || JSON.parse(first.registration).platform !== "macos") {
    fail("device A registration did not keep the label and platform");
  }
  if (JSON.parse(reverse.registration).label !== "Wrist" || JSON.parse(reverse.registration).platform !== "watchos") {
    fail("device B registration did not keep the label and platform");
  }
  if (JSON.parse(first.registration).public_key !== first.senderPublicKey) {
    fail("device A registration public key is not the on-disk public key");
  }
  for (const body of [first.mailbox, reverse.mailbox]) {
    const mailbox = JSON.parse(body);
    if (Object.keys(mailbox).join(",") !== "ciphertext") fail("mailbox key is not ciphertext");
    if (typeof mailbox.ciphertext !== "string" || mailbox.ciphertext.length < 1) fail("ciphertext is empty");
  }

  const sealedToB = JSON.parse(first.mailbox).ciphertext;
  const opened = openMailbox({ stateDir: stateB, ciphertext: sealedToB });
  if (JSON.stringify(opened) !== JSON.stringify(plaintext)) {
    fail("device B did not open the mailbox from the on-disk key");
  }
  const openedByA = openMailbox({
    stateDir: stateA,
    ciphertext: JSON.parse(reverse.mailbox).ciphertext,
  });
  if (JSON.stringify(openedByA) !== JSON.stringify(plaintext)) {
    fail("device A did not open the mailbox sealed to its on-disk key");
  }
  expectClosed(
    () => openMailbox({ stateDir: stateA, ciphertext: sealedToB }),
    "sealed mailbox could not be opened",
  );

  const bytesA = fs.readFileSync(keyA);
  const bytesB = fs.readFileSync(keyB);
  const second = await postDeviceSync({
    base,
    senderStateDir: stateA,
    recipientStateDir: stateB,
    label: "Kitchen Mac",
    platform: "macos",
    plaintext,
  });
  if (second.senderPublicKey !== first.senderPublicKey) fail("a second run minted a new public key");
  if (second.recipientPublicKey !== first.recipientPublicKey) fail("a second run minted a new recipient key");
  if (!fs.readFileSync(keyA).equals(bytesA) || !fs.readFileSync(keyB).equals(bytesB)) {
    fail("a second run replaced a key file");
  }
  if (second.registration !== first.registration) fail("a second run changed the registration");
  if (second.mailbox === first.mailbox) fail("a second run reused the ciphertext");
  if (JSON.parse(second.registration).public_key !== first.senderPublicKey) {
    fail("the stored second registration is a different public key");
  }
  const openedSecond = openMailbox({
    stateDir: stateB,
    ciphertext: JSON.parse(second.mailbox).ciphertext,
  });
  if (JSON.stringify(openedSecond) !== JSON.stringify(plaintext)) {
    fail("device B did not open the second mailbox from the same key file");
  }
  if (stored.length !== 6) fail(`expected 6 requests, saw ${stored.length}`);
  assertClean("second registration", stored[4].body.toString("utf8"), stored[4].body);
  assertClean("second mailbox", stored[5].body.toString("utf8"), stored[5].body);

  const packed = Buffer.from(sealedToB, "base64url");
  packed[packed.length - 1] ^= 0xff;
  const tampered = packed.toString("base64url");
  if (tampered === sealedToB) fail("flip did not change the ciphertext");
  expectClosed(
    () => openMailbox({ stateDir: stateB, ciphertext: tampered }),
    "sealed mailbox could not be opened",
  );

  const goodB = fs.readFileSync(keyB);
  const flippedKey = Buffer.from(goodB);
  flippedKey[0] ^= 0xff;
  if (flippedKey[0] === goodB[0]) fail("flip did not change a key byte");
  fs.writeFileSync(keyB, flippedKey);
  try {
    expectClosed(
      () => openMailbox({ stateDir: stateB, ciphertext: sealedToB }),
      "device key file could not be opened",
    );
  } finally {
    fs.writeFileSync(keyB, goodB);
  }
  if (modeBits(keyB) !== 0o600 || modeBits(keyA) !== 0o600) fail("device.key mode changed");
  const restored = openMailbox({ stateDir: stateB, ciphertext: sealedToB });
  if (JSON.stringify(restored) !== JSON.stringify(plaintext)) {
    fail("the restored key file did not open the mailbox");
  }

  fs.mkdirSync(stubDir, { recursive: true, mode: 0o700 });
  for (let i = 0; i < stored.length; i += 1) {
    const name = `${String(i).padStart(2, "0")}${stored[i].url.replace(/\//g, "-")}.bin`;
    fs.writeFileSync(path.join(stubDir, name), stored[i].body, { mode: 0o600 });
  }

  await new Promise((resolve) => server.close(resolve));
  console.log(`stub: 127.0.0.1:${bound.port}`);
  console.log("devices: 2");
  console.log("registration_keys: label,platform,public_key");
  console.log("mailbox_keys: ciphertext");
  console.log("opened_from_disk: true");
  console.log("token_in_stub: false");
  console.log("ip_in_stub: false");
  console.log("hostname_in_stub: false");
  console.log("private_key_in_stub: false");
  console.log("flipped_byte: closed");
  console.log("second_run_public_key: reused");
  console.log("key_file_mode: 600");
  console.log("home_write: false");
  console.log("mesh_dir: false");
  console.log("check-device-sync-roundtrip: node OK");
})().catch((error) => {
  console.error(`FAIL: check-device-sync-roundtrip: ${error instanceof Error ? error.message : "round trip failed"}`);
  process.exit(1);
});
END_CHECK

mode_of() {
  python3 -c 'import os, sys; print(format(os.stat(sys.argv[1]).st_mode & 0o777, "o"))' "$1"
}
bytes_of() {
  wc -c < "$1" | tr -d ' '
}

for state in "$STATE_A" "$STATE_B"; do
  key_mode="$(mode_of "$state/device.key")"
  dir_mode="$(mode_of "$state")"
  key_bytes="$(bytes_of "$state/device.key")"
  [ "$key_mode" = "600" ] || { echo "FAIL: check-device-sync-roundtrip: stat mode is $key_mode"; exit 1; }
  [ "$dir_mode" = "700" ] || { echo "FAIL: check-device-sync-roundtrip: directory mode is $dir_mode"; exit 1; }
  [ "$key_bytes" = "64" ] || { echo "FAIL: check-device-sync-roundtrip: file is $key_bytes bytes"; exit 1; }
  if [ -L "$state/device.key" ]; then
    echo "FAIL: check-device-sync-roundtrip: device.key is a symlink"
    exit 1
  fi
done

if [ ! -d "$STUB_DIR" ] || [ -z "$(find "$STUB_DIR" -type f -print -quit)" ]; then
  echo "FAIL: check-device-sync-roundtrip: stub stored nothing"
  exit 1
fi

if grep -a -F -q -e 'fixture-token-not-a-secret' -e '203.0.113.10' -e 'fixture-mac' "$STUB_DIR"/*; then
  echo "FAIL: check-device-sync-roundtrip: stub file contains a token, IP, or hostname"
  exit 1
fi

if [ -e "$HOME_DIR/device.key" ] || [ -e "$HOME_DIR/.mesh" ]; then
  echo "FAIL: check-device-sync-roundtrip: round trip wrote under the home directory"
  exit 1
fi
if find "$HOME_DIR" \( -name 'device.key' -o -name '.mesh' \) | grep -q .; then
  echo "FAIL: check-device-sync-roundtrip: home directory contains a key file"
  exit 1
fi

echo "check-device-sync-roundtrip: OK"

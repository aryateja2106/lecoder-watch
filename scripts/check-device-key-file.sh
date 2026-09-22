#!/bin/sh
# Write the device X25519 private key under a temp state directory and prove
# it stays off the wire. The file is mode 600, the directory is mode 700, and
# a flipped or truncated file fails closed. The stub is loopback and is not
# port 8899. This check does not call Supabase, an AI gateway, or a daemon.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KEY="$ROOT/experiments/device-sync/key-file.ts"
CLIENT="$ROOT/experiments/device-sync/client.ts"
SEND="$ROOT/experiments/device-sync/send.ts"
SEAL="$ROOT/experiments/sealed-mailbox/seal.ts"
OPEN="$ROOT/experiments/sealed-mailbox/open.ts"
TMP="$(mktemp -d)"
HOME_DIR="$TMP/home"
STATE_DIR="$TMP/state"
cleanup() {
  rm -rf "$TMP"
  if [ -d /Users/example/MeshKeyProbe ]; then
    rm -rf /Users/example/MeshKeyProbe
  fi
}
trap cleanup EXIT

command -v node >/dev/null 2>&1 || {
  echo "FAIL: check-device-key-file: node is not installed"
  exit 1
}

for f in "$KEY" "$CLIENT" "$SEND" "$SEAL" "$OPEN"; do
  [ -f "$f" ] || { echo "FAIL: check-device-key-file: missing $f"; exit 1; }
done

if grep -E -n 'supabase|createClient|@supabase|ai-gateway|gateway\.ai|8899|hosts\.json|fetch\(|child_process|node:http|node:net|node:https' "$KEY"; then
  echo "FAIL: check-device-key-file: key file reaches the network or a live daemon"
  exit 1
fi

if grep -F -n -e 'fixture-token-not-a-secret' -e '203.0.113.10' -e 'fixture-access' -e 'fixture-mac' -e '/Users/' "$KEY"; then
  echo "FAIL: check-device-key-file: key file hardcodes a fixture secret or a Users path"
  exit 1
fi

mkdir -p "$HOME_DIR"
chmod 700 "$HOME_DIR"

env -u MESHD_STATE \
  HOME="$HOME_DIR" \
  STATE_DIR="$STATE_DIR" \
  TMP="$TMP" \
  ROOT="$ROOT" \
  NODE_NO_WARNINGS=1 \
  node --experimental-strip-types <<'END_CHECK'
const http = require("node:http");
const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");
const { generateDeviceKeyPair, seal } = require(process.env.ROOT + "/experiments/sealed-mailbox/seal.ts");
const { open } = require(process.env.ROOT + "/experiments/sealed-mailbox/open.ts");
const { buildDeviceSyncBodies } = require(process.env.ROOT + "/experiments/device-sync/client.ts");
const { sendDeviceSyncBodies } = require(process.env.ROOT + "/experiments/device-sync/send.ts");
const { saveDeviceKey, loadDeviceKey } = require(process.env.ROOT + "/experiments/device-sync/key-file.ts");

const TOKEN = "fixture-token-not-a-secret";
const ADDRESS = "203.0.113.10";
const HOST = "fixture-mac";
const ACCESS = "fixture-access";
const stateDir = process.env.STATE_DIR;
const homeDir = process.env.HOME;
const tmp = process.env.TMP;

function fail(message) {
  console.error(`FAIL: check-device-key-file: ${message}`);
  process.exit(1);
}

function scalarEncodings(privateKey) {
  const jwk = privateKey.export({ format: "jwk" });
  if (typeof jwk.d !== "string") fail("fixture private key has no scalar");
  const raw = Buffer.from(jwk.d, "base64url");
  if (raw.length !== 32) fail("fixture private key is not 32 bytes");
  const pem = String(privateKey.export({ format: "pem", type: "pkcs8" }));
  const pemBody = pem.replace(/-----[A-Z ]+-----/g, "").replace(/\s+/g, "");
  return [jwk.d, raw.toString("base64"), raw.toString("hex"), pemBody];
}

function assertClean(label, text, encodings) {
  if (text.includes(TOKEN)) fail(`${label} contains the fixture token`);
  if (text.includes(ADDRESS)) fail(`${label} contains the fixture address`);
  if (text.includes(HOST)) fail(`${label} contains the fixture host`);
  for (const encoding of encodings) {
    if (encoding.length > 0 && text.includes(encoding)) fail(`${label} contains the private key`);
  }
}

function modeOf(file) {
  return fs.statSync(file).mode & 0o777;
}

function expectClosed(label) {
  let caught = 0;
  try {
    loadDeviceKey({ stateDir });
  } catch (error) {
    caught += 1;
    if (!(error instanceof Error) || error.message !== "device key file could not be opened") {
      fail(`${label} raised a different error`);
    }
  }
  if (caught !== 1) fail(`${label} did not fail closed`);
}

function expectRefused(label, dir, privateKey) {
  let caught = 0;
  try {
    saveDeviceKey({ privateKey, stateDir: dir });
  } catch (error) {
    caught += 1;
    if (!(error instanceof Error) || error.message !== "device key state directory is not allowed") {
      fail(`${label} raised a different error`);
    }
  }
  if (caught !== 1) fail(`${label} was accepted`);
}

(async () => {
  if (typeof stateDir !== "string" || typeof homeDir !== "string" || typeof tmp !== "string") {
    fail("temp directories were not set");
  }
  if (fs.existsSync(stateDir)) fail("state directory existed before the key file module created it");

  const plaintext = {
    token: TOKEN,
    fleet: [{ host: HOST, ip: ADDRESS, port: 8898, token: TOKEN }],
  };
  const recipient = generateDeviceKeyPair();
  const built = buildDeviceSyncBodies({
    label: "Kitchen Mac",
    platform: "macos",
    recipientPublicKey: recipient.publicKey,
    plaintext,
  });

  const other = path.join(tmp, "env-state");
  process.env.MESHD_STATE = other;
  saveDeviceKey({ privateKey: built.privateKey, stateDir });
  if (fs.existsSync(path.join(other, "device.key"))) {
    fail("MESHD_STATE overrode the state directory argument");
  }

  const keyFile = path.join(stateDir, "device.key");
  if (!fs.existsSync(keyFile)) fail("device.key was not written");
  if (modeOf(stateDir) !== 0o700) fail("state directory is not mode 700");
  if (modeOf(keyFile) !== 0o600) fail("device.key is not mode 600");
  const stored = fs.readFileSync(keyFile);
  if (stored.length !== 64) fail("device.key is not the scalar and public key");
  const scalar = Buffer.from(built.privateKey.export({ format: "jwk" }).d, "base64url");
  const pub = Buffer.from(built.privateKey.export({ format: "jwk" }).x, "base64url");
  if (!stored.subarray(0, 32).equals(scalar) || !stored.subarray(32).equals(pub)) {
    fail("device.key is not the key material");
  }
  const storedText = stored.toString("utf8");
  if (storedText.includes(TOKEN) || storedText.includes(ADDRESS) || storedText.includes(HOST) || storedText.includes(ACCESS)) {
    fail("device.key contains a fixture secret");
  }

  expectRefused("home directory", homeDir, built.privateKey);
  expectRefused("mesh directory", path.join(homeDir, ".mesh"), built.privateKey);
  expectRefused("home subdirectory", path.join(homeDir, "state"), built.privateKey);
  const usersProbe = "/Users/example/MeshKeyProbe";
  const usersExisted = fs.existsSync(usersProbe);
  expectRefused("Users path", usersProbe, built.privateKey);
  if (!usersExisted && fs.existsSync(usersProbe)) fail("a Users path was created");
  const homeLink = path.join(tmp, "home-link");
  fs.symlinkSync(homeDir, homeLink);
  expectRefused("symlink to home", homeLink, built.privateKey);
  if (fs.existsSync(path.join(homeDir, "device.key"))) fail("a key file was written under home");
  if (fs.existsSync(path.join(homeDir, ".mesh"))) fail("a mesh directory was created under home");

  const senderScalar = scalarEncodings(built.privateKey);
  const recipientScalar = scalarEncodings(recipient.privateKey);
  const encodings = senderScalar.concat(recipientScalar);

  const hits = [];
  const server = http.createServer((req, res) => {
    const chunks = [];
    req.on("data", (chunk) => chunks.push(chunk));
    req.on("end", () => {
      hits.push({
        method: req.method,
        url: req.url,
        host: req.headers.host,
        authorization: req.headers.authorization,
        headers: req.headers,
        body: Buffer.concat(chunks).toString("utf8"),
      });
      res.writeHead(204);
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
    const target = String(url);
    if (!target.startsWith(base)) fail("sender dialed a URL outside the stub");
    return originalFetch(url, init);
  };

  try {
    await sendDeviceSyncBodies({
      base,
      registration: built.registration,
      mailbox: built.mailbox,
      accessToken: ACCESS,
    });
  } catch (error) {
    fail(error instanceof Error ? error.message : "send failed");
  }

  if (hits.length !== 2) fail(`expected 2 requests, saw ${hits.length}`);
  for (const hit of hits) {
    const fullUrl = `http://${hit.host}${hit.url}`;
    assertClean("request body", hit.body, encodings);
    assertClean("request url", fullUrl, encodings);
    assertClean("authorization", String(hit.authorization ?? ""), encodings);
    assertClean("a request header", JSON.stringify(hit.headers), encodings);
    if (hit.body.includes(ACCESS) || fullUrl.includes(ACCESS)) {
      fail("access token left the Authorization header");
    }
  }

  const devices = hits[0];
  const mailbox = hits[1];
  if (devices.method !== "POST" || devices.url !== "/devices") fail("registration was not posted to /devices");
  if (mailbox.method !== "POST" || mailbox.url !== "/mailbox") fail("mailbox was not posted to /mailbox");
  if (devices.body !== built.registration) fail("devices body is not the registration string");
  if (mailbox.body !== built.mailbox) fail("mailbox body is not the mailbox string");
  if (devices.authorization !== `Bearer ${ACCESS}` || mailbox.authorization !== `Bearer ${ACCESS}`) {
    fail("access token was not the Authorization header");
  }

  const registration = JSON.parse(devices.body);
  const mailboxJson = JSON.parse(mailbox.body);
  if (Object.keys(registration).join(",") !== "label,platform,public_key") {
    fail("registration body is not label, platform, and public_key");
  }
  if (Object.keys(mailboxJson).join(",") !== "ciphertext") fail("mailbox body is not only ciphertext");
  if (registration.public_key !== built.privateKey.export({ format: "jwk" }).x) {
    fail("registration public key is not the device public key");
  }

  delete process.env.MESHD_STATE;
  process.env.MESHD_STATE = stateDir;
  const loaded = loadDeviceKey();
  const loadedJwk = loaded.export({ format: "jwk" });
  if (loadedJwk.x !== registration.public_key) fail("reloaded public key does not match registration");
  const devicePublic = crypto.createPublicKey({
    key: { kty: "OKP", crv: "X25519", x: registration.public_key },
    format: "jwk",
  });
  const sealed = seal(plaintext, devicePublic);
  const opened = open(sealed, loaded);
  if (JSON.stringify(opened) !== JSON.stringify(plaintext)) {
    fail("reloaded key did not open the sealed mailbox");
  }

  const good = fs.readFileSync(keyFile);
  let flipped = 0;
  for (let i = 0; i < good.length; i += 1) {
    const buf = Buffer.from(good);
    buf[i] ^= 0xff;
    if (buf[i] === good[i]) fail("flip did not change a byte");
    fs.writeFileSync(keyFile, buf);
    expectClosed("flipped byte");
    flipped += 1;
  }
  if (flipped !== 64) fail("did not flip every key byte");
  for (const [index, bit] of [[0, 0x01], [0, 0x02], [0, 0x04], [31, 0x80], [31, 0x40]]) {
    const buf = Buffer.from(good);
    buf[index] ^= bit;
    fs.writeFileSync(keyFile, buf);
    expectClosed("flipped clamp bit");
  }
  fs.writeFileSync(keyFile, good.subarray(0, good.length - 1));
  expectClosed("truncated file");
  fs.writeFileSync(keyFile, Buffer.alloc(0));
  expectClosed("empty file");
  fs.writeFileSync(keyFile, good);
  if (modeOf(keyFile) !== 0o600) fail("device.key mode changed");
  const reloaded = loadDeviceKey({ stateDir });
  if (JSON.stringify(open(sealed, reloaded)) !== JSON.stringify(plaintext)) {
    fail("restored key file did not open the sealed mailbox");
  }

  await new Promise((resolve) => server.close(resolve));
  console.log(`stub: 127.0.0.1:${bound.port}`);
  console.log("state_dir_mode: 700");
  console.log("key_file_mode: 600");
  console.log("key_file_bytes: 64");
  console.log("registration_keys: label,platform,public_key");
  console.log("mailbox_keys: ciphertext");
  console.log("private_key_in_bodies: false");
  console.log("token_in_bodies: false");
  console.log("address_in_bodies: false");
  console.log("private_key_in_urls: false");
  console.log("token_in_urls: false");
  console.log("address_in_urls: false");
  console.log("private_key_in_authorization: false");
  console.log("reload_opens_mailbox: true");
  console.log("flipped_byte: closed");
  console.log("truncated_file: closed");
  console.log("home_write: false");
  console.log("check-device-key-file: node OK");
})().catch((error) => {
  console.error(`FAIL: check-device-key-file: ${error instanceof Error ? error.message : "key file check failed"}`);
  process.exit(1);
});
END_CHECK

key_mode="$(stat -c '%a' "$STATE_DIR/device.key")"
dir_mode="$(stat -c '%a' "$STATE_DIR")"
key_bytes="$(wc -c < "$STATE_DIR/device.key" | tr -d ' ')"
[ "$key_mode" = "600" ] || { echo "FAIL: check-device-key-file: stat mode is $key_mode"; exit 1; }
[ "$dir_mode" = "700" ] || { echo "FAIL: check-device-key-file: directory mode is $dir_mode"; exit 1; }
[ "$key_bytes" = "64" ] || { echo "FAIL: check-device-key-file: file is $key_bytes bytes"; exit 1; }

if grep -a -F -q 'fixture-token-not-a-secret' "$STATE_DIR/device.key" \
  || grep -a -F -q '203.0.113.10' "$STATE_DIR/device.key" \
  || grep -a -F -q 'fixture-mac' "$STATE_DIR/device.key"; then
  echo "FAIL: check-device-key-file: key file contains a fixture secret"
  exit 1
fi

if [ -e "$HOME_DIR/device.key" ] || [ -e "$HOME_DIR/.mesh" ]; then
  echo "FAIL: check-device-key-file: key file wrote under the home directory"
  exit 1
fi
if find "$HOME_DIR" \( -name 'device.key' -o -name '.mesh' \) | grep -q .; then
  echo "FAIL: check-device-key-file: home directory contains a key file"
  exit 1
fi

echo "check-device-key-file: OK"

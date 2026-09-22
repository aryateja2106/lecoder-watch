#!/bin/sh
# POST the sealed device-sync bodies at a loopback stub and read the wire.
# A fixture token, a TEST-NET-3 address, and the device private key are sealed
# inside the ciphertext and must not appear in either body or in the URL.
# The access token is a header. This check does not call Supabase, read a
# mesh directory, or dial a daemon.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SEND="$ROOT/experiments/device-sync/send.ts"
CLIENT="$ROOT/experiments/device-sync/client.ts"
SEAL="$ROOT/experiments/sealed-mailbox/seal.ts"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

command -v node >/dev/null 2>&1 || {
  echo "FAIL: check-device-sync-send: node is not installed"
  exit 1
}

for f in "$SEND" "$CLIENT" "$SEAL"; do
  [ -f "$f" ] || { echo "FAIL: check-device-sync-send: missing $f"; exit 1; }
done

if grep -E -n 'supabase|createClient|@supabase|8899|hosts\.json|\.mesh|homedir|node:fs|readFile|writeFile|process\.env|child_process|node:http|node:net|node:https' "$SEND"; then
  echo "FAIL: check-device-sync-send: sender reaches supabase, a mesh file, or the live daemon"
  exit 1
fi

if grep -F -n -e 'fixture-token-not-a-secret' -e '203.0.113.10' -e 'fixture-access' -e 'fixture-mac' "$SEND"; then
  echo "FAIL: check-device-sync-send: sender hardcodes a fixture secret"
  exit 1
fi

ROOT="$ROOT" HOME="$TMP" NODE_NO_WARNINGS=1 node --experimental-strip-types <<'END_CHECK'
const http = require("node:http");
const { generateDeviceKeyPair } = require(process.env.ROOT + "/experiments/sealed-mailbox/seal.ts");
const { buildDeviceSyncBodies } = require(process.env.ROOT + "/experiments/device-sync/client.ts");
const { sendDeviceSyncBodies } = require(process.env.ROOT + "/experiments/device-sync/send.ts");

const TOKEN = "fixture-token-not-a-secret";
const ADDRESS = "203.0.113.10";
const HOST = "fixture-mac";
const ACCESS = "fixture-access";

function fail(message) {
  console.error(`FAIL: check-device-sync-send: ${message}`);
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
    if (encoding.length > 0 && text.includes(encoding)) {
      fail(`${label} contains the private key`);
    }
  }
}

(async () => {
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
      contentType: req.headers["content-type"],
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

const devices = hits[0];
const mailbox = hits[1];
if (devices.method !== "POST" || devices.url !== "/devices") {
  fail("registration was not posted to /devices");
}
if (mailbox.method !== "POST" || mailbox.url !== "/mailbox") {
  fail("mailbox was not posted to /mailbox");
}
if (devices.body !== built.registration) fail("devices body is not the registration string");
if (mailbox.body !== built.mailbox) fail("mailbox body is not the mailbox string");
if (devices.authorization !== `Bearer ${ACCESS}` || mailbox.authorization !== `Bearer ${ACCESS}`) {
  fail("access token was not the Authorization header");
}
if (devices.contentType !== "application/json" || mailbox.contentType !== "application/json") {
  fail("body was not posted as JSON");
}

const registration = JSON.parse(devices.body);
const mailboxJson = JSON.parse(mailbox.body);
if (Object.keys(registration).join(",") !== "label,platform,public_key") {
  fail("registration body is not label, platform, and public_key");
}
if (registration.label !== "Kitchen Mac" || registration.platform !== "macos") {
  fail("registration did not keep the label and platform");
}
const publicPoint = built.privateKey.export({ format: "jwk" }).x;
if (registration.public_key !== publicPoint) fail("registration public key is not the device public key");
if (Object.keys(mailboxJson).join(",") !== "ciphertext") {
  fail("mailbox body is not only ciphertext");
}
if (typeof mailboxJson.ciphertext !== "string" || mailboxJson.ciphertext.length < 1) {
  fail("mailbox ciphertext is empty");
}

for (const hit of hits) {
  const fullUrl = `http://${hit.host}${hit.url}`;
  assertClean(`${hit.url} body`, hit.body, encodings);
  assertClean(`${hit.url} url`, fullUrl, encodings);
  if (hit.body.includes(ACCESS)) fail(`${hit.url} body contains the access token`);
  if (fullUrl.includes(ACCESS)) fail(`${hit.url} url contains the access token`);
  const headerDump = JSON.stringify({
    host: hit.host,
    authorization: hit.authorization,
    contentType: hit.contentType,
  });
  assertClean(`${hit.url} headers`, headerDump, encodings);
}

const withToken = hits.length;
hits.length = 0;
try {
  await sendDeviceSyncBodies({
    base,
    registration: built.registration,
    mailbox: built.mailbox,
  });
} catch (error) {
  fail(error instanceof Error ? error.message : "send without a token failed");
}
if (hits.length !== 2) fail(`expected 2 requests without a token, saw ${hits.length}`);
for (const hit of hits) {
  if (hit.authorization !== undefined) fail("a missing access token still set Authorization");
  if (hit.body.includes(ACCESS)) fail("body contains the access token when no header was requested");
  assertClean(`${hit.url} body without token`, hit.body, encodings);
  assertClean(`${hit.url} url without token`, `http://${hit.host}${hit.url}`, encodings);
}

await new Promise((resolve) => server.close(resolve));
console.log(`stub: 127.0.0.1:${bound.port}`);
console.log(`requests_with_token: ${withToken}`);
console.log("devices_path: /devices");
console.log("mailbox_path: /mailbox");
console.log("registration_keys: label,platform,public_key");
console.log("mailbox_keys: ciphertext");
console.log("authorization: Bearer fixture-access");
console.log("access_token_in_bodies: false");
console.log("token_in_bodies: false");
console.log("address_in_bodies: false");
console.log("private_key_in_bodies: false");
console.log("token_in_urls: false");
console.log("address_in_urls: false");
console.log("private_key_in_urls: false");
console.log("check-device-sync-send: node OK");
})().catch((error) => {
  console.error(`FAIL: check-device-sync-send: ${error instanceof Error ? error.message : "send failed"}`);
  process.exit(1);
});
END_CHECK

if [ -e "$TMP/.mesh" ]; then
  echo "FAIL: check-device-sync-send: sender touched a mesh directory"
  exit 1
fi

echo "check-device-sync-send: OK"

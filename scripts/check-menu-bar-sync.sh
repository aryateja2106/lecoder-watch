#!/bin/sh
# Build the two menu-bar device-sync JSON bodies with CryptoKit and prove node
# can open the ciphertext. A fixture token and a TEST-NET-3 address are sealed
# inside the ciphertext and must not appear in either body. This check does
# not call Supabase, read a mesh directory, or dial a daemon. A missing
# swiftc is a failure. The compiler flag is -Onone.
set -eu

if ! command -v swiftc >/dev/null 2>&1; then
  echo "FAIL: check-menu-bar-sync: swiftc is missing"
  exit 1
fi

if ! command -v node >/dev/null 2>&1; then
  echo "FAIL: check-menu-bar-sync: node is not installed"
  exit 1
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/MeshDesktop/DeviceSyncBodies.swift"
OPEN="$ROOT/experiments/sealed-mailbox/open.ts"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

[ -f "$SRC" ] || { echo "FAIL: check-menu-bar-sync: missing $SRC"; exit 1; }
[ -f "$OPEN" ] || { echo "FAIL: check-menu-bar-sync: missing $OPEN"; exit 1; }

if grep -E -n 'supabase|8899|\.mesh|hosts\.json|URLSession|URLRequest|NWConnection|Process\(' "$SRC"; then
  echo "FAIL: check-menu-bar-sync: DeviceSyncBodies reaches the network, a file, or a live daemon"
  exit 1
fi

for platform in web ios watchos macos linux; do
  grep -q "\"$platform\"" "$SRC" || {
    echo "FAIL: check-menu-bar-sync: platform $platform is missing"
    exit 1
  }
done

SWIFTC="$(command -v swiftc)"

cat > "$TMP/main.swift" <<'SWIFT'
import CryptoKit
import Foundation

func fail(_ message: String) -> Never {
    fputs("FAIL: check-menu-bar-sync: \(message)\n", stderr)
    exit(1)
}

func base64urlDecode(_ text: String) -> Data? {
    guard !text.isEmpty else { return nil }
    let ok = text.unicodeScalars.allSatisfy { scalar in
        (scalar >= "A" && scalar <= "Z")
            || (scalar >= "a" && scalar <= "z")
            || (scalar >= "0" && scalar <= "9")
            || scalar == "-"
            || scalar == "_"
    }
    guard ok else { return nil }
    var padded = text.replacingOccurrences(of: "-", with: "+")
        .replacingOccurrences(of: "_", with: "/")
    let remainder = padded.count % 4
    if remainder > 0 {
        padded += String(repeating: "=", count: 4 - remainder)
    }
    guard let data = Data(base64Encoded: padded) else { return nil }
    return data
}

func base64urlEncode(_ data: Data) -> String {
    data.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}

func readText(_ path: String) -> String {
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
          let text = String(data: data, encoding: .utf8) else {
        fail("could not read input")
    }
    return text.trimmingCharacters(in: .whitespacesAndNewlines)
}

let token = "fixture-token-not-a-secret"
let address = "203.0.113.10"
let args = Array(CommandLine.arguments.dropFirst())
guard args.count == 3 else { fail("build needs a public key, plaintext, and output directory") }

guard let recipient = base64urlDecode(readText(args[0])), recipient.count == 32 else {
    fail("recipient public key was not 32 raw bytes")
}
guard let plaintext = try? Data(contentsOf: URL(fileURLWithPath: args[1])), !plaintext.isEmpty else {
    fail("could not read the fixture plaintext")
}
let outDir = args[2]

var rejected = false
do {
    _ = try DeviceSyncBodies.build(
        label: "Kitchen Mac",
        platform: "windows",
        recipientPublicKey: recipient,
        plaintext: plaintext
    )
} catch {
    rejected = true
}
if !rejected { fail("an unknown platform produced a registration body") }

let built: DeviceSyncBodies
do {
    built = try DeviceSyncBodies.build(
        label: "Kitchen Mac",
        platform: "macos",
        recipientPublicKey: recipient,
        plaintext: plaintext
    )
} catch {
    fail("DeviceSyncBodies.build failed")
}

let again: DeviceSyncBodies
do {
    again = try DeviceSyncBodies.build(
        label: "Kitchen Mac",
        platform: "macos",
        recipientPublicKey: recipient,
        plaintext: plaintext
    )
} catch {
    fail("a second DeviceSyncBodies.build failed")
}

let secret = built.privateKey.rawRepresentation
let secretURL = base64urlEncode(secret)
let secretB64 = secret.base64EncodedString()
guard secret.count == 32, !secretURL.isEmpty else { fail("in-memory private key is not an x25519 scalar") }
guard base64urlEncode(built.privateKey.publicKey.rawRepresentation) != secretURL else {
    fail("public key is the private scalar")
}

let encoded: Data
do {
    encoded = try JSONEncoder().encode(built)
} catch {
    fail("JSONEncoder could not encode the result")
}
guard let encodedText = String(data: encoded, encoding: .utf8) else {
    fail("JSONEncoder output was not text")
}
if encodedText.contains(secretURL) || encodedText.contains(secretB64) || encoded.range(of: secret) != nil {
    fail("JSONEncoder output contains the private key")
}
if encodedText.contains("privateKey") {
    fail("JSONEncoder output contains the private key")
}
if encodedText.contains(token) || encodedText.contains(address) {
    fail("JSONEncoder output contains the fixture")
}
if built.registration.contains(secretURL) || built.mailbox.contains(secretURL) {
    fail("private key is in a JSON body")
}
if again.registration == built.registration {
    fail("a second call reused the device key")
}

func write(_ name: String, _ text: String) {
    let url = URL(fileURLWithPath: outDir).appendingPathComponent(name)
    do {
        try text.write(to: url, atomically: true, encoding: .utf8)
    } catch {
        fail("could not write \(name)")
    }
}

write("registration.json", built.registration)
write("mailbox.json", built.mailbox)
do {
    try encoded.write(to: URL(fileURLWithPath: outDir).appendingPathComponent("encoded.json"))
} catch {
    fail("could not write encoded.json")
}
print("check-menu-bar-sync: JSONEncoder omits the private key")
SWIFT

if ! grep -q 'DeviceSyncBodies.build' "$TMP/main.swift"; then
  echo "FAIL: check-menu-bar-sync: driver does not call DeviceSyncBodies"
  exit 1
fi

"$SWIFTC" -Onone -o "$TMP/sync" "$SRC" "$TMP/main.swift" 2>"$TMP/swiftc.err" || {
  echo "FAIL: check-menu-bar-sync: does not compile"
  tail -20 "$TMP/swiftc.err"
  exit 1
}

cat > "$TMP/drive.ts" <<'NODE'
const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");

const mode = process.argv[2];
const openPath = process.argv[3];
const tmp = process.argv[4];
const { open } = require(openPath);

const TOKEN = "fixture-token-not-a-secret";
const ADDRESS = "203.0.113.10";
const HOST = "fixture-mac";
const FORBIDDEN = ["token", "ip", "host", "hostname"];

function fail(message) {
  console.error(`FAIL: check-menu-bar-sync: ${message}`);
  process.exit(1);
}

function writeSecret(name, text) {
  fs.writeFileSync(path.join(tmp, name), text, { mode: 0o600 });
}

function readTrim(name) {
  return fs.readFileSync(path.join(tmp, name), "utf8").trim();
}

function rawField(key, field) {
  const jwk = key.export({ format: "jwk" });
  const value = jwk[field];
  if (typeof value !== "string" || Buffer.from(value, "base64url").length !== 32) {
    fail("key export was not 32 raw bytes");
  }
  return value;
}

function privateKey(dName, xName) {
  return crypto.createPrivateKey({
    key: { kty: "OKP", crv: "X25519", d: readTrim(dName), x: readTrim(xName) },
    format: "jwk",
  });
}

function mustStayClosed(ciphertext, key, message) {
  try {
    open(ciphertext, key);
  } catch {
    return;
  }
  fail(message);
}

const plaintext = {
  token: TOKEN,
  fleet: [
    { host: HOST, ip: ADDRESS, port: 8898, token: TOKEN },
  ],
};
const json = JSON.stringify(plaintext);

if (mode === "prepare") {
  const recipient = crypto.generateKeyPairSync("x25519");
  const other = crypto.generateKeyPairSync("x25519");
  if (rawField(recipient.publicKey, "x") === rawField(other.publicKey, "x")) {
    fail("fixture keypairs collided");
  }
  writeSecret("expected.json", json);
  writeSecret("recipient.pub", rawField(recipient.publicKey, "x") + "\n");
  writeSecret("recipient.priv", rawField(recipient.privateKey, "d") + "\n");
  writeSecret("recipient.x", rawField(recipient.publicKey, "x") + "\n");
  writeSecret("other.priv", rawField(other.privateKey, "d") + "\n");
  writeSecret("other.x", rawField(other.publicKey, "x") + "\n");
  process.exit(0);
}

if (mode === "open") {
  const registrationText = fs.readFileSync(path.join(tmp, "registration.json"), "utf8");
  const mailboxText = fs.readFileSync(path.join(tmp, "mailbox.json"), "utf8");
  const encodedText = fs.readFileSync(path.join(tmp, "encoded.json"), "utf8");
  for (const [name, body] of [
    ["registration", registrationText],
    ["mailbox", mailboxText],
  ]) {
    if (body.includes(TOKEN)) fail(`${name} contains the fixture token`);
    if (body.includes(ADDRESS)) fail(`${name} contains the fixture address`);
  }
  if (encodedText.includes(TOKEN) || encodedText.includes(ADDRESS)) {
    fail("JSONEncoder output contains the fixture");
  }

  let registration;
  let mailbox;
  let encoded;
  try {
    registration = JSON.parse(registrationText);
    mailbox = JSON.parse(mailboxText);
    encoded = JSON.parse(encodedText);
  } catch {
    fail("a JSON body did not parse");
  }

  const regKeys = Object.keys(registration);
  if (regKeys.join(",") !== "label,platform,public_key") {
    fail(`registration keys are ${regKeys.join(",")}`);
  }
  for (const key of FORBIDDEN) {
    if (Object.prototype.hasOwnProperty.call(registration, key)) {
      fail(`registration has a ${key} field`);
    }
  }
  if (registration.label !== "Kitchen Mac" || registration.platform !== "macos") {
    fail("registration did not keep the label and platform");
  }
  if (Buffer.from(String(registration.public_key), "base64url").length !== 32) {
    fail("public key is not 32 bytes");
  }

  const mailKeys = Object.keys(mailbox);
  if (mailKeys.length !== 1 || mailKeys[0] !== "ciphertext") {
    fail("mailbox payload is not only ciphertext");
  }
  const encodedKeys = Object.keys(encoded).sort();
  if (encodedKeys.join(",") !== "mailbox,registration") {
    fail(`JSONEncoder keys are ${encodedKeys.join(",")}`);
  }
  if (Object.prototype.hasOwnProperty.call(encoded, "privateKey")) {
    fail("JSONEncoder output contains the private key");
  }

  const ciphertext = mailbox.ciphertext;
  if (typeof ciphertext !== "string" || ciphertext.length === 0 || ciphertext.length > 16384) {
    fail("ciphertext length is outside 1..16384");
  }
  if (ciphertext.includes(TOKEN) || ciphertext.includes(ADDRESS)) {
    fail("ciphertext contains the fixture");
  }

  const recipient = privateKey("recipient.priv", "recipient.x");
  const other = privateKey("other.priv", "other.x");
  let opened;
  try {
    opened = open(ciphertext, recipient);
  } catch {
    fail("node did not open the blob Swift sealed");
  }
  if (JSON.stringify(opened) !== json) fail("node did not return the handoff Swift sealed");
  mustStayClosed(ciphertext, other, "a second key opened the mailbox");
  process.exit(0);
}

fail("unknown driver mode");
NODE

NODE_NO_WARNINGS=1 node --experimental-strip-types "$TMP/drive.ts" prepare "$OPEN" "$TMP"
"$TMP/sync" "$TMP/recipient.pub" "$TMP/expected.json" "$TMP"
NODE_NO_WARNINGS=1 node --experimental-strip-types "$TMP/drive.ts" open "$OPEN" "$TMP"

echo "check-menu-bar-sync: OK"

#!/bin/sh
# The mailbox stores one ciphertext. Swift has to open a blob node sealed, and
# node has to open a blob Swift sealed, or the fleet handoff is readable on one
# device and stuck on the other. This check never reads a mesh token and never
# dials out. The fixture string is not a secret.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIR="$ROOT/experiments/sealed-mailbox"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

if ! command -v swiftc >/dev/null 2>&1; then
  echo "FAIL: check-sealed-mailbox-swift: swiftc is missing"
  exit 1
fi

if ! command -v node >/dev/null 2>&1; then
  echo "FAIL: check-sealed-mailbox-swift: node is not installed"
  exit 1
fi

for f in "$DIR/seal.ts" "$DIR/open.ts"; do
  [ -f "$f" ] || { echo "FAIL: check-sealed-mailbox-swift: missing $f"; exit 1; }
done

SWIFTC="$(command -v swiftc)"

cat > "$TMP/sealed.swift" <<'SWIFT'
import CryptoKit
import Foundation

// Wire layout, kept in lockstep with experiments/sealed-mailbox/seal.ts:
//   version(1) || ephemeral public(32) || nonce(12) || aes-256-gcm body || tag(16)
// HKDF-SHA256 salt is the ephemeral public key. Info is mesh-sealed-mailbox-v1.
// AAD is version || ephemeral public. The mailbox column is base64url of that.

enum SealedMailbox {
    static let version: UInt8 = 1
    static let pubLen = 32
    static let nonceLen = 12
    static let tagLen = 16
    static let info = Data("mesh-sealed-mailbox-v1".utf8)
    static let maxChars = 16384
    static let fixture = "fixture-token-not-a-secret"

    enum Closed: Error {
        case closed
    }

    static func base64urlEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func base64urlDecode(_ text: String) -> Data? {
        guard !text.isEmpty, text.count <= maxChars else { return nil }
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
        guard base64urlEncode(data) == text else { return nil }
        return data
    }

    static func deriveKey(shared: SharedSecret, salt: Data) -> SymmetricKey {
        shared.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: salt,
            sharedInfo: info,
            outputByteCount: 32
        )
    }

    static func seal(_ plaintext: Data, recipientPublic rawPublic: Data) throws -> String {
        guard rawPublic.count == pubLen else { throw Closed.closed }
        let recipient = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: rawPublic)
        let ephemeral = Curve25519.KeyAgreement.PrivateKey()
        let ephRaw = ephemeral.publicKey.rawRepresentation
        guard ephRaw.count == pubLen else { throw Closed.closed }
        let shared = try ephemeral.sharedSecretFromKeyAgreement(with: recipient)
        let key = deriveKey(shared: shared, salt: ephRaw)
        let nonce = AES.GCM.Nonce()
        var aad = Data([version])
        aad.append(ephRaw)
        let sealed = try AES.GCM.seal(plaintext, using: key, nonce: nonce, authenticating: aad)
        let nonceData = nonce.withUnsafeBytes { Data($0) }
        guard nonceData.count == nonceLen, sealed.tag.count == tagLen else { throw Closed.closed }
        var packed = Data([version])
        packed.append(ephRaw)
        packed.append(nonceData)
        packed.append(sealed.ciphertext)
        packed.append(sealed.tag)
        let ciphertext = base64urlEncode(packed)
        guard !ciphertext.isEmpty, ciphertext.count <= maxChars else { throw Closed.closed }
        return ciphertext
    }

    static func open(_ ciphertext: String, recipientPrivate rawPrivate: Data) throws -> Data {
        guard let packed = base64urlDecode(ciphertext) else { throw Closed.closed }
        let minPacked = 1 + pubLen + nonceLen + tagLen
        guard packed.count >= minPacked, packed.first == version else { throw Closed.closed }
        guard rawPrivate.count == pubLen else { throw Closed.closed }
        let ephRaw = packed.subdata(in: 1..<(1 + pubLen))
        let nonceData = packed.subdata(in: (1 + pubLen)..<(1 + pubLen + nonceLen))
        let bodyAndTag = packed.subdata(in: (1 + pubLen + nonceLen)..<packed.count)
        guard ephRaw.count == pubLen, nonceData.count == nonceLen, bodyAndTag.count >= tagLen else {
            throw Closed.closed
        }
        let body = Data(bodyAndTag.prefix(bodyAndTag.count - tagLen))
        let tag = Data(bodyAndTag.suffix(tagLen))
        do {
            let priv = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: rawPrivate)
            let ephPub = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: ephRaw)
            let shared = try priv.sharedSecretFromKeyAgreement(with: ephPub)
            let key = deriveKey(shared: shared, salt: ephRaw)
            let nonce = try AES.GCM.Nonce(data: nonceData)
            let box = try AES.GCM.SealedBox(nonce: nonce, ciphertext: body, tag: tag)
            var aad = Data([version])
            aad.append(ephRaw)
            return try AES.GCM.open(box, using: key, authenticating: aad)
        } catch {
            throw Closed.closed
        }
    }
}

func fail(_ message: String) -> Never {
    fputs("FAIL: check-sealed-mailbox-swift: \(message)\n", stderr)
    exit(1)
}

func readText(_ path: String) -> String {
    guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
        fail("could not read input")
    }
    return text.trimmingCharacters(in: .whitespacesAndNewlines)
}

func readKey(_ path: String) -> Data {
    guard let data = SealedMailbox.base64urlDecode(readText(path)), data.count == SealedMailbox.pubLen else {
        fail("key was not 32 raw bytes")
    }
    return data
}

func readPlaintext(_ path: String) -> Data {
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)), !data.isEmpty else {
        fail("could not read the fixture plaintext")
    }
    return data
}

let args = Array(CommandLine.arguments.dropFirst())
guard let command = args.first else { fail("missing command") }

switch command {
case "open":
    guard args.count == 4 else { fail("open needs ciphertext, private key, and plaintext") }
    let plaintext = readPlaintext(args[3])
    let opened: Data
    do {
        opened = try SealedMailbox.open(readText(args[1]), recipientPrivate: readKey(args[2]))
    } catch {
        fail("the recipient key did not return the handoff")
    }
    assert(opened == plaintext, "the recipient key did not return the handoff")
    if opened != plaintext { fail("the recipient key did not return the handoff") }
    let openedText = String(data: opened, encoding: .utf8) ?? ""
    assert(openedText.contains(SealedMailbox.fixture), "opened plaintext is not the fixture handoff")
    if !openedText.contains(SealedMailbox.fixture) { fail("opened plaintext is not the fixture handoff") }

case "open-fail":
    guard args.count == 3 else { fail("open-fail needs ciphertext and a private key") }
    var opened = false
    do {
        _ = try SealedMailbox.open(readText(args[1]), recipientPrivate: readKey(args[2]))
        opened = true
    } catch {
        opened = false
    }
    assert(!opened, "a second key opened the mailbox")
    if opened { fail("a second key opened the mailbox") }

case "seal":
    guard args.count == 4 else { fail("seal needs a public key, plaintext, and an output path") }
    let plaintext = readPlaintext(args[2])
    let plaintextText = String(data: plaintext, encoding: .utf8) ?? ""
    assert(plaintextText.contains(SealedMailbox.fixture), "fixture plaintext missing")
    if !plaintextText.contains(SealedMailbox.fixture) { fail("fixture plaintext missing") }
    let ciphertext: String
    do {
        ciphertext = try SealedMailbox.seal(plaintext, recipientPublic: readKey(args[1]))
    } catch {
        fail("seal failed")
    }
    assert(!ciphertext.contains(SealedMailbox.fixture), "ciphertext contains the fixture token")
    if ciphertext.contains(SealedMailbox.fixture) { fail("ciphertext contains the fixture token") }
    assert(!ciphertext.isEmpty && ciphertext.count <= SealedMailbox.maxChars, "ciphertext length is outside 1..16384")
    if ciphertext.isEmpty || ciphertext.count > SealedMailbox.maxChars {
        fail("ciphertext length is outside 1..16384")
    }
    do {
        try ciphertext.write(toFile: args[3], atomically: true, encoding: .utf8)
    } catch {
        fail("could not write the sealed blob")
    }

default:
    fail("unknown command")
}
SWIFT

"$SWIFTC" -Onone -o "$TMP/sealed" "$TMP/sealed.swift" 2>"$TMP/swiftc.err" || {
  echo "FAIL: check-sealed-mailbox-swift: does not compile"
  tail -20 "$TMP/swiftc.err"
  exit 1
}

cat > "$TMP/drive.ts" <<'NODE'
const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");

const mode = process.argv[2];
const helperDir = process.argv[3];
const tmp = process.argv[4];
const { generateDeviceKeyPair, seal } = require(path.join(helperDir, "seal.ts"));
const { open } = require(path.join(helperDir, "open.ts"));

const TOKEN = "fixture-token-not-a-secret";

function fail(message) {
  console.error(`FAIL: check-sealed-mailbox-swift: ${message}`);
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

const plaintext = {
  token: TOKEN,
  fleet: [
    { host: "fixture-mac", ip: "203.0.113.10", port: 8898, token: TOKEN },
  ],
};
const json = JSON.stringify(plaintext);

function mustStayClosed(ciphertext, privateKey, message) {
  try {
    open(ciphertext, privateKey);
  } catch {
    return;
  }
  fail(message);
}

if (mode === "prepare") {
  const recipient = generateDeviceKeyPair();
  const other = generateDeviceKeyPair();
  if (rawField(recipient.publicKey, "x") === rawField(other.publicKey, "x")) {
    fail("fixture keypairs collided");
  }
  const ciphertext = seal(plaintext, recipient.publicKey);
  const otherCiphertext = seal(plaintext, other.publicKey);
  if (typeof ciphertext !== "string" || typeof otherCiphertext !== "string") {
    fail("ciphertext is not a string");
  }
  if (ciphertext.includes(TOKEN) || otherCiphertext.includes(TOKEN)) {
    fail("ciphertext contains the fixture token");
  }
  if (JSON.stringify(open(ciphertext, recipient.privateKey)) !== json) {
    fail("node did not round-trip its own blob");
  }
  if (JSON.stringify(open(otherCiphertext, other.privateKey)) !== json) {
    fail("the second key could not open a blob sealed to itself");
  }
  mustStayClosed(ciphertext, other.privateKey, "a second key opened the mailbox");
  writeSecret("expected.json", json);
  writeSecret("recipient.pub", rawField(recipient.publicKey, "x") + "\n");
  writeSecret("recipient.priv", rawField(recipient.privateKey, "d") + "\n");
  writeSecret("other.pub", rawField(other.publicKey, "x") + "\n");
  writeSecret("other.priv", rawField(other.privateKey, "d") + "\n");
  writeSecret("node.ct", ciphertext + "\n");
  writeSecret("other.ct", otherCiphertext + "\n");
  process.exit(0);
}

if (mode === "open") {
  const ciphertext = readTrim("swift.ct");
  if (ciphertext.includes(TOKEN)) fail("ciphertext contains the fixture token");
  const recipient = privateKey("recipient.priv", "recipient.pub");
  const other = privateKey("other.priv", "other.pub");
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

NODE_NO_WARNINGS=1 node --experimental-strip-types "$TMP/drive.ts" prepare "$DIR" "$TMP"

# Swift opens the blob the existing helper just sealed, including one sealed to
# the second key so that key is known-good before it is required to fail closed.
"$TMP/sealed" open "$TMP/node.ct" "$TMP/recipient.priv" "$TMP/expected.json"
"$TMP/sealed" open "$TMP/other.ct" "$TMP/other.priv" "$TMP/expected.json"
"$TMP/sealed" open-fail "$TMP/node.ct" "$TMP/other.priv"
"$TMP/sealed" seal "$TMP/recipient.pub" "$TMP/expected.json" "$TMP/swift.ct"

NODE_NO_WARNINGS=1 node --experimental-strip-types "$TMP/drive.ts" open "$DIR" "$TMP"

for f in "$TMP/node.ct" "$TMP/other.ct" "$TMP/swift.ct"; do
  [ -s "$f" ] || { echo "FAIL: check-sealed-mailbox-swift: empty ciphertext"; exit 1; }
done
if grep -q -F 'fixture-token-not-a-secret' "$TMP/node.ct" "$TMP/other.ct" "$TMP/swift.ct"; then
  echo "FAIL: check-sealed-mailbox-swift: ciphertext contains the fixture token"
  exit 1
fi

echo "check-sealed-mailbox-swift: OK"

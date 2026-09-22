#!/bin/sh
# Swift and node share one device.key. The file is the clamped X25519 scalar
# and the matching public key, mode 600, under a caller-supplied state
# directory mode 700. Node seals a mailbox to that public key and Swift opens
# it with the loaded key. Swift also opens a file node wrote. Registration
# stays label, platform, public_key. The mailbox stays ciphertext. A flipped
# byte fails closed with one error. This check does not call Supabase or a
# daemon. A missing swiftc is a failure. The compiler flag is -Onone.
# File modes are read with Python, because BSD stat rejects GNU `stat -c`.
set -eu

if ! command -v swiftc >/dev/null 2>&1; then
  echo "FAIL: check-swift-device-key: swiftc is missing"
  exit 1
fi

if ! command -v node >/dev/null 2>&1; then
  echo "FAIL: check-swift-device-key: node is not installed"
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "FAIL: check-swift-device-key: python3 is not installed"
  exit 1
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/experiments/device-sync/DeviceKeyFile.swift"
KEY="$ROOT/experiments/device-sync/key-file.ts"
SEAL="$ROOT/experiments/sealed-mailbox/seal.ts"
OPEN="$ROOT/experiments/sealed-mailbox/open.ts"
BODIES="$ROOT/MeshDesktop/DeviceSyncBodies.swift"
TMP="$(mktemp -d /tmp/swift-device-key.XXXXXX)"
HOME_DIR="$TMP/home"
STATE_DIR="$TMP/state"
NODE_STATE="$TMP/node-state"
ENV_STATE="$TMP/env-state"
OUT="$TMP/out"
PROBE="/Users/example/MeshKeyProbe"
probe_existed=0
if [ -e "$PROBE" ]; then
  probe_existed=1
fi
cleanup() {
  rm -rf "$TMP"
  if [ "$probe_existed" -eq 0 ] && [ -e "$PROBE" ]; then
    rm -rf "$PROBE"
  fi
}
trap cleanup EXIT

for f in "$SRC" "$KEY" "$SEAL" "$OPEN" "$BODIES"; do
  [ -f "$f" ] || { echo "FAIL: check-swift-device-key: missing $f"; exit 1; }
done

if grep -E -n 'supabase|createClient|@supabase|URLSession|URLRequest|NWConnection|Process\(|8899|hosts\.json|fetch\(|/Users/' "$SRC"; then
  echo "FAIL: check-swift-device-key: key file reaches the network or a Users path"
  exit 1
fi

if grep -n 'DeviceKeyFile' "$ROOT/project.yml" "$ROOT"/MeshDesktop/*.swift >/dev/null 2>&1; then
  echo "FAIL: check-swift-device-key: the shipping menu bar calls the key file"
  exit 1
fi

SWIFTC="$(command -v swiftc)"
echo "swiftc: $("$SWIFTC" --version 2>&1 | head -n 1)"

cat > "$TMP/main.swift" <<'SWIFT'
import CryptoKit
import Darwin
import Foundation

func fail(_ message: String) -> Never {
    fputs("FAIL: check-swift-device-key: \(message)\n", stderr)
    exit(1)
}

func base64urlEncode(_ data: Data) -> String {
    data.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}

func jsonString(_ value: String) -> String {
    var out = "\""
    for scalar in value.unicodeScalars {
        switch scalar {
        case "\\":
            out += "\\\\"
        case "\"":
            out += "\\\""
        case "\n":
            out += "\\n"
        case "\r":
            out += "\\r"
        case "\t":
            out += "\\t"
        default:
            if scalar.value < 0x20 {
                out += String(format: "\\u%04x", scalar.value)
            } else {
                out.unicodeScalars.append(scalar)
            }
        }
    }
    out += "\""
    return out
}

func readText(_ path: String) -> String {
    guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
        fail("could not read input")
    }
    return text.trimmingCharacters(in: .whitespacesAndNewlines)
}

func readBytes(_ path: String) -> Data {
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
        fail("could not read input")
    }
    return data
}

func writeText(_ path: String, _ text: String) {
    do {
        try text.write(toFile: path, atomically: true, encoding: .utf8)
    } catch {
        fail("could not write output")
    }
}

enum MailboxOpen {
    static let version: UInt8 = 1
    static let pubLen = 32
    static let nonceLen = 12
    static let tagLen = 16
    static let info = Data("mesh-sealed-mailbox-v1".utf8)
    static let maxChars = 16384

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

    static func open(_ ciphertext: String, privateKey: Curve25519.KeyAgreement.PrivateKey) throws -> Data {
        guard let packed = base64urlDecode(ciphertext) else { throw DeviceKeyFile.Failure.couldNotOpen }
        let minPacked = 1 + pubLen + nonceLen + tagLen
        guard packed.count >= minPacked, packed.first == version else { throw DeviceKeyFile.Failure.couldNotOpen }
        let ephRaw = packed.subdata(in: 1..<(1 + pubLen))
        let nonceData = packed.subdata(in: (1 + pubLen)..<(1 + pubLen + nonceLen))
        let bodyAndTag = packed.subdata(in: (1 + pubLen + nonceLen)..<packed.count)
        guard ephRaw.count == pubLen, nonceData.count == nonceLen, bodyAndTag.count >= tagLen else {
            throw DeviceKeyFile.Failure.couldNotOpen
        }
        let body = Data(bodyAndTag.prefix(bodyAndTag.count - tagLen))
        let tag = Data(bodyAndTag.suffix(tagLen))
        let ephPub = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: ephRaw)
        let shared = try privateKey.sharedSecretFromKeyAgreement(with: ephPub)
        let key = shared.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: ephRaw,
            sharedInfo: info,
            outputByteCount: 32
        )
        let nonce = try AES.GCM.Nonce(data: nonceData)
        let box = try AES.GCM.SealedBox(nonce: nonce, ciphertext: body, tag: tag)
        var aad = Data([version])
        aad.append(ephRaw)
        return try AES.GCM.open(box, using: key, authenticating: aad)
    }
}

func scalarEncodings(_ key: Curve25519.KeyAgreement.PrivateKey) -> [String] {
    let raw = key.rawRepresentation
    let hex = raw.map { String(format: "%02x", $0) }.joined()
    return [base64urlEncode(raw), raw.base64EncodedString(), hex, hex.uppercased()]
}

func assertPrivateKeyAbsent(_ text: String, _ key: Curve25519.KeyAgreement.PrivateKey) {
    let raw = key.rawRepresentation
    for encoding in scalarEncodings(key) where !encoding.isEmpty {
        if text.contains(encoding) { fail("private key is in a JSON body") }
    }
    if Data(text.utf8).range(of: raw) != nil { fail("private key is in a JSON body") }
    if text.contains("fixture-token-not-a-secret") || text.contains("203.0.113.10") {
        fail("fixture secret is in a JSON body")
    }
}

func replaceKey(_ path: String, _ bytes: Data) {
    let fd = path.withCString {
        Darwin.open($0, Darwin.O_WRONLY | Darwin.O_TRUNC | Darwin.O_NOFOLLOW, mode_t(0o600))
    }
    if fd < 0 { fail("could not rewrite the key file") }
    defer { _ = Darwin.close(fd) }
    let written = bytes.withUnsafeBytes { raw -> Int in
        guard let base = raw.baseAddress else { return -1 }
        return Darwin.write(fd, base, bytes.count)
    }
    if written != bytes.count { fail("could not rewrite the key file") }
    if Darwin.fchmod(fd, 0o600) != 0 { fail("could not keep the key file mode") }
}

func expectClosed(_ stateDir: String, _ label: String) {
    var caught = 0
    do {
        _ = try DeviceKeyFile.load(stateDir: stateDir)
    } catch let error as DeviceKeyFile.Failure {
        caught += 1
        if error != .couldNotOpen { fail("\(label) raised a different error") }
    } catch {
        fail("\(label) raised a different error")
    }
    if caught != 1 { fail("\(label) did not fail closed") }
}

func expectRefused(_ path: String, _ key: Curve25519.KeyAgreement.PrivateKey) {
    let existed = FileManager.default.fileExists(atPath: path)
    let keyPath = (path as NSString).appendingPathComponent("device.key")
    let keyExisted = FileManager.default.fileExists(atPath: keyPath)
    var caught = 0
    do {
        try DeviceKeyFile.save(privateKey: key, stateDir: path)
    } catch let error as DeviceKeyFile.Failure {
        caught += 1
        if error != .notAllowed { fail("a refused path raised a different error") }
    } catch {
        fail("a refused path raised a different error")
    }
    if caught != 1 { fail("a refused path was accepted") }
    if !existed && FileManager.default.fileExists(atPath: path) {
        fail("a refused directory was created")
    }
    if !keyExisted && FileManager.default.fileExists(atPath: keyPath) {
        fail("a key file was written to a refused path")
    }
}

let args = Array(CommandLine.arguments.dropFirst())
guard let command = args.first else { fail("missing command") }

switch command {
case "write":
    guard args.count == 3 else { fail("write needs a state directory and a public key path") }
    let stateDir = args[1]
    let keyFile = (stateDir as NSString).appendingPathComponent("device.key")
    if FileManager.default.fileExists(atPath: keyFile) { fail("device.key existed before save") }
    let key = Curve25519.KeyAgreement.PrivateKey()
    do {
        try DeviceKeyFile.save(privateKey: key, stateDir: stateDir)
        let loaded = try DeviceKeyFile.load(stateDir: stateDir)
        guard loaded.rawRepresentation == key.rawRepresentation else { fail("reloaded scalar does not match") }
        guard loaded.publicKey.rawRepresentation == key.publicKey.rawRepresentation else {
            fail("reloaded public key does not match")
        }
        let stored = readBytes(keyFile)
        guard stored.count == 64 else { fail("device.key is not 64 bytes") }
        guard stored.prefix(32) == key.rawRepresentation else { fail("device.key scalar does not match") }
        guard stored.suffix(32) == key.publicKey.rawRepresentation else { fail("device.key public key does not match") }
        writeText(args[2], base64urlEncode(loaded.publicKey.rawRepresentation))
    } catch {
        fail("could not write the device key")
    }
    print("reloaded_public_key: match")
    print("key_file_bytes: 64")

case "bodies":
    guard args.count == 5 else { fail("bodies needs a state directory, ciphertext, and two outputs") }
    let loaded: Curve25519.KeyAgreement.PrivateKey
    do {
        loaded = try DeviceKeyFile.load(stateDir: args[1])
    } catch {
        fail("could not load the device key")
    }
    let ciphertext = readText(args[2])
    let registration = "{\"label\":\(jsonString("Kitchen Mac")),\"platform\":\(jsonString("macos")),\"public_key\":\(jsonString(base64urlEncode(loaded.publicKey.rawRepresentation)))}"
    let mailbox = "{\"ciphertext\":\(jsonString(ciphertext))}"
    assertPrivateKeyAbsent(registration, loaded)
    assertPrivateKeyAbsent(mailbox, loaded)
    writeText(args[3], registration)
    writeText(args[4], mailbox)
    print("private_key_in_bodies: false")

case "open":
    guard args.count == 5 else { fail("open needs a state directory, ciphertext, plaintext, and a label") }
    let loaded: Curve25519.KeyAgreement.PrivateKey
    do {
        loaded = try DeviceKeyFile.load(stateDir: args[1])
    } catch {
        fail("could not load the device key")
    }
    let opened: Data
    do {
        opened = try MailboxOpen.open(readText(args[2]), privateKey: loaded)
    } catch {
        fail("the loaded key did not open the mailbox")
    }
    if opened != readBytes(args[3]) { fail("the loaded key did not open the mailbox") }
    print("\(args[4]): true")

case "flip":
    guard args.count == 2 else { fail("flip needs a state directory") }
    let stateDir = args[1]
    let keyFile = (stateDir as NSString).appendingPathComponent("device.key")
    let good = readBytes(keyFile)
    guard good.count == 64 else { fail("device.key is not 64 bytes") }
    var flipped = 0
    for index in 0..<good.count {
        var buf = good
        buf[index] ^= 0xff
        if buf[index] == good[index] { fail("flip did not change a byte") }
        replaceKey(keyFile, buf)
        expectClosed(stateDir, "flipped byte")
        flipped += 1
    }
    if flipped != 64 { fail("did not flip every key byte") }
    for (index, bit) in [(0, UInt8(0x01)), (0, UInt8(0x02)), (0, UInt8(0x04)), (31, UInt8(0x80)), (31, UInt8(0x40))] {
        var buf = good
        buf[index] ^= bit
        replaceKey(keyFile, buf)
        expectClosed(stateDir, "flipped clamp bit")
    }
    replaceKey(keyFile, good.prefix(63))
    expectClosed(stateDir, "truncated file")
    replaceKey(keyFile, Data())
    expectClosed(stateDir, "empty file")
    replaceKey(keyFile, good)
    do {
        let loaded = try DeviceKeyFile.load(stateDir: stateDir)
        guard loaded.rawRepresentation == good.prefix(32) else { fail("restored key file did not load") }
        guard loaded.publicKey.rawRepresentation == good.suffix(32) else { fail("restored key file did not load") }
    } catch {
        fail("restored key file did not load")
    }
    print("flipped_byte: closed")
    print("truncated_file: closed")

case "refuse":
    guard args.count >= 2 else { fail("refuse needs a path") }
    let key = Curve25519.KeyAgreement.PrivateKey()
    for path in args.dropFirst() {
        expectRefused(path, key)
    }
    print("refused_paths: closed")

case "refuse-home":
    guard args.count == 1 else { fail("refuse-home takes no path") }
    guard let pw = getpwuid(getuid()) else { fail("could not resolve the home directory") }
    let passwdHome = String(cString: pw.pointee.pw_dir)
    if passwdHome.isEmpty || passwdHome == "/" { fail("could not resolve the home directory") }
    let key = Curve25519.KeyAgreement.PrivateKey()
    var seen = Set<String>()
    for home in [passwdHome, FileManager.default.homeDirectoryForCurrentUser.path] {
        if !seen.insert(home).inserted { continue }
        expectRefused(home, key)
        expectRefused((home as NSString).appendingPathComponent(".mesh"), key)
        expectRefused((home as NSString).appendingPathComponent("state"), key)
    }
    print("real_home_write: false")

default:
    fail("unknown command")
}
SWIFT

if ! grep -q 'DeviceKeyFile.save' "$TMP/main.swift" || ! grep -q 'DeviceKeyFile.load' "$TMP/main.swift"; then
  echo "FAIL: check-swift-device-key: driver does not call DeviceKeyFile"
  exit 1
fi

"$SWIFTC" -Onone -o "$TMP/device-key" "$SRC" "$TMP/main.swift" 2>"$TMP/swiftc.err" || {
  echo "FAIL: check-swift-device-key: does not compile"
  tail -n 20 "$TMP/swiftc.err"
  exit 1
}

mkdir -p "$HOME_DIR" "$OUT"
chmod 700 "$HOME_DIR"

env -u USERPROFILE -u MESHD_STATE \
  HOME="$HOME_DIR" \
  MESHD_STATE="$ENV_STATE" \
  "$TMP/device-key" write "$STATE_DIR" "$OUT/public.txt"

if [ -e "$ENV_STATE/device.key" ]; then
  echo "FAIL: check-swift-device-key: MESHD_STATE overrode the state directory"
  exit 1
fi

cat > "$TMP/drive.js" <<'NODE'
const fs = require("node:fs");
const path = require("node:path");
const crypto = require("node:crypto");
const { loadDeviceKey, saveDeviceKey } = require(process.env.ROOT + "/experiments/device-sync/key-file.ts");
const { generateDeviceKeyPair, seal } = require(process.env.ROOT + "/experiments/sealed-mailbox/seal.ts");
const { open } = require(process.env.ROOT + "/experiments/sealed-mailbox/open.ts");

function fail(message) {
  console.error(`FAIL: check-swift-device-key: ${message}`);
  process.exit(1);
}

function scalarEncodings(privateKey) {
  const jwk = privateKey.export({ format: "jwk" });
  if (typeof jwk.d !== "string") fail("loaded key has no scalar");
  const raw = Buffer.from(jwk.d, "base64url");
  if (raw.length !== 32) fail("loaded key is not 32 bytes");
  const pem = String(privateKey.export({ format: "pem", type: "pkcs8" }));
  const pemBody = pem.replace(/-----[A-Z ]+-----/g, "").replace(/\s+/g, "");
  return [jwk.d, raw.toString("base64"), raw.toString("hex"), pemBody];
}

const command = process.argv[2];
const plaintext = {
  token: "fixture-token-not-a-secret",
  fleet: [{ host: "fixture-mac", ip: "203.0.113.10", port: 8898, token: "fixture-token-not-a-secret" }],
};

if (command === "seal") {
  const loaded = loadDeviceKey({ stateDir: process.env.STATE_DIR });
  const jwk = loaded.export({ format: "jwk" });
  const pub = fs.readFileSync(process.env.PUB, "utf8").trim();
  if (jwk.x !== pub) fail("swift public key does not match the key file");
  const stored = fs.readFileSync(path.join(process.env.STATE_DIR, "device.key"));
  const scalar = Buffer.from(jwk.d, "base64url");
  const pubRaw = Buffer.from(jwk.x, "base64url");
  if (stored.length !== 64 || !stored.subarray(0, 32).equals(scalar) || !stored.subarray(32).equals(pubRaw)) {
    fail("device.key is not the scalar and public key");
  }
  const recipient = crypto.createPublicKey({
    key: { kty: "OKP", crv: "X25519", x: jwk.x },
    format: "jwk",
  });
  const ciphertext = seal(plaintext, recipient);
  if (ciphertext.includes(plaintext.token) || ciphertext.includes(plaintext.fleet[0].ip)) {
    fail("ciphertext contains the fixture");
  }
  const opened = open(ciphertext, loaded);
  if (JSON.stringify(opened) !== JSON.stringify(plaintext)) fail("node did not open the swift key file");
  fs.writeFileSync(process.env.CT, ciphertext);
  fs.writeFileSync(process.env.PLAIN, JSON.stringify(plaintext));

  const pair = generateDeviceKeyPair();
  saveDeviceKey({ privateKey: pair.privateKey, stateDir: process.env.NODE_STATE });
  const nodeLoaded = loadDeviceKey({ stateDir: process.env.NODE_STATE });
  const nodeJwk = nodeLoaded.export({ format: "jwk" });
  const nodeCiphertext = seal(plaintext, pair.publicKey);
  const nodeOpened = open(nodeCiphertext, nodeLoaded);
  if (JSON.stringify(nodeOpened) !== JSON.stringify(plaintext)) fail("node did not open the node key file");
  fs.writeFileSync(process.env.NODE_CT, nodeCiphertext);
  fs.writeFileSync(process.env.NODE_PLAIN, JSON.stringify(plaintext));
  fs.writeFileSync(process.env.NODE_PUB, String(nodeJwk.x));
  console.log("node_opens_swift_file: true");
  console.log("node_opens_node_file: true");
} else if (command === "bodies") {
  const loaded = loadDeviceKey({ stateDir: process.env.STATE_DIR });
  const registrationText = fs.readFileSync(process.env.REG, "utf8");
  const mailboxText = fs.readFileSync(process.env.MAIL, "utf8");
  const encodings = scalarEncodings(loaded);
  for (const text of [registrationText, mailboxText]) {
    for (const encoding of encodings) {
      if (encoding.length > 0 && text.includes(encoding)) fail("private key is in a JSON body");
    }
    if (text.includes(plaintext.token)) fail("fixture token is in a JSON body");
    if (text.includes(plaintext.fleet[0].ip)) fail("fixture address is in a JSON body");
  }
  const registration = JSON.parse(registrationText);
  const mailbox = JSON.parse(mailboxText);
  if (Object.keys(registration).join(",") !== "label,platform,public_key") {
    fail("registration body is not label, platform, and public_key");
  }
  if (Object.keys(mailbox).join(",") !== "ciphertext") fail("mailbox body is not only ciphertext");
  const jwk = loaded.export({ format: "jwk" });
  if (registration.public_key !== jwk.x) fail("registration public key is not the device public key");
  if (registration.label !== "Kitchen Mac" || registration.platform !== "macos") {
    fail("registration fields changed");
  }
  const ciphertext = fs.readFileSync(process.env.CT, "utf8").trim();
  if (mailbox.ciphertext !== ciphertext) fail("mailbox ciphertext is not the sealed blob");
  console.log("registration_keys: label,platform,public_key");
  console.log("mailbox_keys: ciphertext");
  console.log("private_key_in_bodies: false");
  console.log("token_in_bodies: false");
  console.log("address_in_bodies: false");
} else {
  fail("unknown node command");
}
NODE

env -u USERPROFILE \
  HOME="$HOME_DIR" \
  NODE_NO_WARNINGS=1 \
  ROOT="$ROOT" \
  STATE_DIR="$STATE_DIR" \
  NODE_STATE="$NODE_STATE" \
  PUB="$OUT/public.txt" \
  CT="$OUT/ciphertext.txt" \
  PLAIN="$OUT/plaintext.json" \
  NODE_CT="$OUT/node-ciphertext.txt" \
  NODE_PLAIN="$OUT/node-plaintext.json" \
  NODE_PUB="$OUT/node-public.txt" \
  node --experimental-strip-types "$TMP/drive.js" seal

env -u USERPROFILE HOME="$HOME_DIR" \
  "$TMP/device-key" bodies "$STATE_DIR" "$OUT/ciphertext.txt" "$OUT/registration.json" "$OUT/mailbox.json"

env -u USERPROFILE \
  HOME="$HOME_DIR" \
  NODE_NO_WARNINGS=1 \
  ROOT="$ROOT" \
  STATE_DIR="$STATE_DIR" \
  REG="$OUT/registration.json" \
  MAIL="$OUT/mailbox.json" \
  CT="$OUT/ciphertext.txt" \
  node --experimental-strip-types "$TMP/drive.js" bodies

env -u USERPROFILE HOME="$HOME_DIR" \
  "$TMP/device-key" open "$STATE_DIR" "$OUT/ciphertext.txt" "$OUT/plaintext.json" swift_opens_node_seal

env -u USERPROFILE HOME="$HOME_DIR" \
  "$TMP/device-key" open "$NODE_STATE" "$OUT/node-ciphertext.txt" "$OUT/node-plaintext.json" swift_opens_node_file

env -u USERPROFILE HOME="$HOME_DIR" \
  "$TMP/device-key" flip "$STATE_DIR"

ln -s "$HOME_DIR" "$TMP/home-link"
env -u USERPROFILE HOME="$HOME_DIR" \
  "$TMP/device-key" refuse "$HOME_DIR" "$HOME_DIR/.mesh" "$HOME_DIR/state" "$PROBE" "$TMP/home-link"

if [ "$probe_existed" -eq 0 ] && [ -e "$PROBE" ]; then
  echo "FAIL: check-swift-device-key: a Users path was created"
  exit 1
fi

env -u USERPROFILE HOME="$HOME_DIR" \
  "$TMP/device-key" refuse-home

mode_of() {
  python3 -c 'import os, sys; print(format(os.stat(sys.argv[1]).st_mode & 0o777, "o"))' "$1"
}

for dir in "$STATE_DIR" "$NODE_STATE"; do
  key_mode="$(mode_of "$dir/device.key")"
  dir_mode="$(mode_of "$dir")"
  key_bytes="$(wc -c < "$dir/device.key" | tr -d ' ')"
  [ "$key_mode" = "600" ] || { echo "FAIL: check-swift-device-key: stat mode is $key_mode"; exit 1; }
  [ "$dir_mode" = "700" ] || { echo "FAIL: check-swift-device-key: directory mode is $dir_mode"; exit 1; }
  [ "$key_bytes" = "64" ] || { echo "FAIL: check-swift-device-key: file is $key_bytes bytes"; exit 1; }
  if grep -a -F -q 'fixture-token-not-a-secret' "$dir/device.key" \
    || grep -a -F -q '203.0.113.10' "$dir/device.key" \
    || grep -a -F -q 'fixture-mac' "$dir/device.key"; then
    echo "FAIL: check-swift-device-key: key file contains a fixture secret"
    exit 1
  fi
done

if [ -e "$HOME_DIR/device.key" ] || [ -e "$HOME_DIR/.mesh" ]; then
  echo "FAIL: check-swift-device-key: key file wrote under the home directory"
  exit 1
fi
if find "$HOME_DIR" \( -name 'device.key' -o -name '.mesh' \) | grep -q .; then
  echo "FAIL: check-swift-device-key: home directory contains a key file"
  exit 1
fi

echo "state_dir_mode: 700"
echo "key_file_mode: 600"
echo "key_file_bytes: 64"
echo "home_write: false"
echo "users_path_created: false"
echo "check-swift-device-key: OK"

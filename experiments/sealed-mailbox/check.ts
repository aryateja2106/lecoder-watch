// The token below is a fixture string. It is not a mesh token and it is not
// loaded from disk. The check never writes a private key and never dials out.
const { generateDeviceKeyPair, seal } = require("./seal.ts");
const { open } = require("./open.ts");

const TOKEN = "fixture-token-not-a-secret";

function fail(message: string): never {
  console.error(`FAIL: check-sealed-mailbox: ${message}`);
  process.exit(1);
}

function mustNotOpen(ciphertext: string, privateKey: unknown, message: string): void {
  try {
    open(ciphertext, privateKey);
  } catch {
    return;
  }
  fail(message);
}

const plaintext = {
  token: TOKEN,
  fleet: [
    { host: "fixture-mac", ip: "203.0.113.10", port: 8898, token: TOKEN },
  ],
};

const recipient = generateDeviceKeyPair();
const other = generateDeviceKeyPair();
if (recipient.publicKey.export({ format: "jwk" }).x === other.publicKey.export({ format: "jwk" }).x) {
  fail("fixture keypairs collided");
}

const ciphertext = seal(plaintext, recipient.publicKey);
if (typeof ciphertext !== "string") fail("ciphertext is not a string");
if (ciphertext.length === 0 || ciphertext.length > 16384) {
  fail(`ciphertext length ${ciphertext.length} is outside 1..16384`);
}
if (ciphertext.includes(TOKEN)) fail("ciphertext contains the fixture token");

const opened = open(ciphertext, recipient.privateKey);
if (JSON.stringify(opened) !== JSON.stringify(plaintext)) {
  fail("the recipient key did not return the handoff");
}

mustNotOpen(ciphertext, other.privateKey, "a second key opened the mailbox");

mustNotOpen(ciphertext.slice(0, ciphertext.length - 8), recipient.privateKey, "a truncated blob opened");

const buf = Buffer.from(ciphertext, "base64url");
buf[buf.length - 1] ^= 0xff;
const tampered = buf.toString("base64url");
if (tampered === ciphertext) fail("tamper did not change the blob");
mustNotOpen(tampered, recipient.privateKey, "a tampered byte opened");

console.log("check-sealed-mailbox: OK");

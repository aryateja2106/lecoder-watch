// The strings below are a fixture. They are not loaded from disk and they are
// not sent anywhere. The check fails if either JSON body still contains them.
const { generateDeviceKeyPair } = require("../sealed-mailbox/seal.ts");
const { open } = require("../sealed-mailbox/open.ts");
const { buildDeviceSyncBodies } = require("./client.ts");

const TOKEN = "fixture-token-not-a-secret";
const ADDRESS = "203.0.113.10";
const HOST = "fixture-mac";

function fail(message: string): never {
  console.error(`FAIL: check-device-sync: ${message}`);
  process.exit(1);
}

function mustStayClosed(ciphertext: string, privateKey: unknown, message: string): void {
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
    { host: HOST, ip: ADDRESS, port: 8898, token: TOKEN },
  ],
};

const recipient = generateDeviceKeyPair();
const stranger = generateDeviceKeyPair();
if (recipient.publicKey.export({ format: "jwk" }).x === stranger.publicKey.export({ format: "jwk" }).x) {
  fail("fixture keypairs collided");
}

const built = buildDeviceSyncBodies({
  label: "Kitchen Mac",
  platform: "macos",
  recipientPublicKey: recipient.publicKey,
  plaintext,
});

if (typeof built.registration !== "string" || typeof built.mailbox !== "string") {
  fail("the client did not return JSON bodies");
}

const registration = JSON.parse(built.registration);
const mailbox = JSON.parse(built.mailbox);
const whole = JSON.stringify(built);

for (const [name, json] of [
  ["registration", built.registration],
  ["mailbox", built.mailbox],
  ["result", whole],
] as const) {
  if (json.includes(TOKEN)) fail(`${name} contains the fixture token`);
  if (json.includes(ADDRESS)) fail(`${name} contains the fixture address`);
  if (json.includes(HOST)) fail(`${name} contains the fixture host`);
}

const secret = built.privateKey.export({ format: "jwk" });
if (typeof secret.d !== "string" || Buffer.from(secret.d, "base64url").length !== 32) {
  fail("in-memory private key is not an x25519 scalar");
}
if (built.registration.includes(secret.d) || built.mailbox.includes(secret.d) || whole.includes(secret.d)) {
  fail("private key is in a JSON body");
}
if (whole.includes("privateKey")) fail("private key property was serialized");

const regKeys = Object.keys(registration);
if (regKeys.join(",") !== "label,platform,public_key") {
  fail(`registration keys are ${regKeys.join(",")}`);
}
if (registration.label !== "Kitchen Mac" || registration.platform !== "macos") {
  fail("registration did not keep the label and platform");
}
if (registration.public_key !== secret.x) {
  fail("registration public key is not the in-memory public key");
}
if (registration.public_key === secret.d) fail("public key is the private scalar");
if (Buffer.from(String(registration.public_key), "base64url").length !== 32) {
  fail("public key is not 32 bytes");
}

const mailKeys = Object.keys(mailbox);
if (mailKeys.length !== 1 || mailKeys[0] !== "ciphertext") {
  fail("mailbox payload is not only ciphertext");
}
const ciphertext = mailbox.ciphertext;
if (typeof ciphertext !== "string" || ciphertext.length === 0 || ciphertext.length > 16384) {
  fail("ciphertext length is outside 1..16384");
}

const opened = open(ciphertext, recipient.privateKey);
if (JSON.stringify(opened) !== JSON.stringify(plaintext)) {
  fail("the recipient key did not return the handoff");
}
mustStayClosed(ciphertext, stranger.privateKey, "a second key opened the mailbox");

let rejected = false;
try {
  buildDeviceSyncBodies({
    label: "Kitchen Mac",
    platform: "windows",
    recipientPublicKey: recipient.publicKey,
    plaintext,
  });
} catch {
  rejected = true;
}
if (!rejected) fail("an unknown platform produced a registration body");

const again = buildDeviceSyncBodies({
  label: "Kitchen Mac",
  platform: "macos",
  recipientPublicKey: recipient.publicKey,
  plaintext,
});
if (JSON.parse(again.registration).public_key === registration.public_key) {
  fail("a second call reused the device key");
}

console.log("check-device-sync: node OK");

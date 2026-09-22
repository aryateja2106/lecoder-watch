// Open a sealed fleet handoff. The wrong key, a short blob, and a flipped
// byte all take the same path: one error, and the plaintext is not returned.
// Password reset does not help here. The private key is an argument, not a
// file, and this module does not fetch anything.
import type { KeyObject } from "node:crypto";

const crypto = require("node:crypto");

type FleetMachine = {
  host: string;
  ip: string;
  port: number;
  token: string;
};

type FleetHandoff = {
  token: string;
  fleet: FleetMachine[];
};

// Wire layout, kept in lockstep with seal.ts:
//   version(1) || ephemeral public(32) || nonce(12) || aes-256-gcm body || tag(16)
const VERSION = 1;
const PUB_LEN = 32;
const NONCE_LEN = 12;
const TAG_LEN = 16;
const INFO = "mesh-sealed-mailbox-v1";
const MIN_PACKED = 1 + PUB_LEN + NONCE_LEN + TAG_LEN;
const MAX_CIPHERTEXT_CHARS = 16384;

function closed(): never {
  throw new Error("sealed mailbox could not be opened");
}

function isFleetHandoff(value: unknown): value is FleetHandoff {
  if (typeof value !== "object" || value === null || Array.isArray(value)) return false;
  const token = (value as FleetHandoff).token;
  const fleet = (value as FleetHandoff).fleet;
  if (typeof token !== "string" || token.length === 0) return false;
  if (!Array.isArray(fleet)) return false;
  return fleet.every((machine) => {
    if (typeof machine !== "object" || machine === null) return false;
    return typeof machine.host === "string"
      && typeof machine.ip === "string"
      && typeof machine.port === "number"
      && Number.isInteger(machine.port)
      && typeof machine.token === "string"
      && machine.token.length > 0;
  });
}

function publicKeyFromRaw(raw: Buffer): KeyObject {
  return crypto.createPublicKey({
    key: { kty: "OKP", crv: "X25519", x: raw.toString("base64url") },
    format: "jwk",
  });
}

function open(ciphertext: string, recipientPrivateKey: KeyObject): FleetHandoff {
  if (typeof ciphertext !== "string" || ciphertext.length === 0 || ciphertext.length > MAX_CIPHERTEXT_CHARS) {
    closed();
  }
  if (!/^[A-Za-z0-9_-]+$/.test(ciphertext)) closed();
  if (recipientPrivateKey?.asymmetricKeyType !== "x25519" || recipientPrivateKey.type !== "private") {
    closed();
  }

  const packed = Buffer.from(ciphertext, "base64url");
  if (packed.toString("base64url") !== ciphertext) closed();
  if (packed.length < MIN_PACKED || packed[0] !== VERSION) closed();

  const ephRaw = packed.subarray(1, 1 + PUB_LEN);
  const nonce = packed.subarray(1 + PUB_LEN, 1 + PUB_LEN + NONCE_LEN);
  const bodyAndTag = packed.subarray(1 + PUB_LEN + NONCE_LEN);
  if (ephRaw.length !== PUB_LEN || nonce.length !== NONCE_LEN || bodyAndTag.length < TAG_LEN) closed();
  const tag = bodyAndTag.subarray(bodyAndTag.length - TAG_LEN);
  const body = bodyAndTag.subarray(0, bodyAndTag.length - TAG_LEN);

  let json = "";
  let key: Buffer | null = null;
  try {
    const shared: Buffer = crypto.diffieHellman({
      privateKey: recipientPrivateKey,
      publicKey: publicKeyFromRaw(ephRaw),
    });
    key = Buffer.from(crypto.hkdfSync("sha256", shared, ephRaw, INFO, 32));
    shared.fill(0);
    const decipher = crypto.createDecipheriv("aes-256-gcm", key, nonce);
    decipher.setAAD(Buffer.concat([Buffer.from([VERSION]), ephRaw]));
    decipher.setAuthTag(tag);
    json = Buffer.concat([decipher.update(body), decipher.final()]).toString("utf8");
  } catch {
    closed();
  } finally {
    key?.fill(0);
  }

  let parsed: unknown;
  try {
    parsed = JSON.parse(json);
  } catch {
    closed();
  }
  if (!isFleetHandoff(parsed)) closed();
  return parsed;
}

module.exports = { open };

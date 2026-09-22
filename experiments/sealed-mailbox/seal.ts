// Seal a fleet handoff to one device's X25519 public key.
//
// The mailbox column is the string this returns and nothing else. The server
// can store that string and still cannot read a machine token: the AES key is
// HKDF of an X25519 shared secret, and the private key that completes the
// secret is the recipient's. This module keeps that key in memory. It does
// not export a private key, write a file, or talk to the network.
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

// Wire layout, kept in lockstep with open.ts:
//   version(1) || ephemeral public(32) || nonce(12) || aes-256-gcm body || tag(16)
const VERSION = 1;
const PUB_LEN = 32;
const NONCE_LEN = 12;
const TAG_LEN = 16;
const INFO = "mesh-sealed-mailbox-v1";
// mailbox.ciphertext is text, max 16384. A blob the column would reject is not a seal.
const MAX_CIPHERTEXT_CHARS = 16384;

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

function rawPublicKey(key: KeyObject): Buffer {
  const jwk = key.export({ format: "jwk" });
  const raw = Buffer.from(String(jwk.x ?? ""), "base64url");
  if (jwk.kty !== "OKP" || jwk.crv !== "X25519" || raw.length !== PUB_LEN) {
    throw new Error("seal expects an x25519 public key");
  }
  return raw;
}

function generateDeviceKeyPair(): { publicKey: KeyObject; privateKey: KeyObject } {
  return crypto.generateKeyPairSync("x25519");
}

function seal(plaintext: FleetHandoff, recipientPublicKey: KeyObject): string {
  if (!isFleetHandoff(plaintext)) throw new Error("seal expects a fleet handoff object");
  if (recipientPublicKey?.asymmetricKeyType !== "x25519" || recipientPublicKey.type !== "public") {
    throw new Error("seal expects an x25519 public key");
  }

  const json = JSON.stringify(plaintext);
  const ephemeral = crypto.generateKeyPairSync("x25519");
  const shared: Buffer = crypto.diffieHellman({
    privateKey: ephemeral.privateKey,
    publicKey: recipientPublicKey,
  });
  const ephRaw = rawPublicKey(ephemeral.publicKey);
  const key = Buffer.from(crypto.hkdfSync("sha256", shared, ephRaw, INFO, 32));
  shared.fill(0);

  const nonce = crypto.randomBytes(NONCE_LEN);
  const aad = Buffer.concat([Buffer.from([VERSION]), ephRaw]);
  const cipher = crypto.createCipheriv("aes-256-gcm", key, nonce);
  cipher.setAAD(aad);
  const body = Buffer.concat([cipher.update(json, "utf8"), cipher.final()]);
  const tag = cipher.getAuthTag();
  key.fill(0);
  if (tag.length !== TAG_LEN) throw new Error("seal failed");

  const packed = Buffer.concat([Buffer.from([VERSION]), ephRaw, nonce, body, tag]);
  const ciphertext = packed.toString("base64url");
  if (ciphertext.length === 0 || ciphertext.length > MAX_CIPHERTEXT_CHARS) {
    throw new Error("sealed blob exceeds the mailbox ciphertext limit");
  }
  return ciphertext;
}

module.exports = { generateDeviceKeyPair, seal };

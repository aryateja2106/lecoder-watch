// Two JSON bodies a later menu-bar change can send.
//
// This device mints an X25519 keypair and keeps the private key on the
// returned object. Registration is a label, a platform, and the public key.
// The mailbox body is one ciphertext from the existing seal helper. Nothing
// here writes a key file or dials out.
import type { KeyObject } from "node:crypto";

const { generateDeviceKeyPair, seal } = require("../sealed-mailbox/seal.ts");

const PLATFORMS = ["web", "ios", "watchos", "macos", "linux"];

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

type DeviceSyncBodies = {
  registration: string;
  mailbox: string;
  privateKey: KeyObject;
};

function publicKeyText(key: KeyObject): string {
  if (key?.asymmetricKeyType !== "x25519" || key.type !== "public") {
    throw new Error("device key is not an x25519 public key");
  }
  const jwk = key.export({ format: "jwk" });
  const raw = String(jwk.x ?? "");
  if (jwk.kty !== "OKP" || jwk.crv !== "X25519" || jwk.d !== undefined) {
    throw new Error("device public key export included more than the public point");
  }
  const bytes = Buffer.from(raw, "base64url");
  if (bytes.length !== 32 || raw.length === 0 || raw.length > 512) {
    throw new Error("device public key is not 32 bytes");
  }
  return raw;
}

function buildDeviceSyncBodies(input: {
  label: string;
  platform: string;
  recipientPublicKey: KeyObject;
  plaintext: FleetHandoff;
}): DeviceSyncBodies {
  const label = input?.label;
  const platform = input?.platform;
  if (typeof label !== "string" || label.length < 1 || label.length > 64) {
    throw new Error("label must be 1 to 64 characters");
  }
  if (typeof platform !== "string" || !PLATFORMS.includes(platform)) {
    throw new Error("platform is not a known device kind");
  }

  const device = generateDeviceKeyPair();
  const registration = JSON.stringify({
    label,
    platform,
    public_key: publicKeyText(device.publicKey),
  });
  const mailbox = JSON.stringify({
    ciphertext: seal(input.plaintext, input.recipientPublicKey),
  });

  const bodies: DeviceSyncBodies = {
    registration,
    mailbox,
    privateKey: device.privateKey,
  };
  // A careless JSON.stringify of the whole result must not carry the key.
  Object.defineProperty(bodies, "privateKey", {
    value: device.privateKey,
    enumerable: false,
    writable: false,
    configurable: false,
  });
  return bodies;
}

module.exports = { buildDeviceSyncBodies };

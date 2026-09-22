// Register one device and seal a mailbox to another, using keys on disk.
//
// Each device passes its own state directory. The X25519 private key is
// saved and loaded with the key-file module. Registration JSON is label,
// platform, and public_key. The mailbox JSON is ciphertext sealed to the
// recipient public key. The bodies are posted with the send helper to a
// caller-supplied base URL. Opening reloads the recipient key from disk.
// This file does not choose a directory under the caller's account, start
// a daemon, or call Supabase. The shipping menu bar does not call it.
import type { KeyObject } from "node:crypto";

const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");
const { generateDeviceKeyPair, seal } = require("../sealed-mailbox/seal.ts");
const { open } = require("../sealed-mailbox/open.ts");
const { saveDeviceKey, loadDeviceKey } = require("./key-file.ts");
const { sendDeviceSyncBodies } = require("./send.ts");

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

type RoundTripPost = {
  registration: string;
  mailbox: string;
  senderPublicKey: string;
  recipientPublicKey: string;
};

function publicKeyText(privateKey: KeyObject): string {
  if (privateKey?.asymmetricKeyType !== "x25519" || privateKey.type !== "private") {
    throw new Error("device key is not an x25519 private key");
  }
  const jwk = privateKey.export({ format: "jwk" });
  if (jwk.kty !== "OKP" || jwk.crv !== "X25519" || typeof jwk.x !== "string" || typeof jwk.d !== "string") {
    throw new Error("device key is not an x25519 private key");
  }
  const raw = Buffer.from(jwk.x, "base64url");
  if (raw.length !== 32 || jwk.x === jwk.d) {
    throw new Error("device public key is not 32 bytes");
  }
  return jwk.x;
}

function publicKeyObject(privateKey: KeyObject): KeyObject {
  return crypto.createPublicKey({
    key: { kty: "OKP", crv: "X25519", x: publicKeyText(privateKey) },
    format: "jwk",
  });
}

function loadOrCreate(stateDir: string): KeyObject {
  const file = path.join(path.resolve(stateDir), "device.key");
  if (!fs.existsSync(file)) {
    const created = generateDeviceKeyPair();
    saveDeviceKey({ privateKey: created.privateKey, stateDir });
  }
  return loadDeviceKey({ stateDir });
}

function refusePrivateKey(bodies: string[], privateKey: KeyObject): void {
  const scalar = privateKey.export({ format: "jwk" }).d;
  if (typeof scalar !== "string" || scalar.length === 0) {
    throw new Error("device key is not an x25519 private key");
  }
  for (const body of bodies) {
    if (body.includes(scalar)) {
      throw new Error("device sync round trip refused to post a private key");
    }
  }
}

async function postDeviceSync(input: {
  base: string;
  senderStateDir: string;
  recipientStateDir: string;
  label: string;
  platform: string;
  plaintext: FleetHandoff;
  accessToken?: string;
}): Promise<RoundTripPost> {
  if (input === null || typeof input !== "object") {
    throw new Error("device sync round trip input is required");
  }
  const sender = loadOrCreate(input.senderStateDir);
  const recipient = loadOrCreate(input.recipientStateDir);
  const senderPublicKey = publicKeyText(sender);
  const recipientPublicKey = publicKeyText(recipient);
  const registration = JSON.stringify({
    label: input.label,
    platform: input.platform,
    public_key: senderPublicKey,
  });
  const mailbox = JSON.stringify({
    ciphertext: seal(input.plaintext, publicKeyObject(recipient)),
  });
  refusePrivateKey([registration, mailbox], sender);
  refusePrivateKey([registration, mailbox], recipient);
  await sendDeviceSyncBodies({
    base: input.base,
    registration,
    mailbox,
    accessToken: input.accessToken,
  });
  return { registration, mailbox, senderPublicKey, recipientPublicKey };
}

function openMailbox(input: { stateDir: string; ciphertext: string }): FleetHandoff {
  if (input === null || typeof input !== "object") {
    throw new Error("device sync round trip input is required");
  }
  const privateKey = loadDeviceKey({ stateDir: input.stateDir });
  return open(input.ciphertext, privateKey);
}

module.exports = { postDeviceSync, openMailbox };

// Keep this device's X25519 private key on the machine.
//
// The sealed send posts a public key and a ciphertext. A later open needs
// the same private scalar, so the caller passes a state directory (or
// MESHD_STATE) and this module writes <stateDir>/device.key mode 600.
// The directory is mode 700. The file is the scalar and the matching
// public key, and nothing else: no mesh token, no host, no address.
// A short file or a flipped byte fails closed with one error. This module
// does not post the key and does not write under a home directory.
import type { KeyObject } from "node:crypto";

const crypto = require("node:crypto");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

const SCALAR_LEN = 32;
const FILE_LEN = SCALAR_LEN * 2;
const FILE_NAME = "device.key";
// Fixed X25519 PKCS#8 header (OID 1.3.101.110) plus a 32-byte scalar.
const PKCS8_PREFIX = Buffer.from("302e020100300506032b656e04220420", "hex");

function closed(): never {
  throw new Error("device key file could not be opened");
}

function notAllowed(): never {
  throw new Error("device key state directory is not allowed");
}

function deniedSegments(value: string): boolean {
  return value.split(/[/\\]+/).some((part) => part === ".mesh" || part === "Users");
}

function addHome(homes: string[], value: string | undefined): void {
  if (typeof value !== "string" || value.length === 0) return;
  const abs = path.resolve(value);
  if (abs === path.parse(abs).root) return;
  homes.push(abs);
  try {
    const real = fs.realpathSync(abs);
    if (real !== path.parse(real).root) homes.push(real);
  } catch {
    // A missing home directory is not a place we can write.
  }
}

function underHome(dir: string): boolean {
  const homes: string[] = [];
  try {
    addHome(homes, os.homedir());
  } catch {
    // No home directory from the OS. HOME is still checked below.
  }
  addHome(homes, process.env.HOME);
  addHome(homes, process.env.USERPROFILE);
  return homes.some((home) => {
    const rel = path.relative(home, dir);
    return rel === "" || (!rel.startsWith("..") && !path.isAbsolute(rel));
  });
}

function assertAllowed(dir: string): void {
  if (deniedSegments(dir) || underHome(dir)) notAllowed();
  const root = path.parse(dir).root;
  if (dir === root) notAllowed();
  if (dir === "/tmp" || dir === "/var/tmp" || dir === "/private/tmp" || dir === "/home" || dir === "/root") {
    notAllowed();
  }
}

function resolveExisting(resolved: string): string {
  let cursor = resolved;
  const suffix: string[] = [];
  const root = path.parse(resolved).root;
  while (cursor !== root && !fs.existsSync(cursor)) {
    suffix.push(path.basename(cursor));
    cursor = path.dirname(cursor);
  }
  let real: string;
  try {
    real = fs.realpathSync(cursor);
  } catch {
    notAllowed();
  }
  for (let i = suffix.length - 1; i >= 0; i -= 1) {
    real = path.join(real, suffix[i]);
  }
  return real;
}

function stateDirectory(stateDir: string | undefined): string {
  if (stateDir !== undefined && typeof stateDir !== "string") {
    throw new Error("device key state directory is required");
  }
  const raw = stateDir !== undefined ? stateDir : process.env.MESHD_STATE;
  if (typeof raw !== "string" || raw.length === 0 || raw.includes("\0")) {
    throw new Error("device key state directory is required");
  }
  if (raw.includes("~") || deniedSegments(raw)) notAllowed();
  const resolved = path.resolve(raw);
  assertAllowed(resolved);
  const real = resolveExisting(resolved);
  assertAllowed(real);
  return real;
}

function same32(left: Buffer, right: Buffer): boolean {
  if (left.length !== SCALAR_LEN || right.length !== SCALAR_LEN) return false;
  return crypto.timingSafeEqual(left, right);
}

function isCanonical(scalar: Buffer): boolean {
  if (scalar.length !== SCALAR_LEN) return false;
  if ((scalar[0] & 7) !== 0) return false;
  if ((scalar[31] & 0x80) !== 0) return false;
  if ((scalar[31] & 0x40) === 0) return false;
  return true;
}

function privateKeyFromScalar(scalar: Buffer): KeyObject {
  if (!isCanonical(scalar)) {
    throw new Error("device key is not an x25519 private key");
  }
  const der = Buffer.concat([PKCS8_PREFIX, scalar]);
  try {
    const key = crypto.createPrivateKey({ key: der, format: "der", type: "pkcs8" });
    if (key.asymmetricKeyType !== "x25519" || key.type !== "private") {
      throw new Error("device key is not an x25519 private key");
    }
    return key;
  } finally {
    der.fill(0);
  }
}

function keyMaterial(privateKey: KeyObject): Buffer {
  if (privateKey?.asymmetricKeyType !== "x25519" || privateKey.type !== "private") {
    throw new Error("device key is not an x25519 private key");
  }
  const jwk = privateKey.export({ format: "jwk" });
  if (jwk.kty !== "OKP" || jwk.crv !== "X25519" || typeof jwk.d !== "string" || typeof jwk.x !== "string") {
    throw new Error("device key is not an x25519 private key");
  }
  const scalar = Buffer.from(jwk.d, "base64url");
  const pub = Buffer.from(jwk.x, "base64url");
  if (scalar.length !== SCALAR_LEN || pub.length !== SCALAR_LEN) {
    scalar.fill(0);
    pub.fill(0);
    throw new Error("device key is not an x25519 private key");
  }
  const clamped = Buffer.from(scalar);
  clamped[0] &= 248;
  clamped[31] &= 127;
  clamped[31] |= 64;
  try {
    const restored = privateKeyFromScalar(clamped);
    const again = restored.export({ format: "jwk" });
    const againScalar = Buffer.from(String(again.d ?? ""), "base64url");
    const againPub = Buffer.from(String(again.x ?? ""), "base64url");
    const matches = same32(againScalar, clamped) && same32(againPub, pub);
    againScalar.fill(0);
    againPub.fill(0);
    if (!matches) throw new Error("device key is not an x25519 private key");
    return Buffer.concat([clamped, pub]);
  } finally {
    scalar.fill(0);
    clamped.fill(0);
    pub.fill(0);
  }
}

function writeKeyFile(dir: string, body: Buffer): void {
  const file = path.join(dir, FILE_NAME);
  let fd: number | null = null;
  try {
    fs.mkdirSync(dir, { recursive: true, mode: 0o700 });
    const listed = fs.lstatSync(dir);
    if (listed.isSymbolicLink() || !listed.isDirectory()) {
      throw new Error("device key file could not be written");
    }
    const realNow = fs.realpathSync(dir);
    assertAllowed(realNow);
    if (realNow !== dir) throw new Error("device key file could not be written");
    fs.chmodSync(dir, 0o700);
    if ((fs.statSync(dir).mode & 0o777) !== 0o700) {
      throw new Error("device key file could not be written");
    }
    if (fs.existsSync(file)) {
      const current = fs.lstatSync(file);
      if (current.isSymbolicLink() || !current.isFile()) {
        throw new Error("device key file could not be written");
      }
    }
    if (typeof fs.constants.O_NOFOLLOW !== "number") {
      throw new Error("device key file could not be written");
    }
    const flags = fs.constants.O_WRONLY | fs.constants.O_CREAT | fs.constants.O_TRUNC | fs.constants.O_NOFOLLOW;
    fd = fs.openSync(file, flags, 0o600);
    fs.writeFileSync(fd, body);
    fs.fchmodSync(fd, 0o600);
    const st = fs.fstatSync(fd);
    if (!st.isFile() || st.size !== body.length || (st.mode & 0o777) !== 0o600) {
      throw new Error("device key file could not be written");
    }
  } catch (error) {
    if (fd !== null) {
      try { fs.closeSync(fd); } catch { /* the static error below is the one the caller sees */ }
      fd = null;
      try { fs.unlinkSync(file); } catch { /* a partial file must not remain */ }
    }
    if (error instanceof Error && error.message === "device key state directory is not allowed") throw error;
    throw new Error("device key file could not be written");
  } finally {
    if (fd !== null) fs.closeSync(fd);
    body.fill(0);
  }
}

function saveDeviceKey(input: { privateKey: KeyObject; stateDir?: string }): void {
  if (input === null || typeof input !== "object") {
    throw new Error("device key is not an x25519 private key");
  }
  const dir = stateDirectory(input.stateDir);
  const body = keyMaterial(input.privateKey);
  writeKeyFile(dir, body);
}

function loadDeviceKey(input?: { stateDir?: string }): KeyObject {
  const dir = stateDirectory(input?.stateDir);
  const file = path.join(dir, FILE_NAME);
  try {
    const listed = fs.lstatSync(file);
    if (listed.isSymbolicLink() || !listed.isFile() || listed.size !== FILE_LEN) closed();
    const raw = fs.readFileSync(file);
    if (raw.length !== FILE_LEN) closed();
    const scalar = raw.subarray(0, SCALAR_LEN);
    const pub = raw.subarray(SCALAR_LEN);
    if (!isCanonical(scalar)) closed();
    const key = privateKeyFromScalar(Buffer.from(scalar));
    const jwk = key.export({ format: "jwk" });
    const gotScalar = Buffer.from(String(jwk.d ?? ""), "base64url");
    const gotPub = Buffer.from(String(jwk.x ?? ""), "base64url");
    const matches = same32(gotScalar, scalar) && same32(gotPub, pub);
    gotScalar.fill(0);
    raw.fill(0);
    if (!matches) closed();
    return key;
  } catch (error) {
    if (error instanceof Error && error.message === "device key file could not be opened") throw error;
    if (error instanceof Error && error.message === "device key state directory is not allowed") throw error;
    if (error instanceof Error && error.message === "device key state directory is required") throw error;
    closed();
  }
}

module.exports = { saveDeviceKey, loadDeviceKey };

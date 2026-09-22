const MAX_BYTES = 4 * 1024;
const DROPPED = Symbol("dropped");

const SENSITIVE_KEYS = new Set([
  "token",
  "ip",
  "host",
  "hostname",
  "mac",
  "apns",
  "url",
  "path",
  "clipboard",
  "screen",
  "password",
  "authorization",
  "cookie",
]);

const IPV4 =
  /(?:^|[^0-9])(?:(?:25[0-5]|2[0-4]\d|[01]?\d\d?)\.){3}(?:25[0-5]|2[0-4]\d|[01]?\d\d?)(?![0-9])/;

function isPlainObject(value: unknown): value is Record<string, unknown> {
  if (value === null || typeof value !== "object" || Array.isArray(value)) return false;
  if (isBufferLike(value)) return false;
  const proto = Object.getPrototypeOf(value);
  return proto === Object.prototype || proto === null;
}

function isBufferLike(value: unknown): boolean {
  if (typeof Buffer !== "undefined" && Buffer.isBuffer(value)) return true;
  if (value instanceof Uint8Array || value instanceof ArrayBuffer || value instanceof DataView) return true;
  if (value === null || typeof value !== "object" || Array.isArray(value)) return false;
  const record = value as Record<string, unknown>;
  return record.type === "Buffer" && Array.isArray(record.data);
}

function keyIsSensitive(name: string): boolean {
  const parts = name
    .replace(/([a-z0-9])([A-Z])/g, "$1 $2")
    .toLowerCase()
    .split(/[^a-z0-9]+/)
    .filter((part) => part.length > 0);
  return parts.some((part) => {
    if (SENSITIVE_KEYS.has(part)) return true;
    for (const word of SENSITIVE_KEYS) {
      if (word.length >= 4 && part.startsWith(word)) return true;
    }
    return false;
  });
}

function isHextet(part: string): boolean {
  return /^[0-9a-f]{1,4}$/i.test(part);
}

function looksLikeIpv6(value: string): boolean {
  const trimmed = value.trim();
  if (!/^[0-9a-f:]+$/i.test(trimmed) || !trimmed.includes(":")) return false;
  const halves = trimmed.split("::");
  if (halves.length > 2) return false;
  if (halves.length === 2) {
    const left = halves[0] === "" ? [] : halves[0].split(":");
    const right = halves[1] === "" ? [] : halves[1].split(":");
    if (left.length + right.length > 7) return false;
    if (!left.every(isHextet) || !right.every(isHextet)) return false;
    return left.length + right.length >= 1 || trimmed === "::";
  }
  const parts = trimmed.split(":");
  return parts.length === 8 && parts.every(isHextet);
}

function looksLikeBearer(value: string): boolean {
  const trimmed = value.trim();
  if (/^bearer\s+\S{8,}$/i.test(trimmed)) return true;
  if (/^[a-f0-9]{32,}$/i.test(trimmed)) return true;
  if (/^[A-Za-z0-9+/_-]{32,}={0,2}$/.test(trimmed)) return true;
  return false;
}

function looksLikeHttpUrl(value: string): boolean {
  return /https?:\/\/\S+/i.test(value);
}

const EMBEDDED_IPV4 =
  /(?:(?:25[0-5]|2[0-4]\d|[01]?\d\d?)\.){3}(?:25[0-5]|2[0-4]\d|[01]?\d\d?)/;

function textHasEmbeddedSecret(value: string): boolean {
  if (/bearer\s+\S{8,}/i.test(value)) return true;
  if (/[a-f0-9]{32,}/i.test(value)) return true;
  if (/[A-Za-z0-9+/_-]{32,}={0,2}/.test(value)) return true;
  return EMBEDDED_IPV4.test(value);
}

export function textCarriesSecret(value: string): boolean {
  const trimmed = value.trim();
  if (IPV4.test(trimmed) || looksLikeIpv6(trimmed) || looksLikeHttpUrl(value) || looksLikeBearer(trimmed)) {
    return true;
  }
  return textHasEmbeddedSecret(value);
}

function redactEmbedded(value: string): string {
  return value
    .replace(/\b(bearer)\s+\S{8,}/gi, "$1")
    .replace(/[a-f0-9]{32,}/gi, "")
    .replace(/[A-Za-z0-9+/_-]{32,}={0,2}/g, "")
    .replace(new RegExp(EMBEDDED_IPV4.source, "g"), "");
}

function isImagePayload(value: string): boolean {
  const trimmed = value.trim();
  if (/^data:image\//i.test(trimmed)) return true;
  const compact = trimmed.replace(/\s+/g, "");
  if (compact.length < 24 || !/^[A-Za-z0-9+/]+=*$/.test(compact)) return false;
  const decoded = Buffer.from(compact, "base64");
  if (decoded.length < 12) return false;
  if (decoded[0] === 0x89 && decoded[1] === 0x50 && decoded[2] === 0x4e && decoded[3] === 0x47) return true;
  if (decoded[0] === 0xff && decoded[1] === 0xd8 && decoded[2] === 0xff) return true;
  if (decoded.subarray(0, 6).toString("ascii").startsWith("GIF8")) return true;
  if (decoded.subarray(0, 4).toString("ascii") === "RIFF" && decoded.subarray(8, 12).toString("ascii") === "WEBP") {
    return true;
  }
  return false;
}

function assertNoBuffer(value: unknown, seen: WeakSet<object>): void {
  if (isBufferLike(value)) throw new Error("refused: buffer");
  if (value === null || typeof value !== "object") return;
  if (seen.has(value)) throw new Error("refused: unsupported value");
  seen.add(value);
  const children = Array.isArray(value) ? value : Object.values(value as Record<string, unknown>);
  for (const child of children) assertNoBuffer(child, seen);
}

function serializedBytes(value: unknown): number {
  let encoded: string;
  try {
    encoded = JSON.stringify(value) ?? "";
  } catch {
    throw new Error("refused: unsupported value");
  }
  return Buffer.byteLength(encoded, "utf8");
}

function sanitizeString(value: string): unknown {
  if (Buffer.byteLength(value, "utf8") > MAX_BYTES) throw new Error("refused: value over 4 KB");
  if (isImagePayload(value)) throw new Error("refused: image payload");
  const trimmed = value.trim();
  if (looksLikeIpv6(trimmed) || looksLikeHttpUrl(value) || looksLikeBearer(trimmed)) return DROPPED;
  if (!textCarriesSecret(value)) return value;
  const redacted = redactEmbedded(value);
  if (redacted.trim() === "" || textCarriesSecret(redacted)) return DROPPED;
  return redacted;
}

function sanitize(value: unknown): unknown {
  if (isBufferLike(value)) throw new Error("refused: buffer");
  if (typeof value === "string") return sanitizeString(value);
  if (value === null || typeof value === "number" || typeof value === "boolean") return value;
  if (typeof value === "undefined") return DROPPED;
  if (typeof value !== "object") throw new Error("refused: unsupported value");
  if (serializedBytes(value) > MAX_BYTES) throw new Error("refused: value over 4 KB");
  if (Array.isArray(value)) {
    const out: unknown[] = [];
    for (const item of value) {
      const next = sanitize(item);
      if (next !== DROPPED) out.push(next);
    }
    return out;
  }
  const out: Record<string, unknown> = {};
  for (const [key, child] of Object.entries(value as Record<string, unknown>)) {
    if (keyIsSensitive(key)) continue;
    const next = sanitize(child);
    if (next !== DROPPED) out[key] = next;
  }
  return out;
}

export function filter(input: Record<string, unknown>): Record<string, unknown> {
  if (!isPlainObject(input)) throw new Error("refused: expected a JSON object");
  assertNoBuffer(input, new WeakSet());
  const result = sanitize(input);
  if (!isPlainObject(result)) throw new Error("refused: expected a JSON object");
  return result;
}

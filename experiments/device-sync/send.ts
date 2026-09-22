// POST the two sealed device-sync bodies to a caller-supplied base URL.
//
// The registration string is the body of {base}/devices. The mailbox string
// is the body of {base}/mailbox. Those strings are sent unchanged. An
// optional access token is an Authorization header. This module does not
// take a private key, and it does not put the token in either JSON body.
const PLATFORMS = ["web", "ios", "watchos", "macos", "linux"];

type JsonObject = Record<string, unknown>;

function parseObject(raw: string, what: string): JsonObject {
  let value: unknown;
  try {
    value = JSON.parse(raw);
  } catch {
    throw new Error(`${what} body is not JSON`);
  }
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    throw new Error(`${what} body is not a JSON object`);
  }
  return value as JsonObject;
}

function registrationBody(raw: string): string {
  if (typeof raw !== "string" || raw.length === 0) {
    throw new Error("registration body is required");
  }
  const parsed = parseObject(raw, "registration");
  const keys = Object.keys(parsed);
  if (keys.join(",") !== "label,platform,public_key") {
    throw new Error("registration body must be label, platform, and public_key");
  }
  const label = parsed.label;
  const platform = parsed.platform;
  const publicKey = parsed.public_key;
  if (typeof label !== "string" || label.length < 1 || label.length > 64) {
    throw new Error("registration label must be 1 to 64 characters");
  }
  if (typeof platform !== "string" || !PLATFORMS.includes(platform)) {
    throw new Error("registration platform is not a known device kind");
  }
  if (typeof publicKey !== "string" || Buffer.from(publicKey, "base64url").length !== 32) {
    throw new Error("registration public key is not 32 bytes");
  }
  return raw;
}

function mailboxBody(raw: string): string {
  if (typeof raw !== "string" || raw.length === 0) {
    throw new Error("mailbox body is required");
  }
  const parsed = parseObject(raw, "mailbox");
  const keys = Object.keys(parsed);
  if (keys.length !== 1 || keys[0] !== "ciphertext" || typeof parsed.ciphertext !== "string") {
    throw new Error("mailbox body must be only ciphertext");
  }
  if (parsed.ciphertext.length < 1 || parsed.ciphertext.length > 16384) {
    throw new Error("ciphertext length is outside 1..16384");
  }
  return raw;
}

function endpoint(base: string, name: "devices" | "mailbox"): string {
  if (typeof base !== "string" || base.length === 0) {
    throw new Error("base URL is required");
  }
  let url: URL;
  try {
    url = new URL(base);
  } catch {
    throw new Error("base URL is not a URL");
  }
  if (url.protocol !== "http:" && url.protocol !== "https:") {
    throw new Error("base URL must be http or https");
  }
  if (url.username !== "" || url.password !== "") {
    throw new Error("base URL must not carry credentials");
  }
  if (url.search !== "" || url.hash !== "") {
    throw new Error("base URL must not carry a query or fragment");
  }
  const trimmed = url.pathname.replace(/\/+$/, "");
  url.pathname = `${trimmed}/${name}`;
  return url.href;
}

function headerToken(accessToken: string | undefined, bodies: string[]): string | undefined {
  if (accessToken === undefined) return undefined;
  if (typeof accessToken !== "string" || !/^[\x21-\x7e]+$/.test(accessToken)) {
    throw new Error("access token must be a single header token");
  }
  for (const body of bodies) {
    if (body.includes(accessToken)) {
      throw new Error("access token must stay out of the JSON body");
    }
  }
  return accessToken;
}

async function postJson(url: string, body: string, accessToken: string | undefined): Promise<void> {
  if (accessToken !== undefined && url.includes(accessToken)) {
    throw new Error("access token must stay out of the URL");
  }
  const headers: Record<string, string> = {
    "content-type": "application/json",
  };
  if (accessToken !== undefined) {
    headers.authorization = `Bearer ${accessToken}`;
  }
  const response = await fetch(url, {
    method: "POST",
    headers,
    body,
    redirect: "manual",
  });
  await response.body?.cancel();
  if (response.status < 200 || response.status >= 300) {
    throw new Error("device sync post was refused");
  }
}

async function sendDeviceSyncBodies(input: {
  base: string;
  registration: string;
  mailbox: string;
  accessToken?: string;
}): Promise<void> {
  const registration = registrationBody(input?.registration);
  const mailbox = mailboxBody(input?.mailbox);
  const accessToken = headerToken(input?.accessToken, [registration, mailbox]);
  const devicesUrl = endpoint(input?.base, "devices");
  const mailboxUrl = endpoint(input?.base, "mailbox");
  await postJson(devicesUrl, registration, accessToken);
  await postJson(mailboxUrl, mailbox, accessToken);
}

module.exports = { sendDeviceSyncBodies };

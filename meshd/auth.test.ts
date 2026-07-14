// Auth gate tests for meshd — a daemon that executes shell commands, so the
// gate must be strict. The `fails CLOSED` case is the exact invariant the old
// `if (!TOKEN) return true` violated (empty token → wide-open RCE).
import { describe, expect, test } from "bun:test";
import { isAuthorized } from "./auth";

const TOKEN = "s3cret-per-machine-token-9f2a";

describe("isAuthorized (meshd bearer gate)", () => {
  test("fails CLOSED when no token is configured", () => {
    expect(isAuthorized("", `Bearer ${TOKEN}`)).toBe(false);
    expect(isAuthorized("", "")).toBe(false);
  });

  test("accepts the correct Bearer token", () => {
    expect(isAuthorized(TOKEN, `Bearer ${TOKEN}`)).toBe(true);
  });

  test("rejects a wrong token", () => {
    expect(isAuthorized(TOKEN, "Bearer wrong-token")).toBe(false);
  });

  test("rejects missing or malformed Authorization headers", () => {
    expect(isAuthorized(TOKEN, "")).toBe(false);
    expect(isAuthorized(TOKEN, TOKEN)).toBe(false); // no "Bearer " scheme
    expect(isAuthorized(TOKEN, `Basic ${TOKEN}`)).toBe(false);
    expect(isAuthorized(TOKEN, "Bearer ")).toBe(false); // empty value
    expect(isAuthorized(TOKEN, "bearer " + TOKEN)).toBe(false); // scheme is case-sensitive
  });

  test("rejects length-mismatched tokens (prefix / superset)", () => {
    expect(isAuthorized(TOKEN, `Bearer ${TOKEN}x`)).toBe(false);
    expect(isAuthorized(TOKEN, `Bearer ${TOKEN.slice(0, -1)}`)).toBe(false);
  });
});

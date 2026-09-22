// A local note is drafted only when route() returns allow-local-tool.
// Filter first, then the existing local route. This module does not call
// the gateway and does not copy its question list. The model is recorded
// only as the class "local" or "user-subscription". The assistant text is
// written to one relative file and is not run.

import { chmod, open } from "node:fs/promises";
import { constants as fsConstants } from "node:fs";
import { isAbsolute, relative, resolve } from "node:path";
import { filter } from "../jev-routing/filter.ts";
import { route, type DispatchRoute, type EvaluateResult } from "../jev-routing/route.ts";

export type ModelClass = "local" | "user-subscription";

export type DraftResult = {
  decision: DispatchRoute;
  routed: Record<string, unknown>;
  drafted: boolean;
  modelClass: ModelClass;
  file: string | null;
};

const FILE_MODE = 0o600;

export function modelClassOf(model: string): ModelClass {
  const raw = model.trim();
  if (raw === "local" || raw === "user-subscription") return raw;
  let host = "";
  try {
    const withScheme = /^[a-z][a-z0-9+.-]*:\/\//i.test(raw) ? raw : `http://${raw}`;
    host = new URL(withScheme).hostname.replace(/^\[|\]$/g, "").toLowerCase();
  } catch {
    host = "";
  }
  if (host === "127.0.0.1" || host === "localhost" || host === "::1") return "local";
  return "user-subscription";
}

function loopbackEndpoint(endpoint: string): string {
  let parsed: URL;
  try {
    parsed = new URL(endpoint);
  } catch {
    throw new Error("refused: loopback only");
  }
  if (parsed.username || parsed.password) throw new Error("refused: loopback only");
  if (parsed.protocol !== "http:" || parsed.hostname !== "127.0.0.1") {
    throw new Error("refused: loopback only");
  }
  parsed.search = "";
  parsed.hash = "";
  return parsed.toString();
}

function oneRelativeFile(file: string | undefined): string {
  const raw = (file ?? "").trim();
  const name = raw.length === 0 ? "draft.txt" : raw;
  if (name.includes("\0") || name.includes("/") || name.includes("\\")) {
    throw new Error("refused: relative file");
  }
  if (name === "." || name === ".." || isAbsolute(name)) throw new Error("refused: relative file");
  return name;
}

function assistantText(payload: unknown): string {
  if (!payload || typeof payload !== "object") throw new Error("refused: empty draft");
  const choices = (payload as { choices?: unknown }).choices;
  if (!Array.isArray(choices) || choices.length === 0) throw new Error("refused: empty draft");
  const message = (choices[0] as { message?: { content?: unknown } }).message;
  const content = message?.content;
  if (typeof content !== "string" || content.length === 0) throw new Error("refused: empty draft");
  return content;
}

async function writeOneFile(cwd: string, name: string, text: string): Promise<void> {
  const root = resolve(cwd);
  const abs = resolve(root, name);
  if (relative(root, abs) !== name) throw new Error("refused: relative file");
  const noFollow = typeof fsConstants.O_NOFOLLOW === "number" ? fsConstants.O_NOFOLLOW : 0;
  const flags = fsConstants.O_WRONLY | fsConstants.O_CREAT | fsConstants.O_TRUNC | noFollow;
  const handle = await open(abs, flags, FILE_MODE);
  try {
    await handle.writeFile(text, "utf8");
  } finally {
    await handle.close();
  }
  await chmod(abs, FILE_MODE);
}

export async function draftNote(input: {
  state: Record<string, unknown>;
  evaluation: EvaluateResult;
  endpoint: string;
  model: string;
  cwd: string;
  file?: string;
}): Promise<DraftResult> {
  const modelClass = modelClassOf(input.model);
  const routed = filter(input.state);
  const decision = route(routed, input.evaluation);
  if (decision !== "allow-local-tool") {
    return { decision, routed, drafted: false, modelClass, file: null };
  }

  const name = oneRelativeFile(input.file);
  const endpoint = loopbackEndpoint(input.endpoint);
  const response = await fetch(endpoint, {
    method: "POST",
    redirect: "error",
    signal: AbortSignal.timeout(2000),
    headers: { "content-type": "application/json", accept: "application/json" },
    body: JSON.stringify({
      model: modelClass,
      messages: [{ role: "user", content: JSON.stringify(routed) }],
    }),
  });
  if (!response.ok) {
    try {
      await response.body?.cancel();
    } catch {
      /* the status is enough */
    }
    throw new Error("refused: empty draft");
  }
  let payload: unknown;
  try {
    payload = await response.json();
  } catch {
    throw new Error("refused: empty draft");
  }
  const text = assistantText(payload);
  await writeOneFile(input.cwd, name, text);
  return { decision, routed, drafted: true, modelClass, file: name };
}

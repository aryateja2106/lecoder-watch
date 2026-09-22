import { createServer, type IncomingMessage, type ServerResponse } from "node:http";
import { readFileSync, existsSync } from "node:fs";
import { mkdtemp, readdir, rm, stat } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { filter } from "../jev-routing/filter.ts";
import { route, type EvaluateResult } from "../jev-routing/route.ts";
import { draftNote, modelClassOf, type ModelClass } from "./draft.ts";

const here = dirname(fileURLToPath(import.meta.url));
const fixtures = JSON.parse(readFileSync(join(here, "../jev-routing/fixtures.json"), "utf8")) as {
  notePage: { title: string; text: string };
  uploadToken: { text: string };
  withSecret: { token: unknown; ip: unknown };
  sendPairingCode: { text: string };
  copyHosts: { text: string };
  readMeshToken: { text: string };
  sendMeshBearer: { text: string };
  summarizePaper: { text: string };
  sendMessage: { text: string };
};

const FAKE_TOKEN = String(fixtures.withSecret.token);
const FAKE_IP = String(fixtures.withSecret.ip);
const ASSISTANT = "echo note-route-draft-executed > executed-draft\n";
const FILE_NAME = "draft.txt";

type Hit = { raw: string; authorization: string | undefined };

function fail(message: string): never {
  console.error("FAIL: " + message);
  process.exit(1);
}

function allowEval(overrides: Partial<EvaluateResult> = {}): EvaluateResult {
  return {
    surface: "terminal-text",
    choice: "allow-local-tool",
    score: 0.2,
    boolean: true,
    confidence: 0.6,
    ...overrides,
  };
}

function pageState(): Record<string, unknown> {
  return {
    title: fixtures.notePage.title,
    text: fixtures.notePage.text,
    token: FAKE_TOKEN,
    ip: FAKE_IP,
  };
}

function secretState(): Record<string, unknown> {
  return {
    text: fixtures.uploadToken.text,
    token: FAKE_TOKEN,
    ip: FAKE_IP,
  };
}

function assertClass(value: ModelClass, label: string): void {
  if (value !== "local" && value !== "user-subscription") fail(label + " model class");
}

function assertRoutedClean(routed: Record<string, unknown>, label: string): void {
  const encoded = JSON.stringify(routed);
  if (encoded.includes(FAKE_TOKEN)) fail(label + " routed the fixture token");
  if (encoded.includes(FAKE_IP)) fail(label + " routed the fixture address");
  if ("token" in routed || "ip" in routed) fail(label + " kept a sensitive key");
}

async function main(): Promise<void> {
  if (typeof process.env.AI_GATEWAY_API_KEY === "string" && process.env.AI_GATEWAY_API_KEY.length > 0) {
    fail("AI_GATEWAY_API_KEY must stay unset");
  }
  process.umask(0);

  const draftSource = readFileSync(join(here, "draft.ts"), "utf8");
  if (draftSource.includes("liveGatewayCall") || draftSource.includes("ai-gateway.vercel.sh")) {
    fail("draft module reaches the gateway");
  }
  if (draftSource.includes("Where should this turn be shown") || draftSource.includes("QUESTIONS")) {
    fail("question list was forked");
  }
  if (/\b(child_process|spawn|execFile)\b/.test(draftSource)) fail("draft module can run a file");

  if (modelClassOf("local") !== "local") fail("local class");
  if (modelClassOf("user-subscription") !== "user-subscription") fail("subscription class");
  if (modelClassOf("http://127.0.0.1:9/v1/chat/completions") !== "local") fail("loopback class");
  if (modelClassOf("gpt-4o") !== "user-subscription") fail("vendor model was not reduced to a class");
  if (modelClassOf("https://api.openai.com/v1/chat/completions") !== "user-subscription") {
    fail("subscription url class");
  }

  const hits: Hit[] = [];
  const server = createServer((req: IncomingMessage, res: ServerResponse) => {
    const chunks: Buffer[] = [];
    req.on("data", (chunk) => {
      chunks.push(Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk));
    });
    req.on("end", () => {
      hits.push({
        raw: Buffer.concat(chunks).toString("utf8"),
        authorization: typeof req.headers.authorization === "string" ? req.headers.authorization : undefined,
      });
      const payload = {
        id: "note-route-draft",
        object: "chat.completion",
        model: "should-not-be-recorded",
        choices: [{ index: 0, message: { role: "assistant", content: ASSISTANT }, finish_reason: "stop" }],
      };
      res.writeHead(200, { "content-type": "application/json" });
      res.end(JSON.stringify(payload));
    });
  });

  const port = await new Promise<number>((resolve, reject) => {
    server.once("error", reject);
    server.listen(0, "127.0.0.1", () => {
      const address = server.address();
      if (!address || typeof address === "string") {
        reject(new Error("stub address"));
        return;
      }
      resolve(address.port);
    });
  });
  const endpoint = `http://127.0.0.1:${port}/v1/chat/completions`;
  const cwd = await mkdtemp(join(tmpdir(), "note-route-draft-"));

  const realFetch = globalThis.fetch;
  let fetches = 0;
  globalThis.fetch = async (input: RequestInfo | URL, init?: RequestInit) => {
    const url = input instanceof Request ? input.url : String(input);
    let host = "";
    try {
      host = new URL(url).hostname;
    } catch {
      host = "";
    }
    if (host !== "127.0.0.1") fail("fetch left 127.0.0.1");
    if (url.includes("ai-gateway.vercel.sh") || url.includes("vercel.sh")) fail("gateway fetch");
    fetches += 1;
    return realFetch(input, init);
  };

  try {
    console.log("note-route-draft: gateway key is unset");

    async function held(
      label: string,
      state: Record<string, unknown>,
      evaluation: EvaluateResult,
      model: string,
    ): Promise<void> {
      const before = hits.length;
      const result = await draftNote({
        state,
        evaluation,
        endpoint,
        model,
        cwd,
        file: FILE_NAME,
      });
      if (result.decision !== "hold-for-review") fail(label + " was allowed");
      if (result.drafted || result.file !== null) fail(label + " drafted");
      if (hits.length !== before || fetches !== before) fail(label + " connected");
      if (existsSync(join(cwd, FILE_NAME)) || existsSync(join(cwd, "executed-draft"))) {
        fail(label + " created a file");
      }
      assertRoutedClean(result.routed, label);
      assertClass(result.modelClass, label);
      const dumped = JSON.stringify(result);
      if (dumped.includes(FAKE_TOKEN) || dumped.includes(FAKE_IP)) fail(label + " recorded a secret");
      if (dumped.includes(endpoint) || dumped.includes("gpt-4o") || dumped.includes("api.openai.com")) {
        fail(label + " recorded a model string");
      }
      if (dumped.includes("should-not-be-recorded")) fail(label + " recorded the stub model");
      console.log("note-route-draft: " + label + " did not connect");
    }

    const page = pageState();
    if (route(page, allowEval()) !== "hold-for-review") fail("unfiltered note was allowed");
    const filteredPage = filter(page);
    assertRoutedClean(filteredPage, "filtered page");
    if (route(filteredPage, allowEval()) !== "allow-local-tool") fail("filtered page was held");
    console.log("note-route-draft: fixture token and address are absent from the routed note");

    await held("secret-moving note", secretState(), allowEval(), "gpt-4o");
    await held("pairing code", { text: fixtures.sendPairingCode.text + " " + FAKE_TOKEN }, allowEval(), "local");
    await held("hosts.json", { text: fixtures.copyHosts.text + " " + FAKE_TOKEN }, allowEval(), "local");
    await held("mesh token path", { text: fixtures.readMeshToken.text + " " + FAKE_TOKEN }, allowEval(), "local");
    await held(
      "mesh bearer",
      { text: fixtures.sendMeshBearer.text + " " + FAKE_TOKEN },
      allowEval(),
      "local",
    );
    if (route(filter({ text: fixtures.summarizePaper.text }), allowEval()) !== "allow-local-tool") {
      fail("clean paper was held");
    }
    if (route(filter({ text: fixtures.sendMessage.text }), allowEval()) !== "allow-local-tool") {
      fail("plain send was held");
    }
    console.log("note-route-draft: clean paper would allow a local tool");
    console.log("note-route-draft: plain send would allow a local tool");
    await held("graphical ask", pageState(), allowEval({ surface: "needs-graphical-screen" }), "local");
    await held("wait-for-human", pageState(), allowEval({ surface: "wait-for-human" }), "local");
    await held("high risk", pageState(), allowEval({ score: 0.91 }), "local");
    await held("confidence below 0.6", pageState(), allowEval({ confidence: 0.59 }), "local");
    await held("local model unfit", pageState(), allowEval({ boolean: false }), "local");

    if (hits.length !== 0 || fetches !== 0) fail("a held note connected");
    if ((await readdir(cwd)).length !== 0) fail("a held note created a file");

    const allowed = await draftNote({
      state: pageState(),
      evaluation: allowEval(),
      endpoint,
      model: "local",
      cwd,
      file: FILE_NAME,
    });
    if (allowed.decision !== "allow-local-tool" || !allowed.drafted || allowed.file !== FILE_NAME) {
      fail("allow-local-tool did not draft");
    }
    if (allowed.modelClass !== "local") fail("local draft recorded " + allowed.modelClass);
    if (JSON.stringify(allowed.routed) !== JSON.stringify(filteredPage)) fail("posted object was not filtered");
    assertRoutedClean(allowed.routed, "allowed");
    if (hits.length !== 1 || fetches !== 1) fail("allow-local-tool did not post once");
    const first = JSON.parse(hits[0].raw) as { model?: string; messages?: { content?: string }[] };
    if (first.model !== "local") fail("stub saw model " + String(first.model));
    if (hits[0].authorization) fail("stub saw an authorization header");
    const posted = JSON.parse(String(first.messages?.[0]?.content)) as Record<string, unknown>;
    if (JSON.stringify(posted) !== JSON.stringify(filteredPage)) fail("stub did not receive the filtered note");
    if (JSON.stringify(allowed).includes(endpoint) || JSON.stringify(allowed).includes("should-not-be-recorded")) {
      fail("draft result recorded a model endpoint");
    }
    console.log("note-route-draft: allow-local-tool posted the filtered note");

    const subscriptionModel = "https://api.openai.com/v1/chat/completions";
    const subscription = await draftNote({
      state: pageState(),
      evaluation: allowEval(),
      endpoint,
      model: subscriptionModel,
      cwd,
      file: FILE_NAME,
    });
    if (subscription.modelClass !== "user-subscription") fail("subscription class was not recorded");
    if (hits.length !== 2 || fetches !== 2) fail("subscription class did not stay on loopback");
    const second = JSON.parse(hits[1].raw) as { model?: string };
    if (second.model !== "user-subscription") fail("stub saw model " + String(second.model));
    const subscriptionDump = JSON.stringify(subscription);
    if (subscriptionDump.includes(subscriptionModel) || subscriptionDump.includes("api.openai.com")) {
      fail("subscription url was recorded");
    }
    if (subscriptionDump.includes("should-not-be-recorded")) fail("stub model name was recorded");
    console.log("note-route-draft: model class is local or user-subscription");

    const names = await readdir(cwd);
    if (names.length !== 1 || names[0] !== FILE_NAME) fail("draft wrote " + names.join(","));
    const draftPath = join(cwd, FILE_NAME);
    const info = await stat(draftPath);
    if (!info.isFile() || (info.mode & 0o777) !== 0o600) fail("draft mode is " + (info.mode & 0o777).toString(8));
    const body = readFileSync(draftPath, "utf8");
    if (body !== ASSISTANT) fail("draft file is not the assistant text");
    if (body.includes(FAKE_TOKEN) || body.includes(FAKE_IP)) fail("draft file contains a fixture secret");
    if (existsSync(join(cwd, "executed-draft"))) fail("draft file was executed");
    console.log("note-route-draft: assistant text is one relative file mode 600");
    console.log("note-route-draft: draft file was not executed");
  } finally {
    globalThis.fetch = realFetch;
    await new Promise<void>((resolve, reject) => {
      server.close((err) => (err ? reject(err) : resolve()));
    });
    await rm(cwd, { recursive: true, force: true });
  }
}

main().catch((error: unknown) => {
  const message = error instanceof Error ? error.message : "unknown";
  console.error("FAIL: " + message);
  process.exit(1);
});

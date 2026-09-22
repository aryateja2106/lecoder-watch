import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { filter } from "./filter.ts";
import { route } from "./route.ts";

const here = dirname(fileURLToPath(import.meta.url));
const fixtures = JSON.parse(readFileSync(join(here, "fixtures.json"), "utf8")) as {
  lines: { text: string }[];
  withSecret: Record<string, unknown>;
  notePage: { title: string; text: string };
  uploadToken: { text: string };
  sensitiveKeys: Record<string, unknown>;
};

const FAKE_TOKEN = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
const FAKE_IP = "203.0.113.10";

function fail(message: string): never {
  console.error("FAIL: " + message);
  process.exit(1);
}

function assertRefused(run: () => void, label: string): void {
  try {
    run();
  } catch (error) {
    if (error instanceof Error && error.message.toLowerCase().includes(label)) return;
    fail("unexpected refusal: " + (error instanceof Error ? error.message : "unknown"));
  }
  fail("expected a refusal");
}

const source = structuredClone(fixtures.withSecret);
const before = JSON.stringify(source);
const filtered = filter(source);
if (JSON.stringify(source) !== before) fail("filter mutated its input");

const encoded = JSON.stringify(filtered);
if (encoded.includes(FAKE_TOKEN)) fail("fake token still present after filter");
if (encoded.includes(FAKE_IP)) fail("fake ip still present after filter");
if (encoded.includes("2001:db8")) fail("fake ipv6 still present after filter");
if (encoded.includes("http://") || encoded.includes("https://")) fail("url still present after filter");
if (encoded.includes("kitchen")) fail("hostname value still present after filter");
if (!encoded.includes("tests passed")) fail("benign summary was removed");
for (const key of ["token", "note", "ip", "where", "peer", "hostname", "link"]) {
  if (key in filtered) fail("sensitive or secret value kept under " + key);
}

const rm = fixtures.lines.find((line) => line.text === "about to rm a directory");
const passed = fixtures.lines.find((line) => line.text === "tests passed");
const paper = fixtures.lines.find((line) => line.text === "user asked to read a paper");
if (!rm || !passed || !paper) fail("fixture lines missing");

const rmRoute = route(filter(rm), {
  surface: "terminal-text",
  choice: "allow-local-tool",
  score: 0.91,
  boolean: true,
  confidence: 0.95,
});
if (rmRoute !== "hold-for-review") fail("rm fixture did not hold");

const allow = route(filter(passed), {
  surface: "terminal-text",
  choice: "allow-local-tool",
  score: 0.1,
  boolean: true,
  confidence: 0.95,
});
if (allow !== "allow-local-tool") fail("benign fixture did not allow");

const lowConfidence = route(filter(passed), {
  surface: "terminal-text",
  choice: "allow-local-tool",
  score: 0.1,
  boolean: true,
  confidence: 0.2,
});
if (lowConfidence !== "hold-for-review") fail("low confidence did not hold");

const topRung = route(filter(passed), {
  surface: "terminal-text",
  choice: "allow-local-tool",
  score: 3,
  boolean: true,
  confidence: 0.99,
});
if (topRung !== "hold-for-review") fail("high risk rung did not hold");

const calmPaper = {
  surface: "terminal-text",
  choice: "allow-local-tool",
  score: 0.2,
  boolean: true,
  confidence: 0.9,
};

const paperAllow = route(filter(paper), calmPaper);
if (paperAllow !== "allow-local-tool") fail("paper on terminal text did not allow");

const graphical = route(filter(paper), { ...calmPaper, surface: "needs-graphical-screen" });
if (graphical !== "hold-for-review") fail("graphical screen did not hold");

const waitForHuman = route(filter(paper), { ...calmPaper, surface: "wait-for-human" });
if (waitForHuman !== "hold-for-review") fail("wait-for-human did not hold");

const unfit = route(filter(paper), { ...calmPaper, boolean: false });
if (unfit !== "hold-for-review") fail("local model unfit did not hold");

const missingFit = route(filter(paper), {
  surface: calmPaper.surface,
  choice: calmPaper.choice,
  score: calmPaper.score,
  confidence: calmPaper.confidence,
});
if (missingFit !== "hold-for-review") fail("missing local model fit did not hold");

const nonFinite = route(filter(paper), { ...calmPaper, score: Number.NaN });
if (nonFinite !== "hold-for-review") fail("non-finite risk did not hold");

function paperAnswers(surface: string, fit: number | undefined) {
  return {
    answers: {
      surface: { choice: surface },
      dispatch: {
        choice: "allow-local-tool",
        probabilities: { "allow-local-tool": 0.9 },
      },
      risk: { score: 0.6 },
      localModelFit: fit === undefined ? {} : { probability: fit },
    },
  };
}

const parsedAllow = route(filter(paper), paperAnswers("terminal-text", 0.9));
if (parsedAllow !== "allow-local-tool") fail("parsed terminal-text answers did not allow");

const parsedGraphical = route(filter(paper), paperAnswers("needs-graphical-screen", 0.9));
if (parsedGraphical !== "hold-for-review") fail("parsed graphical answers did not hold");

const parsedUnfit = route(filter(paper), paperAnswers("terminal-text", 0.2));
if (parsedUnfit !== "hold-for-review") fail("parsed unfit answers did not hold");

const parsedMissingFit = route(filter(paper), paperAnswers("terminal-text", undefined));
if (parsedMissingFit !== "hold-for-review") fail("parsed missing fit did not hold");

if (filter(paper).text !== "user asked to read a paper") fail("paper line was altered");

assertRefused(() => {
  filter({ text: "data:image/png;base64,iVBORw0KGgo=" });
}, "image");
assertRefused(() => {
  filter({ blob: Buffer.from([1, 2, 3, 4]) });
}, "buffer");
assertRefused(() => {
  filter({ text: "tests passed. ".repeat(400) });
}, "4 kb");

const note = fixtures.notePage;
if (!note || note.title !== "Sunday bread") fail("note title missing");
if (!note.text.includes("one HTML page") || !note.text.includes("session directory")) {
  fail("note page ask missing");
}
const noteFiltered = filter(note);
if (noteFiltered.title !== note.title || noteFiltered.text !== note.text) fail("note page was altered");

const noteAllow = {
  surface: "terminal-text",
  choice: "allow-local-tool",
  score: 0.2,
  boolean: true,
  confidence: 0.6,
};
if (route(noteFiltered, noteAllow) !== "allow-local-tool") fail("note page did not allow");
if (route(noteFiltered, { ...noteAllow, boolean: false }) !== "hold-for-review") {
  fail("note page with local model unfit did not hold");
}
if (route(noteFiltered, { ...noteAllow, confidence: 0.59 }) !== "hold-for-review") {
  fail("note page with low confidence did not hold");
}
if (route(noteFiltered, { ...noteAllow, surface: "needs-graphical-screen" }) !== "hold-for-review") {
  fail("note page on a graphical screen did not hold");
}
if (route(noteFiltered, { ...noteAllow, score: 0.91 }) !== "hold-for-review") {
  fail("note page with high risk did not hold");
}

const upload = fixtures.uploadToken;
const uploadBefore = JSON.stringify(upload);
if (!uploadBefore.includes(FAKE_TOKEN) || !uploadBefore.includes(FAKE_IP)) {
  fail("upload fixture is missing the synthetic secret");
}
if (!/bearer\s+\S{8,}/i.test(upload.text)) fail("upload fixture is missing a bearer-like string");
const uploadFiltered = filter(structuredClone(upload));
const uploadEncoded = JSON.stringify(uploadFiltered);
if (uploadEncoded.includes(FAKE_TOKEN)) fail("upload token still present after filter");
if (uploadEncoded.includes(FAKE_IP)) fail("upload address still present after filter");
if (!uploadEncoded.toLowerCase().includes("mesh token")) fail("upload ask was removed with the secret");
if (route(upload, noteAllow) !== "hold-for-review") fail("secret upload was allowed");
if (route(uploadFiltered, noteAllow) !== "hold-for-review") fail("filtered secret upload was allowed");

const sensitiveNames = [
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
];
const sensitive = filter(structuredClone(fixtures.sensitiveKeys));
for (const key of sensitiveNames) {
  if (key in sensitive) fail("sensitive key kept: " + key);
}
if (sensitive.summary !== "tests passed") fail("benign field was removed with the sensitive keys");
if (JSON.stringify(sensitive).includes("marker")) fail("sensitive key value leaked");

console.log("jev-routing: filtered secret is absent");
console.log("jev-routing: rm fixture routed to hold-for-review");
console.log("jev-routing: paper on terminal-text routed to allow-local-tool");
console.log("jev-routing: graphical screen routed to hold-for-review");
console.log("jev-routing: wait-for-human routed to hold-for-review");
console.log("jev-routing: local model unfit routed to hold-for-review");
console.log("jev-routing: note page on terminal-text routed to allow-local-tool");
console.log("jev-routing: note page with unfit, low confidence, graphical screen, or high risk held");
console.log("jev-routing: secret upload routed to hold-for-review");
console.log("jev-routing: sensitive keys are absent");

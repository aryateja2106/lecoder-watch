import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { filter } from "./filter.ts";
import { route } from "./route.ts";

const here = dirname(fileURLToPath(import.meta.url));
const fixtures = JSON.parse(readFileSync(join(here, "fixtures.json"), "utf8")) as {
  lines: { text: string }[];
  withSecret: Record<string, unknown>;
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
  choice: "allow-local-tool",
  score: 0.91,
  boolean: true,
  confidence: 0.95,
});
if (rmRoute !== "hold-for-review") fail("rm fixture did not hold");

const allow = route(filter(passed), {
  choice: "allow-local-tool",
  score: 0.1,
  boolean: true,
  confidence: 0.95,
});
if (allow !== "allow-local-tool") fail("benign fixture did not allow");

const lowConfidence = route(filter(passed), {
  choice: "allow-local-tool",
  score: 0.1,
  boolean: true,
  confidence: 0.2,
});
if (lowConfidence !== "hold-for-review") fail("low confidence did not hold");

const topRung = route(filter(passed), {
  choice: "allow-local-tool",
  score: 3,
  boolean: true,
  confidence: 0.99,
});
if (topRung !== "hold-for-review") fail("high risk rung did not hold");

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

console.log("jev-routing: filtered secret is absent");
console.log("jev-routing: rm fixture routed to hold-for-review");

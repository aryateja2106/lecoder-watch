// Making mobile output small enough for a small model to read.
//
// The constraint that decides this file: the local model is text-only and PREFILL-bound.
// Qwen 3.6's own published numbers work out to roughly 110 tokens/second of prefill, so
// a 30KB uiautomator dump is not merely wasteful — it is over a minute of silence before
// the model emits a single token, and it eats half a 16K context. A raw xcodebuild log is
// worse.
//
// So nothing raw is ever handed to the model. A test log becomes a few lines per failure
// naming file, line, test and message; a UI hierarchy becomes a numbered outline of the
// elements you can actually act on. Both are pure functions of text, which means they are
// testable on any machine — no simulator, no device, no Xcode.
//
// These run automatically on command output, because asking a small model to remember to
// compress its own input is not a plan.

export type TestFailure = {
  file: string | null;
  line: number | null;
  suite: string | null;
  test: string | null;
  message: string;
};

export type Digest = {
  kind: "xcodebuild" | "gradle" | "none";
  failures: TestFailure[];
  passed: number | null;
  failed: number | null;
  text: string;
};

// -[SuiteName testName] : message, prefixed by an absolute path and a line number.
const XC_FAILURE = /^(\/[^\s:]+):(\d+):\s+error:\s+-\[([\w.]+)\s+(\w+)\]\s*:\s*(.*)$/;
const XC_COMPILE = /^(\/[^\s:]+):(\d+):(\d+):\s+error:\s+(.*)$/;
const XC_SUMMARY = /Executed\s+(\d+)\s+tests?,\s+with\s+(\d+)\s+failures?/;

// org.example.LoginTest > signInDisabled FAILED
const GRADLE_FAILURE = /^([\w.]+)\s+>\s+([\w$]+)\s+FAILED\s*$/;
const GRADLE_SUMMARY = /(\d+)\s+tests?\s+completed,\s+(\d+)\s+failed/;

export function digestTestLog(raw: string): Digest {
  const lines = raw.split("\n");
  const failures: TestFailure[] = [];
  let kind: Digest["kind"] = "none";
  let passed: number | null = null;
  let failed: number | null = null;

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];

    const xc = XC_FAILURE.exec(line);
    if (xc) {
      kind = "xcodebuild";
      failures.push({
        file: xc[1],
        line: Number(xc[2]),
        suite: xc[3],
        test: xc[4],
        message: xc[5].trim(),
      });
      continue;
    }

    const comp = XC_COMPILE.exec(line);
    if (comp) {
      kind = "xcodebuild";
      failures.push({
        file: comp[1],
        line: Number(comp[2]),
        suite: null,
        test: null,
        message: `compile error: ${comp[4].trim()}`,
      });
      continue;
    }

    const gf = GRADLE_FAILURE.exec(line);
    if (gf) {
      kind = kind === "none" ? "gradle" : kind;
      // The exception and its first stack frame follow the FAILED line, indented. Stop
      // at the first line that is not part of this failure, or the run summary gets
      // glued onto the message.
      let message = "";
      let file: string | null = null;
      let lineNo: number | null = null;
      for (let j = i + 1; j < Math.min(i + 8, lines.length); j++) {
        const raw = lines[j];
        if (!/^\s/.test(raw)) break;
        const t = raw.trim();
        if (!t) continue;
        const frame = /\(([\w$]+\.\w+):(\d+)\)/.exec(t);
        if (frame && file === null) {
          file = frame[1];
          lineNo = Number(frame[2]);
        }
        if (!t.startsWith("at ") && !message) message = t;
      }
      failures.push({ file, line: lineNo, suite: gf[1], test: gf[2], message: message.slice(0, 200) });
      continue;
    }

    const xs = XC_SUMMARY.exec(line);
    if (xs) {
      kind = "xcodebuild";
      failed = Number(xs[2]);
      passed = Number(xs[1]) - failed;
      continue;
    }
    const gs = GRADLE_SUMMARY.exec(line);
    if (gs) {
      kind = kind === "none" ? "gradle" : kind;
      failed = Number(gs[2]);
      passed = Number(gs[1]) - failed;
    }
  }

  if (kind === "none") return { kind, failures: [], passed: null, failed: null, text: "" };

  const head =
    passed !== null && failed !== null
      ? `${failed} failed, ${passed} passed`
      : `${failures.length} failure${failures.length === 1 ? "" : "s"}`;
  const body = failures.slice(0, 20).map((f) => {
    const where = f.file ? `${f.file}:${f.line}` : (f.suite ?? "?");
    const what = f.test ? `${f.suite}.${f.test}` : "";
    return `FAIL ${what}\n  ${where}\n  ${f.message}`;
  });
  const more = failures.length > body.length ? `\n... and ${failures.length - body.length} more failures` : "";
  return { kind, failures, passed, failed, text: `${head}\n\n${body.join("\n\n")}${more}` };
}

export type UiElement = {
  index: number;
  role: string;
  label: string;
  bounds: { x: number; y: number };
  clickable: boolean;
};

/**
 * uiautomator XML -> a numbered outline of the elements worth acting on.
 *
 * The model is given an INDEX, never coordinates: a bare integer is the argument shape
 * Qwen's parser handles most reliably, and the harness owns the index -> pixel mapping so
 * a hallucinated coordinate cannot land a tap somewhere destructive.
 */
export function outlineUiHierarchy(xml: string): { elements: UiElement[]; text: string } {
  const elements: UiElement[] = [];
  const nodeRe = /<node\b([^>]*)\/?>/g;
  let m: RegExpExecArray | null;
  let index = 0;

  const attr = (s: string, name: string): string => {
    const r = new RegExp(`${name}="([^"]*)"`).exec(s);
    return r ? r[1] : "";
  };

  while ((m = nodeRe.exec(xml)) !== null) {
    const a = m[1];
    const text = attr(a, "text").trim();
    const desc = attr(a, "content-desc").trim();
    const resource = attr(a, "resource-id").split("/").pop() ?? "";
    const cls = attr(a, "class").split(".").pop() ?? "node";
    const clickable = attr(a, "clickable") === "true";
    const label = text || desc || resource;

    // An element with no label and no interactivity is layout scaffolding: it costs
    // tokens and tells the model nothing.
    if (!label && !clickable) continue;

    const bounds = /\[(\d+),(\d+)\]\[(\d+),(\d+)\]/.exec(attr(a, "bounds"));
    const centre = bounds
      ? {
          x: Math.round((Number(bounds[1]) + Number(bounds[3])) / 2),
          y: Math.round((Number(bounds[2]) + Number(bounds[4])) / 2),
        }
      : { x: 0, y: 0 };

    index += 1;
    elements.push({ index, role: cls, label: label.slice(0, 60), clickable, bounds: centre });
  }

  // State the numbering base explicitly. The model is given an INDEX and the harness
  // resolves it to a pixel: if the two disagree about whether counting starts at 0 or 1,
  // every tap lands on the wrong element and nothing errors.
  const header = elements.length
    ? `${elements.length} elements, numbered from 1. [tap] marks what you can tap.`
    : "no actionable elements found";
  const text = [
    header,
    ...elements.map(
      (e) => `${String(e.index).padStart(3)}. ${e.clickable ? "[tap] " : "      "}${e.role}: ${e.label}`,
    ),
  ].join("\n");
  return { elements, text };
}

/**
 * Recognise a raw artifact in command output and replace it with its digest.
 * Returns null when the output is not something we can compress, so the caller keeps it.
 */
export function compressIfRecognized(output: string): { text: string; note: string } | null {
  if (output.length < 1500) return null;

  if (output.includes("<hierarchy") && output.includes("<node")) {
    const { elements, text } = outlineUiHierarchy(output);
    if (!elements.length) return null;
    return {
      text,
      note: `UI hierarchy compressed to ${elements.length} actionable elements (${output.length} -> ${text.length} chars)`,
    };
  }

  const digest = digestTestLog(output);
  if (digest.kind !== "none" && (digest.failures.length || digest.failed !== null)) {
    return {
      text: digest.text,
      note: `${digest.kind} log digested (${output.length} -> ${digest.text.length} chars)`,
    };
  }
  return null;
}

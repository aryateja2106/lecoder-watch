// feedback-to-issues.ts — the feedback pipeline: unprocessed public.feedback rows become deduped GitHub issues labeled from-users on LeSearch-AI/mesh, each linked back by issue_url.
//
// Runs on a schedule (launchd on the Mac that owns the fleet — see scripts/feedback-worker.plist)
// or by hand:
//   bun scripts/feedback-to-issues.ts              # file everything new
//   bun scripts/feedback-to-issues.ts --dry-run    # say what would be filed, write nothing
//   bun scripts/feedback-to-issues.ts --fixture f.json   # rows + open issues from a file, no network (the check)
//
// Reads SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY from supabase/.env (gitignored) — the only
// holder of the service key is this worker on this machine. GitHub goes through `gh`, which
// keeps its token in the OS keyring; nothing here ever sees or prints it.
//
// Privacy, in order:
//   1. contact_email never leaves Supabase. The issue carries sha256(lowercased email)[0:12]
//      so two reports from one person can be matched, and nothing else.
//   2. every string that reaches the issue passes the daemon's own redactor (redact.ts), the
//      same families check-feedback-redact pins on the phone — belt and braces.
//   3. an attachment (screenshot / recording, opt-in on the phone) is linked by a signed URL
//      that expires; the bucket itself stays private.
// Dedupe: a new report whose normalized title shares ≥ 60 % of its tokens with an open
// from-users issue (or contains / is contained by it) becomes a comment on that issue, and
// the row is marked duplicate with that issue's URL, so a flood of "app crashes on pair"
// is one issue with a counter, not forty.
//
// ponytail: token-set Jaccard on titles is the whole "fuzzy" — good enough for tens of
// issues; swap for pg_trgm on the server if the queue ever grows past that.
import { createHash } from "node:crypto";
import { readFileSync, existsSync } from "node:fs";
import { dirname, join } from "node:path";
import { redact } from "../install/payload/meshd/redact.ts";

const ROOT = join(dirname(new URL(import.meta.url).pathname), "..");
const REPO = process.env.FEEDBACK_REPO ?? "LeSearch-AI/mesh";
const LABEL = "from-users";
const BATCH = 20;
const SIGNED_URL_SECONDS = 7 * 24 * 3600;
const BODY_MAX = 60_000; // GitHub caps issue bodies at 65 536 chars

type Row = {
  id: string; created_at: string; kind: "bug" | "idea" | "other"; title: string; body: string;
  contact_email: string | null; user_id: string | null; app_version: string; app_build: string;
  device: string; os: string; attachment: string | null; bundle: string | null; source: string;
};
type Issue = { number: number; title: string; url: string };
type Fixture = { rows: Row[]; issues: Issue[] };

const args = process.argv.slice(2);
const DRY = args.includes("--dry-run");
const fixturePath = args[args.indexOf("--fixture") + 1];
const FIXTURE: Fixture | null = args.includes("--fixture") && fixturePath ? JSON.parse(readFileSync(fixturePath, "utf8")) : null;

function loadEnv(): { url: string; key: string } {
  if (FIXTURE) return { url: "fixture", key: "fixture" };
  const file = process.env.FEEDBACK_ENV ?? join(ROOT, "supabase", ".env");
  if (!existsSync(file)) throw new Error(`no ${file} — SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are needed`);
  const env: Record<string, string> = {};
  for (const line of readFileSync(file, "utf8").split("\n")) {
    const m = line.match(/^([A-Z_]+)=(.*)$/);
    if (m) env[m[1]] = m[2].replace(/^"|"$/g, "");
  }
  if (!env.SUPABASE_URL || !env.SUPABASE_SERVICE_ROLE_KEY) throw new Error(`${file} lacks SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY`);
  return { url: env.SUPABASE_URL, key: env.SUPABASE_SERVICE_ROLE_KEY };
}

async function sb(env: { url: string; key: string }, method: string, path: string, body?: unknown, extra: Record<string, string> = {}) {
  const r = await fetch(`${env.url}${path}`, {
    method,
    headers: { apikey: env.key, Authorization: `Bearer ${env.key}`, "Content-Type": "application/json", ...extra },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const text = await r.text();
  if (!r.ok) throw new Error(`${method} ${path} -> ${r.status}: ${text.slice(0, 200)}`);
  return text ? JSON.parse(text) : null;
}

function gh(argv: string[]): string {
  const r = Bun.spawnSync(["gh", ...argv], { stdout: "pipe", stderr: "pipe" });
  if (!r.success) throw new Error(`gh ${argv.slice(0, 3).join(" ")} failed: ${r.stderr.toString().trim().split("\n").pop()}`);
  return r.stdout.toString();
}

// ---------- the pure parts (the check drives these through --fixture) ----------

// The phone's own table (iOS/FeedbackView.swift, pinned by check-feedback-redact) runs
// here too: the daemon's redactor keys on longer, exact token shapes, the phone's on the
// families a person types into a report. Both, so neither's blind spot reaches GitHub.
const PHONE_PATTERNS: Array<[RegExp, string]> = [
  [/sk-[A-Za-z0-9_-]{16,}/g, "[api-key]"],
  [/vck_[A-Za-z0-9]{16,}/g, "[api-key]"],
  [/ghp_[A-Za-z0-9]{20,}/g, "[github-token]"],
  [/xox[abp]-[A-Za-z0-9-]{10,}/g, "[slack-token]"],
  [/AKIA[0-9A-Z]{16}/g, "[aws-key]"],
  [/Bearer\s+[A-Za-z0-9._-]{16,}/g, "Bearer [token]"],
  [/\b[a-f0-9]{64}\b/g, "[hex-token]"],
  [/-----BEGIN [A-Z ]*PRIVATE KEY-----[\s\S]*?-----END [A-Z ]*PRIVATE KEY-----/g, "[private-key]"],
];

export function clean(s: string | null | undefined, max = BODY_MAX): string {
  let out = redact(String(s ?? "")).text;
  for (const [re, label] of PHONE_PATTERNS) out = out.replace(re, label);
  return out.slice(0, max);
}

export function contactHash(email: string | null): string | null {
  const e = (email ?? "").trim().toLowerCase();
  return e ? createHash("sha256").update(e).digest("hex").slice(0, 12) : null;
}

export function tokens(title: string): Set<string> {
  // ponytail: a four-suffix stemmer is the whole morphology (crashes/crash, pairing/pair).
  const stem = (w: string) => (w.length > 4 ? w.replace(/(ing|ed|es|s)$/, "") : w);
  return new Set(
    title.toLowerCase().replace(/^\[[a-z]+\]\s*/, "").replace(/[^a-z0-9 ]+/g, " ").split(/\s+/)
      .filter((w) => w.length > 2 && !STOP.has(w)).map(stem),
  );
}
const STOP = new Set(["the", "and", "for", "with", "when", "this", "that", "not", "but", "app", "from", "into", "after", "before"]);

export function similar(a: string, b: string): boolean {
  const ta = tokens(a), tb = tokens(b);
  if (!ta.size || !tb.size) return false;
  let inter = 0;
  for (const w of ta) if (tb.has(w)) inter++;
  const jaccard = inter / (ta.size + tb.size - inter);
  const contained = inter === Math.min(ta.size, tb.size) && Math.min(ta.size, tb.size) >= 2;
  return jaccard >= 0.6 || contained;
}

export function issueTitle(row: Row): string {
  return `[${row.kind}] ${clean(row.title, 200).trim() || "(untitled report)"}`;
}

export function issueBody(row: Row, attachmentURL: string | null): string {
  const hash = contactHash(row.contact_email);
  const lines = [
    `Filed from the app's **Report a problem** by the feedback worker. Reference \`${row.id}\`.`,
    "",
    "| | |",
    "|---|---|",
    `| Kind | ${row.kind} |`,
    `| App | ${clean(row.app_version, 40)} (${clean(row.app_build, 40)}) |`,
    `| Device | ${clean(row.device, 80)} · ${clean(row.os, 80)} |`,
    `| Reported | ${row.created_at} |`,
    `| Reporter | ${hash ? `contact on file (hash ${hash})` : "anonymous"}${row.user_id ? " · signed in" : ""} |`,
    "",
    "## What happened",
    "",
    clean(row.body, 20_000) || "_(no description)_",
  ];
  if (attachmentURL) lines.push("", `Attachment (link expires in 7 days): ${attachmentURL}`);
  if (row.bundle) {
    lines.push("", "<details><summary>Diagnostic bundle (redacted on the phone, and again here)</summary>", "", "```", clean(row.bundle, 30_000), "```", "", "</details>");
  }
  return lines.join("\n").slice(0, BODY_MAX);
}

export function plan(rows: Row[], open: Issue[]): Array<{ row: Row; duplicateOf: Issue | null }> {
  const seen: Issue[] = [...open];
  return rows.map((row) => {
    const title = issueTitle(row);
    const dup = seen.find((i) => similar(i.title, title)) ?? null;
    if (!dup) seen.push({ number: 0, title, url: "" }); // a later row in this batch can dedupe against this one
    return { row, duplicateOf: dup };
  });
}

// ---------- the effects ----------

async function main() {
  const env = loadEnv();
  const rows: Row[] = FIXTURE ? FIXTURE.rows : await sb(env, "GET", `/rest/v1/feedback?processed_at=is.null&order=created_at.asc&limit=${BATCH}&select=*`);
  if (!rows.length) { console.log("feedback-to-issues: nothing new"); return; }
  const open: Issue[] = FIXTURE ? FIXTURE.issues
    : JSON.parse(gh(["issue", "list", "--repo", REPO, "--label", LABEL, "--state", "open", "--limit", "200", "--json", "number,title,url"]));
  if (!FIXTURE && !DRY) {
    // idempotent: --force updates the colour/description when the label exists
    gh(["label", "create", LABEL, "--repo", REPO, "--color", "0E8A16", "--description", "Filed from in-app feedback", "--force"]);
  }
  const filedInBatch = new Map<string, Issue>();
  for (const { row, duplicateOf } of plan(rows, open)) {
    const title = issueTitle(row);
    let target = duplicateOf;
    if (target && target.number === 0) target = filedInBatch.get(target.title) ?? null; // filed earlier in this run
    let signed: string | null = null;
    if (row.attachment && !FIXTURE && !DRY) {
      try {
        const r = await sb(env, "POST", `/storage/v1/object/sign/feedback-attachments/${row.attachment}`, { expiresIn: SIGNED_URL_SECONDS });
        signed = r?.signedURL ? `${env.url}/storage/v1${r.signedURL}` : null;
      } catch (e: any) { console.log(`  attachment ${row.attachment}: ${e.message}`); }
    }
    const body = issueBody(row, signed);
    if (target) {
      console.log(`duplicate  ${row.id}  ->  #${target.number} ${target.url}`);
      if (!FIXTURE && !DRY) {
        gh(["issue", "comment", String(target.number), "--repo", REPO, "--body",
          `Another report of this (reference \`${row.id}\`, ${clean(row.app_version, 40)} on ${clean(row.device, 80)} · ${clean(row.os, 80)}).\n\n${clean(row.body, 4000)}`]);
        await sb(env, "PATCH", `/rest/v1/feedback?id=eq.${row.id}`, { issue_url: target.url, issue_status: "duplicate", processed_at: new Date().toISOString() }, { Prefer: "return=minimal" });
      }
      continue;
    }
    if (FIXTURE || DRY) {
      console.log(`would file ${row.id}  ${title}`);
      if (FIXTURE) console.log(body.split("\n").map((l) => "    " + l).join("\n"));
      filedInBatch.set(title, { number: -1, title, url: "" });
      continue;
    }
    const labels = [LABEL, row.kind === "bug" ? "bug" : row.kind === "idea" ? "enhancement" : ""].filter(Boolean).join(",");
    const url = gh(["issue", "create", "--repo", REPO, "--title", title, "--body", body, "--label", labels]).trim().split("\n").pop()!;
    const number = Number(url.split("/").pop());
    filedInBatch.set(title, { number, title, url });
    await sb(env, "PATCH", `/rest/v1/feedback?id=eq.${row.id}`, { issue_url: url, issue_status: "filed", processed_at: new Date().toISOString() }, { Prefer: "return=minimal" });
    console.log(`filed      ${row.id}  ->  ${url}`);
  }
}

if (import.meta.main) {
  main().catch((e) => { console.error(`feedback-to-issues: ${e.message}`); process.exit(1); });
}

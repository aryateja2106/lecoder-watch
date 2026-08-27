// codex-state.ts — read why a Codex session stopped, and when its limit resets.
//
// Pure reads. Nothing here starts, resumes or writes to a session; that belongs to
// whatever decides to act on this, and keeping the two apart is deliberate — reading is
// always safe, acting never is.
//
// Everything below was measured against a real stalled session on 2026-08-27
// ("Polish LeSearch.ai landing page", thread 01a04143-…, a 26 MB rollout), not inferred
// from documentation.

import { readFile, stat, readdir } from "node:fs/promises";
import { open } from "node:fs/promises";
import { homedir } from "node:os";
import { join } from "node:path";

const CODEX_HOME = process.env.CODEX_HOME ?? join(homedir(), ".codex");

/** Why a session is not running. */
export type StopReason =
  | "limit"        // stopped because the usage limit was hit — the only resumable one
  | "done"         // finished a turn normally
  | "interrupted"  // a human aborted it
  | "running"      // still working, or nothing conclusive in the tail
  | "unknown";     // the rollout could not be read at all

export type CodexStop = {
  stopped: StopReason;
  /** Unix ms when the limit window resets. Only meaningful when stopped === "limit". */
  resetsAtMs: number | null;
  limitId: string | null;
  usedPercent: number | null;
  /** The human message, for a receipt — never for matching. */
  message: string | null;
};

/**
 * The rollout for a thread.
 *
 * `state_5.sqlite` is the documented index, but it is NOT reliably readable: the desktop
 * app holds it with an active WAL and a `?mode=ro` open intermittently fails outright
 * with "unable to open database file" — observed twice, seconds apart, on a machine where
 * it had just succeeded. So the filesystem is the primary path here and sqlite is not
 * consulted at all: rollouts are named `rollout-<ISO>-<threadId>.jsonl` under
 * `sessions/YYYY/MM/DD/`, which is enough to find one by id without a database.
 */
export async function findRollout(threadId: string): Promise<string | null> {
  const root = join(CODEX_HOME, "sessions");
  // Newest days first: a thread we are asked about is almost always recent, and this
  // avoids walking years of history to find today's file.
  const walk = async (dir: string, depth: number): Promise<string | null> => {
    let entries;
    try { entries = await readdir(dir, { withFileTypes: true }); } catch { return null; }
    const names = entries.map((e) => e.name).sort().reverse();
    for (const name of names) {
      const full = join(dir, name);
      if (depth < 3) {
        const hit = await walk(full, depth + 1);
        if (hit) return hit;
      } else if (name.includes(threadId) && name.endsWith(".jsonl")) {
        return full;
      }
    }
    return null;
  };
  return walk(root, 0);
}

/** How much of the tail to read. Rollouts reach tens of megabytes; never read one whole. */
const TAIL_BYTES = 512 * 1024;

/**
 * Read the end of a rollout and decide why the session stopped.
 *
 * Two things here are load-bearing and both were found the hard way:
 *
 * 1. Match on `codex_error_info`, never on the message. The message embeds a localized
 *    wall-clock time and a marketing URL, both of which change.
 * 2. The reset epoch is NOT on the newest `token_count` line. On the measured incident the
 *    newest carried `limit_id: "premium"` with `primary: null` — the credits pool — while
 *    the usable snapshot (`limit_id: "codex"`, `used_percent: 100`, `window_minutes: 300`,
 *    `resets_at: 1787804714`) was the line before it. A reader that takes the last
 *    token_count gets nulls and silently never arms, which is the worst possible failure
 *    for a feature whose whole job is to fire later.
 */
export async function readStopReason(rolloutPath: string): Promise<CodexStop> {
  const miss: CodexStop = { stopped: "unknown", resetsAtMs: null, limitId: null, usedPercent: null, message: null };

  let lines: string[];
  try {
    const info = await stat(rolloutPath);
    const start = Math.max(0, info.size - TAIL_BYTES);
    const handle = await open(rolloutPath, "r");
    try {
      const buf = Buffer.alloc(Math.min(TAIL_BYTES, info.size));
      await handle.read(buf, 0, buf.length, start);
      // Drop the first line when we seeked into the middle of one.
      const all = buf.toString("utf8").split("\n").filter((l) => l.trim());
      lines = start > 0 ? all.slice(1) : all;
    } finally {
      await handle.close();
    }
  } catch {
    return miss;
  }

  const out: CodexStop = { stopped: "running", resetsAtMs: null, limitId: null, usedPercent: null, message: null };

  for (let i = lines.length - 1; i >= 0; i--) {
    let doc: any;
    try { doc = JSON.parse(lines[i]); } catch { continue; }
    if (doc?.type !== "event_msg") continue;
    const payload = doc.payload ?? {};

    if (out.stopped === "running") {
      if (payload.type === "task_complete") {
        const info = payload.error?.codex_error_info;
        out.stopped = typeof info === "string" && info.startsWith("usage_limit") ? "limit" : "done";
        out.message = typeof payload.error?.message === "string" ? payload.error.message.slice(0, 300) : null;
      } else if (payload.type === "turn_aborted") {
        out.stopped = "interrupted";
      }
    }

    // Keep walking for the newest *usable* limit snapshot even after the stop reason is
    // known — it sits earlier in the file than the line that ended the turn.
    if (out.resetsAtMs === null && payload.type === "token_count") {
      const limits = payload.rate_limits ?? {};
      const primary = limits.primary;
      const resets = primary?.resets_at;
      if (limits.limit_id === "codex" && typeof resets === "number" && resets > 0) {
        out.resetsAtMs = resets * 1000;   // the field is unix SECONDS
        out.limitId = limits.limit_id;
        out.usedPercent = typeof primary?.used_percent === "number" ? primary.used_percent : null;
      }
    }

    if (out.stopped !== "running" && out.resetsAtMs !== null) break;
  }

  return out;
}

/** Everything about one thread, for a caller deciding whether it is resumable. */
export async function readThread(threadId: string): Promise<(CodexStop & { rolloutPath: string }) | null> {
  const rolloutPath = await findRollout(threadId);
  if (!rolloutPath) return null;
  return { ...(await readStopReason(rolloutPath)), rolloutPath };
}

/**
 * Whether this stop is one a resume should ever be armed for.
 *
 * Only a limit stop, and only with a real reset time. "done" means the work finished and
 * typing at it would start something nobody asked for; "interrupted" means a human chose
 * to stop it, which is the loudest possible signal not to restart it on their behalf.
 */
export function isResumable(stop: CodexStop): boolean {
  return stop.stopped === "limit" && typeof stop.resetsAtMs === "number" && stop.resetsAtMs > 0;
}

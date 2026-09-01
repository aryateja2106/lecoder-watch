// Durable run state.
//
// A long-running task must survive the CLI being closed, the machine sleeping, or a
// crash — otherwise "work on long running tasks" means "work until something twitches".
// State is written after every turn, so a killed run resumes from its last completed
// turn rather than from the beginning.
//
// Lives under $MESH_HOME (~/.mesh), matching the rest of the payload, and is written
// 0600 because a transcript contains whatever the agent read.

import { homedir } from "node:os";
import { join } from "node:path";
import { mkdirSync, writeFileSync, readFileSync, existsSync, readdirSync, renameSync } from "node:fs";
import type { Message } from "./model";

export const MESH_HOME = process.env.MESH_HOME || join(homedir(), ".mesh");
export const RUNS_DIR = join(MESH_HOME, "code", "runs");

export type RunStatus = "running" | "finished" | "failed" | "interrupted" | "escalate";

export type CommandRecord = {
  command: string;
  exitCode: number | null;
  ms: number;
  truncated: boolean;
};

export type RunState = {
  id: string;
  task: string;
  cwd: string;
  session: string;
  status: RunStatus;
  turns: number;
  createdISO: string;
  updatedISO: string;
  brain: { model: string; endpoint: string; source: string } | null;
  summary: string | null;
  messages: Message[];
  commands: CommandRecord[];
  tokens: { prompt: number; completion: number; cached: number };
};

export function runPath(id: string): string {
  return join(RUNS_DIR, `${id}.json`);
}

export function newRunId(seed: string): string {
  // No Math.random here: ids stay reproducible and sortable, and a caller supplying a
  // timestamp keeps them unique.
  return seed.replace(/[^a-zA-Z0-9_-]/g, "-").slice(0, 60);
}

export function saveRun(state: RunState): void {
  mkdirSync(RUNS_DIR, { recursive: true, mode: 0o700 });
  const target = runPath(state.id);
  const tmp = `${target}.tmp`;
  // Write-then-rename so a crash mid-write cannot leave a half-parsed run behind.
  writeFileSync(tmp, JSON.stringify(state, null, 2), { encoding: "utf8", mode: 0o600 });
  renameSync(tmp, target);
}

export function loadRun(id: string): RunState | null {
  const p = runPath(id);
  if (!existsSync(p)) return null;
  try {
    return JSON.parse(readFileSync(p, "utf8")) as RunState;
  } catch {
    return null;
  }
}

export function listRuns(): RunState[] {
  if (!existsSync(RUNS_DIR)) return [];
  const out: RunState[] = [];
  for (const f of readdirSync(RUNS_DIR)) {
    if (!f.endsWith(".json")) continue;
    const r = loadRun(f.slice(0, -5));
    if (r) out.push(r);
  }
  return out.sort((a, b) => (a.updatedISO < b.updatedISO ? 1 : -1));
}

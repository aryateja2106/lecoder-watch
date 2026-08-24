// telemetry.ts — one anonymized heartbeat a day, and nothing else, ever.
//
// The entire payload: a random install id (generated once, tied to nothing),
// the daemon version, process.platform, uptime in whole hours, and coarse
// numeric counters (how many hook events landed this week, by level). No
// commands, no keystrokes, no terminal or screen content, no hostnames, no
// paths, no strings derived from user content — counter keys come from a
// fixed whitelist below, values are always numbers. This file and
// web/privacy.html must always agree; change one, change the other.
//
// Opt out with MESHD_TELEMETRY=off (0 and false also count). The daemon works
// identically either way. Failures are silent and cheap: one request, short
// timeout, no retry — a heartbeat is never worth a slow or chatty daemon.
import { homedir } from "node:os";
import { dirname, join } from "node:path";
import { mkdir, readFile, writeFile } from "node:fs/promises";

// The anon key is public by design — it ships in every install, like a Firebase
// app id. Row Level Security on telemetry_events gives the anon role INSERT and
// nothing else: holders of this key can append a heartbeat but can never read,
// change or delete anyone's rows (proven in scripts + the migration comment).
const SUPABASE_URL = "https://zmisjteztezaqfflwbgf.supabase.co";
const SUPABASE_ANON_KEY =
  "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InptaXNqdGV6dGV6YXFmZmx3YmdmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODM3NDQ2MzMsImV4cCI6MjA5OTMyMDYzM30.9I0_eaLYkvISZX6pkrWDeZywBHortnzQoz35omgk_6I";

// Same state home as everything else the daemon persists (~/.mesh), same env
// override pattern as MESHD_EVENTS_PATH so tests never touch the real home.
const STATE_PATH = process.env.MESHD_TELEMETRY_STATE ?? join(homedir(), ".mesh", "telemetry.json");
const EVENTS_PATH = process.env.MESHD_EVENTS_PATH ?? join(homedir(), ".mesh", "agent-events.jsonl");

const DAY_MS = 24 * 60 * 60 * 1000;
const CHECK_MS = 6 * 60 * 60 * 1000; // wake 4x/day; the 24h gate below decides
const SEND_TIMEOUT_MS = 5000;

// mesh-hook emits exactly these levels; anything unexpected is counted as
// "other" rather than letting an arbitrary string become a payload key.
const KNOWN_LEVELS = ["error", "warning", "info"] as const;

function telemetryOff(): boolean {
  const v = (process.env.MESHD_TELEMETRY ?? "").trim().toLowerCase();
  return v === "off" || v === "0" || v === "false";
}

type TelemetryState = { installId: string; lastSentISO?: string };

async function loadState(): Promise<TelemetryState> {
  try {
    const raw = JSON.parse(await readFile(STATE_PATH, "utf8"));
    if (typeof raw?.installId === "string" && raw.installId) {
      return { installId: raw.installId, lastSentISO: typeof raw.lastSentISO === "string" ? raw.lastSentISO : undefined };
    }
  } catch {}
  // Mint the id once and persist it immediately — "generated once" must hold
  // even when the first sends fail, or retries would look like new installs.
  const fresh = { installId: crypto.randomUUID() };
  await saveState(fresh).catch(() => {});
  return fresh;
}

async function saveState(state: TelemetryState): Promise<void> {
  await mkdir(dirname(STATE_PATH), { recursive: true, mode: 0o700 });
  await writeFile(STATE_PATH, `${JSON.stringify(state)}\n`);
}

// Coarse counts only: how many events the hook file gained in the last 7 days,
// split by whitelisted level. Values are numbers; nothing from an event's
// title, body, session or host ever leaves this function.
async function eventCounters(): Promise<Record<string, number>> {
  const out: Record<string, number> = {};
  try {
    const raw = await readFile(EVENTS_PATH, "utf8");
    const cutoff = new Date(Date.now() - 7 * DAY_MS).toISOString();
    let total = 0;
    const byLevel: Record<string, number> = {};
    for (const line of raw.split("\n")) {
      if (!line) continue;
      let e: any;
      try { e = JSON.parse(line); } catch { continue; }
      if (typeof e?.createdISO !== "string" || e.createdISO <= cutoff) continue;
      total++;
      const level = KNOWN_LEVELS.includes(e.level) ? (e.level as string) : "other";
      byLevel[level] = (byLevel[level] ?? 0) + 1;
    }
    out.events_7d = total;
    for (const [level, n] of Object.entries(byLevel)) out[`events_7d_${level}`] = n;
  } catch {} // no events file is the common case on a fresh install; send {}
  return out;
}

async function sendHeartbeat(version: string): Promise<void> {
  const state = await loadState();
  if (state.lastSentISO && Date.now() - Date.parse(state.lastSentISO) < DAY_MS) return;
  const payload = {
    install_id: state.installId,
    platform: process.platform,
    daemon_version: version,
    uptime_hours: Math.round(process.uptime() / 3600),
    counters: await eventCounters(),
  };
  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), SEND_TIMEOUT_MS);
  try {
    const res = await fetch(`${SUPABASE_URL}/rest/v1/telemetry_events`, {
      method: "POST",
      headers: {
        apikey: SUPABASE_ANON_KEY,
        authorization: `Bearer ${SUPABASE_ANON_KEY}`,
        "content-type": "application/json",
        prefer: "return=minimal",
      },
      body: JSON.stringify(payload),
      signal: ctrl.signal,
    });
    // Only a delivered heartbeat advances the clock; a failed one retries at
    // the next 6h check rather than in a loop.
    if (res.ok) {
      state.lastSentISO = new Date().toISOString();
      await saveState(state);
    }
  } catch {} finally {
    clearTimeout(timer);
  }
}

export function initTelemetry(version: string): void {
  if (telemetryOff()) {
    console.log("telemetry: off (MESHD_TELEMETRY)");
    return;
  }
  const tick = () => { sendHeartbeat(version).catch(() => {}); };
  tick();
  const timer = setInterval(tick, CHECK_MS);
  // Never the reason the process stays alive.
  (timer as unknown as { unref?: () => void }).unref?.();
  console.log("telemetry: one anonymized heartbeat/day (version, platform, coarse counters) — MESHD_TELEMETRY=off disables it");
}

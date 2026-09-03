/**
 * Compare mode: the same probes, two endpoints, one verdict per capability.
 *
 * Sequencing is the part that makes the numbers mean something. Our own engine serves
 * one generation at a time and keeps a single cached prefix; LM Studio unloads idle
 * models; the two share one GPU and one SSD. So: probes run one at a time, each probe
 * runs fully on one endpoint and then fully on the other, first-mover alternates per
 * probe, and nothing is ever concurrent. Speed rows come from streamed requests
 * (see core.ts); structure is checked on exactly what was timed.
 *
 * The verdict rule is deliberately dull: more passes wins; then fewer fails — an honest
 * "unsupported" beats a wrong action; then a ≥20% median-speed edge on paired passes;
 * otherwise the literal word "tie". No overall winner: the owner asked which model is
 * better for WHAT, and the per-capability lines plus the failure-mode tags are that.
 */
import { median, type Ctx, type FailureMode, type Probe, type Status, type Turn } from "./core.ts"
import { apiFetch, chat } from "./core.ts"

export type Verdict = "OK" | "PARTIAL" | "PARTIAL/FAILING" | "UNSUPPORTED"

import type { ProbeResult } from "./core.ts"

export interface ProbeRun extends ProbeResult {
  repeats: number
  /** every repeat's status, in order; `status` is their majority */
  statuses: Status[]
  passRate: number
  nondeterministic: boolean
  ttftMs: number | null
  ttfcMs: number | null
  tokPerSec: number | null
  cachedTokens: number | null
  turns: Turn[]
}

export interface RepeatSample {
  status: Status
  failureMode: FailureMode | null
  detail: string
  ms: number
}

/**
 * One status from N repeats. Majority wins; a tie is a fail — a model that passes half
 * the time has not passed. Unsupported outranks fail when it is the majority, because it
 * is a capability boundary, not a wrong action. The speed number is the median of the
 * PASSING repeats only: a failed or timed-out repeat's duration says nothing about how
 * fast a correct answer arrives.
 */
export function aggregateRepeats(samples: RepeatSample[]): { status: Status; failureMode: FailureMode | null; detail: string; ms: number; passRate: number } {
  const n = samples.length
  const by = (st: Status) => samples.filter((x) => x.status === st)
  const passes = by("pass").length
  const unsupported = by("unsupported").length
  let status: Status
  if (passes * 2 > n) status = "pass"
  else if (unsupported * 2 > n) status = "unsupported"
  else if (by("skip").length === n) status = "skip"
  else status = "fail"
  const chosen = by(status)
  // The representative sample: the most common failure mode among failed repeats, else
  // the last repeat with the aggregate status.
  let failureMode: FailureMode | null = null
  if (status === "fail") {
    const modes = new Map<FailureMode, number>()
    for (const x of by("fail")) if (x.failureMode) modes.set(x.failureMode, (modes.get(x.failureMode) ?? 0) + 1)
    failureMode = [...modes.entries()].sort((a, b) => b[1] - a[1])[0]?.[0] ?? "other"
  }
  const rep = [...chosen].reverse().find((x) => status !== "fail" || x.failureMode === failureMode) ?? chosen.at(-1) ?? samples.at(-1)!
  const passing = by("pass").map((x) => x.ms)
  const ms = median(passing.length ? passing : samples.map((x) => x.ms)) ?? rep.ms
  return { status, failureMode, detail: n > 1 ? `${passes}/${n} pass · ${rep.detail}` : rep.detail, ms, passRate: n ? passes / n : 0 }
}

export interface EndpointReport {
  label: string
  endpoint: string
  model: string
  modelsListed: string[]
  warmupMs: number | null
  summary: Record<string, Verdict>
  failureModes: Partial<Record<FailureMode, number>>
  probes: ProbeRun[]
}

export interface CapabilityVerdict {
  capability: string
  a: Verdict
  b: Verdict
  compared: string[]
  notCompared: string[]
  betterFor: "a" | "b" | "tie"
  rule: "more-passes" | "fewer-fails" | "faster-20pct" | "tie"
  reason: string
}

export interface CompareSettings {
  temperature: number
  maxTokens: number
  timeoutMs: number
  repeat: number
  cacheBust: string | null
  only: string[] | null
  warmup: boolean
}

export interface Side {
  ctx: Ctx
  label: string
}

const MARK: Record<Status, string> = { pass: "PASS", fail: "FAIL", unsupported: "N/A ", skip: "SKIP" }
const pad = (s: string, n: number) => (s.length >= n ? s.slice(0, n) : s + " ".repeat(n - s.length))
const fmt = (n: number | null, digits = 0) => (n === null ? "—" : n.toFixed(digits))

export function verdictOf(statuses: Status[]): Verdict {
  if (statuses.length && statuses.every((s) => s === "unsupported")) return "UNSUPPORTED"
  if (statuses.some((s) => s === "fail")) return "PARTIAL/FAILING"
  if (statuses.length && statuses.every((s) => s === "pass")) return "OK"
  return "PARTIAL"
}

async function resolveModel(ctx: Ctx): Promise<string[]> {
  try {
    const { body } = await apiFetch(ctx, "/models")
    const ids: string[] = Array.isArray(body?.data) ? body.data.map((m: any) => String(m?.id ?? "")).filter(Boolean) : []
    if (!ctx.model) ctx.model = ids[0] ?? "local-model"
    return ids
  } catch {
    if (!ctx.model) ctx.model = "local-model"
    return []
  }
}

async function warmUp(ctx: Ctx): Promise<number | null> {
  const t0 = performance.now()
  const saved = { streamPerf: ctx.streamPerf, record: ctx.record }
  ctx.streamPerf = false
  ctx.record = undefined
  try {
    await chat(ctx, { messages: [{ role: "user", content: "ok" }], max_tokens: 8 })
    return Math.round(performance.now() - t0)
  } catch {
    return null
  } finally {
    ctx.streamPerf = saved.streamPerf
    ctx.record = saved.record
    ctx.turnIndex = 0
  }
}

async function runProbeOn(side: Side, probe: Probe, repeats: number): Promise<ProbeRun> {
  const samples: RepeatSample[] = []
  const ttfts: number[] = []
  const ttfcs: number[] = []
  const tps: number[] = []
  const turns: Turn[] = []
  let cached: number | null = null
  let meta: Record<string, unknown> | undefined
  for (let r = 0; r < repeats; r++) {
    const started = performance.now()
    side.ctx.turnIndex = 0
    const mine: Turn[] = []
    side.ctx.record = (t) => mine.push(t)
    let out: Awaited<ReturnType<Probe["run"]>>
    try {
      out = await probe.run(side.ctx)
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err)
      const timeout = /timeout|abort/i.test(msg)
      out = { status: "fail", detail: `threw: ${msg}`, failureMode: timeout ? "timeout" : "other" }
    }
    const wall = performance.now() - started
    // The probe's time is the server's time: the sum of its turns' request→[DONE]
    // windows when every turn was measured, so harness work between turns (and any
    // untimed request) never reaches the speed rule. Wall-clock only when a turn was
    // not streamed (an HTTP error, or the one probe that fetches by hand).
    const perfs = mine.map((t) => t.response.perf)
    const ms = Math.round(mine.length && perfs.every(Boolean) ? perfs.reduce((n, p) => n + p!.totalMs, 0) : wall)
    samples.push({ status: out.status, failureMode: out.failureMode ?? (out.status === "fail" ? "other" : null), detail: out.detail, ms })
    meta = out.meta
    // Perf of the probe's LAST turn — the decision turn — is what the table shows.
    const perfTurn = [...mine].reverse().find((t) => t.response.perf)
    if (perfTurn?.response.perf && out.status === "pass") {
      if (perfTurn.response.perf.ttftMs !== null) ttfts.push(perfTurn.response.perf.ttftMs)
      if (perfTurn.response.perf.ttfcMs !== null) ttfcs.push(perfTurn.response.perf.ttfcMs)
      if (perfTurn.response.perf.genTokPerSec !== null) tps.push(perfTurn.response.perf.genTokPerSec)
    }
    if (perfTurn?.response.perf?.cachedTokens !== null && perfTurn?.response.perf?.cachedTokens !== undefined) cached = perfTurn.response.perf.cachedTokens
    turns.push(...mine.map((t) => ({ ...t, index: r * 100 + t.index })))
  }
  side.ctx.record = undefined
  const agg = aggregateRepeats(samples)
  return {
    id: probe.id,
    title: probe.title,
    capability: probe.capability,
    useCase: probe.useCase,
    status: agg.status,
    detail: agg.detail,
    failureMode: agg.failureMode,
    ms: agg.ms,
    meta,
    repeats,
    statuses: samples.map((x) => x.status),
    passRate: agg.passRate,
    nondeterministic: new Set(samples.map((x) => x.status)).size > 1,
    ttftMs: median(ttfts),
    ttfcMs: median(ttfcs),
    tokPerSec: median(tps),
    cachedTokens: cached,
    turns,
  }
}

function countModes(probes: ProbeRun[]): Partial<Record<FailureMode, number>> {
  const out: Partial<Record<FailureMode, number>> = {}
  for (const p of probes) if (p.failureMode) out[p.failureMode] = (out[p.failureMode] ?? 0) + 1
  return out
}

function summarize(probes: ProbeRun[]): Record<string, Verdict> {
  const caps = new Map<string, Status[]>()
  for (const p of probes) {
    if (!caps.has(p.capability)) caps.set(p.capability, [])
    caps.get(p.capability)!.push(p.status)
  }
  const out: Record<string, Verdict> = {}
  for (const [c, s] of caps) out[c] = verdictOf(s)
  return out
}

// Not the model's doing: a dead endpoint, a timeout, or a reply the harness's own
// max_tokens cut off. These are listed under "not compared", never counted as fails.
const excluded = (p: ProbeRun) =>
  p.status === "skip" || p.failureMode === "http-error" || p.failureMode === "timeout" || p.failureMode === "truncated"

export function decideCapability(capability: string, a: ProbeRun[], b: ProbeRun[]): CapabilityVerdict {
  const byId = (xs: ProbeRun[]) => new Map(xs.map((p) => [p.id, p]))
  const am = byId(a.filter((p) => p.capability === capability))
  const bm = byId(b.filter((p) => p.capability === capability))
  const ids = [...new Set([...am.keys(), ...bm.keys()])]
  const compared: string[] = []
  const notCompared: string[] = []
  for (const id of ids) {
    const x = am.get(id), y = bm.get(id)
    if (x && y && !excluded(x) && !excluded(y)) compared.push(id)
    else notCompared.push(id)
  }
  const count = (m: Map<string, ProbeRun>, s: Status) => compared.filter((id) => m.get(id)!.status === s).length
  const aPass = count(am, "pass"), bPass = count(bm, "pass")
  const aFail = count(am, "fail"), bFail = count(bm, "fail")
  const av = verdictOf([...am.values()].map((p) => p.status))
  const bv = verdictOf([...bm.values()].map((p) => p.status))
  const tally = `A ${aPass} pass/${aFail} fail, B ${bPass} pass/${bFail} fail`
  const base = { capability, a: av, b: bv, compared, notCompared }
  if (!compared.length) return { ...base, betterFor: "tie", rule: "tie", reason: "nothing ran on both endpoints" }
  if (aPass !== bPass) return { ...base, betterFor: aPass > bPass ? "a" : "b", rule: "more-passes", reason: tally }
  if (aFail !== bFail) return { ...base, betterFor: aFail < bFail ? "a" : "b", rule: "fewer-fails", reason: `${tally} — unsupported beats a wrong action` }
  const paired = compared.filter((id) => am.get(id)!.status === "pass" && bm.get(id)!.status === "pass")
  const ma = median(paired.map((id) => am.get(id)!.ms))
  const mb = median(paired.map((id) => bm.get(id)!.ms))
  if (ma !== null && mb !== null && ma > 0 && mb > 0) {
    const ratio = Math.max(ma, mb) / Math.min(ma, mb)
    if (ratio >= 1.2) return { ...base, betterFor: ma < mb ? "a" : "b", rule: "faster-20pct", reason: `${tally}, median ${Math.round(ma)}ms vs ${Math.round(mb)}ms` }
    return { ...base, betterFor: "tie", rule: "tie", reason: `${tally}, median ${Math.round(ma)}ms vs ${Math.round(mb)}ms (within 20%)` }
  }
  return { ...base, betterFor: "tie", rule: "tie", reason: tally }
}

export interface CompareFile {
  schemaVersion: 1
  recordedAt: string
  host: { platform: string; arch: string; note: string }
  settings: CompareSettings
  a: EndpointReport
  b: EndpointReport
  table: Array<{ id: string; capability: string; a: RowSide; b: RowSide }>
  verdicts: CapabilityVerdict[]
  unsupportedOnAPassingOnB: string[]
}
type RowSide = { status: Status; ms: number; tokPerSec: number | null; ttftMs: number | null; ttfcMs: number | null; cachedTokens: number | null; failureMode: FailureMode | null; passRate: number }

export async function runCompare(a: Side, b: Side, probes: Probe[], settings: CompareSettings, out: { json?: string; jsonl?: string; strict?: boolean }) {
  const sides = [a, b]
  for (const s of sides) {
    s.ctx.streamPerf = true
    const ids = await resolveModel(s.ctx)
    if (!s.label) s.label = `${s.ctx.model}@${new URL(s.ctx.endpoint).port || "80"}`
    ;(s as any).modelsListed = ids
  }
  console.log(`\nbrain-eval compare\n  A: ${a.label}  ${a.ctx.endpoint}\n  B: ${b.label}  ${b.ctx.endpoint}\n  temperature=${settings.temperature} max_tokens=${settings.maxTokens} repeat=${settings.repeat}${settings.cacheBust ? " cache-bust" : ""}\n`)

  const warm: Record<string, number | null> = {}
  if (settings.warmup) for (const s of sides) warm[s.label] = await warmUp(s.ctx)

  const runsA: ProbeRun[] = []
  const runsB: ProbeRun[] = []
  console.log(`  ${pad("probe", 34)} ${pad(`A ${a.label}`.slice(0, 30), 34)} ${pad(`B ${b.label}`.slice(0, 30), 34)}`)
  for (let i = 0; i < probes.length; i++) {
    const probe = probes[i]
    // Alternate first-mover so ordering and thermal state do not favour one side.
    const order = i % 2 === 0 ? [a, b] : [b, a]
    const got: Record<string, ProbeRun> = {}
    for (const s of order) got[s.label] = await runProbeOn(s, probe, settings.repeat)
    const ra = got[a.label], rb = got[b.label]
    runsA.push(ra)
    runsB.push(rb)
    const cell = (r: ProbeRun) =>
      `${MARK[r.status]}${r.repeats > 1 ? ` ${Math.round(r.passRate * 100)}%` : ""} ${pad(`${r.ms}ms`, 8)} ${pad(fmt(r.tokPerSec, 1) + " t/s", 10)}${r.failureMode ? ` ${r.failureMode}` : ""}`
    console.log(`  ${pad(probe.title, 34)} ${pad(cell(ra), 34)} ${pad(cell(rb), 34)}`)
  }

  const A: EndpointReport = { label: a.label, endpoint: a.ctx.endpoint, model: a.ctx.model, modelsListed: (a as any).modelsListed ?? [], warmupMs: warm[a.label] ?? null, summary: summarize(runsA), failureModes: countModes(runsA), probes: runsA }
  const B: EndpointReport = { label: b.label, endpoint: b.ctx.endpoint, model: b.ctx.model, modelsListed: (b as any).modelsListed ?? [], warmupMs: warm[b.label] ?? null, summary: summarize(runsB), failureModes: countModes(runsB), probes: runsB }

  const capabilities = [...new Set(probes.map((p) => p.capability))]
  const verdicts = capabilities.filter((c) => c !== "reachability").map((c) => decideCapability(c, runsA, runsB))
  const boundary = runsA.filter((p) => p.status === "unsupported" && runsB.find((q) => q.id === p.id)?.status === "pass").map((p) => p.id)

  console.log("\n  capability            A                 B")
  for (const c of capabilities) console.log(`    ${pad(c, 22)} ${pad(A.summary[c] ?? "-", 17)} ${B.summary[c] ?? "-"}`)
  console.log("")
  for (const v of verdicts) {
    const who = v.betterFor === "tie" ? "tie" : v.betterFor === "a" ? A.label : B.label
    console.log(`  better for ${pad(v.capability + ":", 24)} ${who}  (${v.rule}: ${v.reason})`)
  }
  console.log(`\n  unsupported on A, passing on B: ${boundary.length ? boundary.join(", ") : "none"}`)
  const modes = (m: Partial<Record<FailureMode, number>>) => Object.entries(m).map(([k, v]) => `${k} x${v}`).join(", ") || "none"
  console.log(`  failure modes — A: ${modes(A.failureModes)}\n                  B: ${modes(B.failureModes)}\n`)

  const table = runsA.map((ra, i) => {
    const rb = runsB[i]
    const side = (r: ProbeRun): RowSide => ({ status: r.status, ms: r.ms, tokPerSec: r.tokPerSec, ttftMs: r.ttftMs, ttfcMs: r.ttfcMs, cachedTokens: r.cachedTokens, failureMode: r.failureMode, passRate: r.passRate })
    return { id: ra.id, capability: ra.capability, a: side(ra), b: side(rb) }
  })
  const file: CompareFile = {
    schemaVersion: 1,
    recordedAt: new Date().toISOString(),
    host: { platform: process.platform, arch: process.arch, note: "server RSS is not visible to the harness; read it from Activity Monitor or ps and type it here" },
    settings,
    a: A,
    b: B,
    table,
    verdicts,
    unsupportedOnAPassingOnB: boundary,
  }
  if (out.json) {
    await Bun.write(out.json, JSON.stringify(file, null, 2) + "\n")
    console.log(`  wrote ${out.json}`)
  }
  if (out.jsonl) {
    const rows: string[] = []
    for (const [tag, rep] of [["a", A], ["b", B]] as const) {
      for (const p of rep.probes) {
        for (const t of p.turns) {
          const req = t.request.body as any
          rows.push(JSON.stringify({
            endpoint: tag, label: rep.label, model: rep.model, probe: p.id, capability: p.capability, useCase: p.useCase,
            turn: t.index % 100, repeat: Math.floor(t.index / 100),
            messages: req.messages ?? null, tools: req.tools ?? null,
            assistant: (t.response.body as any)?.choices?.[0]?.message ?? null,
            httpStatus: t.response.httpStatus, status: p.status, failureMode: p.failureMode, perf: t.response.perf,
          }))
        }
      }
    }
    await Bun.write(out.jsonl, rows.join("\n") + "\n")
    console.log(`  wrote ${out.jsonl} (${rows.length} rows)`)
  }
  const failed = runsA.filter((r) => r.status === "fail").length + runsB.filter((r) => r.status === "fail").length
  if (out.strict && failed > 0) process.exit(1)
  return file
}

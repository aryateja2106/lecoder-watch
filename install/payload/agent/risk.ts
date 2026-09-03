// Which commands the agent may run without asking.
//
// AGENTS.md design principle 4 is explicit: "Review before dispatch. Nothing reaches a
// shell until the user confirms." An autonomous coding agent that asks before every
// command cannot do the long-running work this product exists for, so the line is drawn
// where the apps already draw it: SAFE commands run unattended, DESTRUCTIVE ones need a
// human.
//
// The rules below are a deliberate MIRROR of Shared/RiskClassifier.swift, so the CLI, the
// phone and the watch agree about what "destructive" means. scripts/check-agent-risk-parity.sh
// fails if the two ever drift. Do not add a rule here without adding it there.
//
// The Swift file's own reasoning applies unchanged, and is worth repeating: the rule is
// narrow ON PURPOSE. Flagging everything trains the eye to skip the warning, at which
// point the warning is worse than nothing.

export type Risk = "safe" | "destructive";

export type Verdict = {
  risk: Risk;
  /** the actual verb, because a generic word assumes the reader finished the sentence */
  verb: string;
  /** one line saying what happens; only set when destructive */
  consequence: string | null;
};

export const SAFE: Verdict = { risk: "safe", verb: "Continue", consequence: null };

/**
 * Ordered; first match wins, so the more specific entry comes before the more general
 * one (`sudo rm -rf` should read as a delete, not as "run as root").
 * Needles are matched against a lowercased, whitespace-collapsed copy of the text.
 */
export const DESTRUCTIVE_RULES: Array<{ needles: string[]; verb: string; why: string }> = [
  { needles: ["push --force", "push -f", "force-with-lease", "force push"], verb: "Force push", why: "Rewrites history on the remote." },
  { needles: ["reset --hard"], verb: "Hard reset", why: "Throws away uncommitted work." },
  { needles: ["rm -rf", "rm -fr", "rm -r -f"], verb: "Delete files", why: "Removes files permanently. There is no undo." },
  { needles: ["clean -fd", "clean -fdx", "clean -xdf"], verb: "Clean tree", why: "Deletes untracked files." },
  { needles: ["drop table", "drop database", "truncate table"], verb: "Drop data", why: "Destroys data in the database." },
  { needles: ["| sh", "|sh", "| bash", "|bash"], verb: "Run script", why: "Runs a script fetched over the network." },
  { needles: ["kill -9", "pkill -9"], verb: "Force kill", why: "Kills the process without letting it clean up." },
  { needles: ["--no-verify"], verb: "Skip checks", why: "Bypasses your commit hooks." },
  { needles: ["sudo "], verb: "Run as root", why: "Runs with root privileges." },
];

/**
 * Shipping actions, gated separately from DESTRUCTIVE_RULES.
 *
 * These are deliberately NOT mirrored into Shared/RiskClassifier.swift, and the reason is
 * a domain difference rather than an oversight: the Swift classifier judges "the line an
 * agent is blocked on" -- a prompt a human is about to answer on a watch -- while this
 * judges "a command about to run". Tapping Continue on a wrist cannot submit a build to
 * the App Store; the agent's shell can. The user's goal says ship "securely to
 * production", and an unattended model is not who decides that.
 */
export const SHIP_RULES: Array<{ needles: string[]; verb: string; why: string }> = [
  { needles: ["notarytool submit", "altool --upload", "xcrun altool"], verb: "Submit to Apple", why: "Uploads a build to Apple." },
  { needles: ["fastlane deliver", "fastlane pilot", "fastlane release"], verb: "Release build", why: "Publishes a build to users." },
  { needles: ["bundle exec fastlane deliver"], verb: "Release build", why: "Publishes a build to users." },
  { needles: ["npm publish", "yarn publish", "pnpm publish"], verb: "Publish package", why: "Publishes to a public registry." },
  { needles: ["gcloud app deploy", "vercel --prod", "netlify deploy --prod", "eas submit"], verb: "Deploy to production", why: "Changes what real users are running." },
  { needles: ["gh release create"], verb: "Cut a release", why: "Publishes a release publicly." },
];

export function classifyRisk(text: string): Verdict {
  const hay = text
    .toLowerCase()
    .split(/\s+/)
    .filter((s) => s.length > 0)
    .join(" ");
  if (!hay) return SAFE;
  for (const rule of [...DESTRUCTIVE_RULES, ...SHIP_RULES]) {
    if (rule.needles.some((n) => hay.includes(n))) {
      return { risk: "destructive", verb: rule.verb, consequence: rule.why };
    }
  }
  return SAFE;
}

export type ApprovalMode =
  /** default: safe commands run, destructive ones are refused with a corrective result */
  | "ask"
  /** everything runs unattended — an explicit opt-in for trusted long-running work */
  | "auto"
  /** destructive commands are always refused */
  | "never";

export type Decision = { allow: boolean; verdict: Verdict; explanation: string };

/**
 * `ask` refuses rather than blocking on stdin: a run started from the phone, or left
 * going overnight, has nobody at the keyboard, and a prompt nobody answers is a hang.
 * The refusal is a corrective tool result, so the model can choose a safer route instead
 * of the run simply dying.
 */
export function decideCommand(command: string, mode: ApprovalMode): Decision {
  const verdict = classifyRisk(command);
  if (verdict.risk === "safe") return { allow: true, verdict, explanation: "" };
  if (mode === "auto") {
    return { allow: true, verdict, explanation: `${verdict.verb.toLowerCase()} allowed by --approve auto` };
  }
  return {
    allow: false,
    verdict,
    explanation:
      `refused: this would ${verdict.verb.toLowerCase()}. ${verdict.consequence} ` +
      `The user has not approved destructive commands for this run. ` +
      `Do it a safer way, or call finish and explain what you need permission for.`,
  };
}

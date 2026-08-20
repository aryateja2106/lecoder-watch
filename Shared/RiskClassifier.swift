import Foundation

/// How much damage a one-tap answer could do.
///
/// This exists because of what "Continue" actually sends: a bare Return (see
/// `AgentNotification.command(for:typed:)`). Return accepts whichever option the agent
/// has *highlighted*, which for most prompts is the affirmative. So the wrist button
/// is not "acknowledge" — it is "yes", pressed by someone who may be walking and who
/// read at most two lines. For `rm -rf` or a force push that is not a button anyone
/// should offer without saying what it does.
///
/// The rule is narrow on purpose. Flagging everything trains the eye to skip the
/// warning, at which point the warning is worse than nothing.
enum AgentRisk: String, Codable, Hashable {
    case safe
    case destructive
}

/// The classification plus the words the UI should use for it. Bundled together so a
/// caller cannot show a red button with a generic label, or a verb with a calm tint.
struct RiskVerdict: Codable, Hashable {
    var risk: AgentRisk
    /// The affirmative button's label. "Continue" when safe; the actual verb when not,
    /// because a generic word assumes the reader finished the sentence above it.
    var verb: String
    /// One line saying what happens, shown only when destructive.
    var consequence: String?

    static let safe = RiskVerdict(risk: .safe, verb: "Continue", consequence: nil)
    var isDestructive: Bool { risk == .destructive }
}

/// Ordered; first match wins, so the more specific entry has to come before the more
/// general one (`sudo rm -rf` should read as a delete, not as "run as root").
///
/// Needles are matched against a lowercased, whitespace-collapsed copy of the text.
private let destructiveRules: [(needles: [String], verb: String, why: String)] = [
    (["push --force", "push -f", "force-with-lease", "force push"],
     "Force push", "Rewrites history on the remote."),
    (["reset --hard"],
     "Hard reset", "Throws away uncommitted work."),
    (["rm -rf", "rm -fr", "rm -r -f"],
     "Delete files", "Removes files permanently. There is no undo."),
    (["clean -fd", "clean -fdx", "clean -xdf"],
     "Clean tree", "Deletes untracked files."),
    (["drop table", "drop database", "truncate table"],
     "Drop data", "Destroys data in the database."),
    (["| sh", "|sh", "| bash", "|bash"],
     "Run script", "Runs a script fetched over the network."),
    (["kill -9", "pkill -9"],
     "Force kill", "Kills the process without letting it clean up."),
    (["--no-verify"],
     "Skip checks", "Bypasses your commit hooks."),
    (["sudo "],
     "Run as root", "Runs with root privileges."),
]

/// Classify the line an agent is blocked on.
///
/// Only the question text is examined — never the session or machine name. A session
/// called `deploy-api` is not a destructive command, and treating it as one would
/// paint half the fleet red.
func classifyRisk(_ text: String) -> RiskVerdict {
    let hay = text.lowercased()
        .components(separatedBy: .whitespacesAndNewlines)
        .filter { !$0.isEmpty }
        .joined(separator: " ")
    guard !hay.isEmpty else { return .safe }

    for rule in destructiveRules where rule.needles.contains(where: { hay.contains($0) }) {
        return RiskVerdict(risk: .destructive, verb: rule.verb, consequence: rule.why)
    }
    return .safe
}

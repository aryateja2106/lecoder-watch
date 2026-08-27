import Foundation

// DaemonCapabilities — what this app asks of meshd, and what a user loses when the
// daemon on their machine is older than the app on their wrist.
//
// This file exists because the failure it names is *silent*. A daemon that predates a
// capability does not refuse the call — it serves the old answer with HTTP 200. Ask a
// 0.4.1 daemon for a cropped region and it returns the whole display, no `x-mesh-rect`
// header, 200 OK; the watch then renders an entire Mac screen into 368 pixels and the
// person wearing it concludes the app cannot show readable text. Measured on a real
// fleet: the region a user was trying to read arrived as 125x53 pixels where the
// current daemon serves 786x334 for the identical rectangle. The app was right, the
// bytes were fine, the daemon was stale — and nothing anywhere said so.
//
// Two rules follow, and both are load-bearing:
//
//  1. Gate on capabilities, never on a version string. A hand-built daemon, a fork, or
//     a machine mid-upgrade all carry versions that no comparison can order correctly,
//     and `/health` already lists exactly what the thing can do.
//  2. When a capability is missing, name the *symptom*, not the capability. "screenRegion
//     unsupported" sends nobody anywhere. "Zooming can't sharpen text" is the sentence
//     that was already forming in the user's head.

/// One capability this app depends on, and the shape of its absence.
struct DaemonGap: Equatable, Hashable {
    /// The exact string meshd advertises in `/health` → `capabilities`.
    let capability: String
    /// What the user calls the thing that stopped working.
    let feature: String
    /// What they see instead. Phrased as the symptom, because the symptom is what
    /// sends someone to file a bug against the app rather than update the daemon.
    let symptom: String
}

enum DaemonCapabilities {
    /// The one command that closes every gap below. It reinstalls in place and
    /// preserves the existing token and config, so a machine stays paired across an
    /// upgrade — that is what makes it safe to put in front of a user verbatim.
    ///
    /// `--upgrade` is a real flag of the shipped installer, not a hopeful one; see
    /// install/install.sh, and check-daemon-gaps.sh proves the two still agree.
    static let upgradeCommand =
        "curl -fsSL https://github.com/LeSearch-AI/mesh-install/releases/latest/download/install.sh | sh -s -- --upgrade"

    /// Every capability this build actually calls, with the consequence of its absence.
    ///
    /// Adding a row here is a promise that the app really gates something on it — an
    /// entry for a capability nobody uses nags forever about a feature that was never
    /// missed. check-daemon-gaps.sh holds both ends of that promise: every capability
    /// named here must appear in meshd's own CAPABILITIES array, and must be referenced
    /// somewhere in the Swift that claims to need it.
    static let expected: [DaemonGap] = [
        DaemonGap(capability: "screenRegion",
                  feature: "Sharp screen text",
                  symptom: "Zooming re-sends the same shrunken frame, so text never gets clearer."),
        DaemonGap(capability: "power",
                  feature: "Restart and shut down",
                  symptom: "Only sleep is offered; restarting a machine needs its own keyboard."),
        DaemonGap(capability: "paste",
                  feature: "Paste into the machine",
                  symptom: "Text has to be typed a keystroke at a time instead of pasted."),
        DaemonGap(capability: "openUrl",
                  feature: "Open a link on the machine",
                  symptom: "A link found on the wrist can't be handed to the machine's browser."),
        DaemonGap(capability: "laPush",
                  feature: "Live Activity updates",
                  symptom: "The Lock Screen card stops moving while an agent is still working."),
        DaemonGap(capability: "sessionStatus",
                  feature: "Accurate session state",
                  symptom: "A session's badge can lag behind what the agent is really doing."),
        DaemonGap(capability: "captureJoin",
                  feature: "Faster screen capture",
                  symptom: "Overlapping screen requests each pay full price, so frames arrive slower."),
    ]

    /// The gaps for a machine, given what its daemon advertised.
    ///
    /// `nil` means "we have not heard from it yet" and yields nothing. That distinction
    /// matters: `MeshClient.supports` reads nil as "assume old", which is the right
    /// conservative answer when deciding whether to *send* a request, and the wrong one
    /// for deciding whether to *accuse* a machine of being out of date. A row that
    /// flashes "7 features off" at every machine during the first poll teaches users to
    /// ignore the warning by the time it is true.
    static func gaps(in capabilities: [String]?) -> [DaemonGap] {
        guard let capabilities else { return [] }
        let have = Set(capabilities)
        return expected.filter { !have.contains($0.capability) }
    }

    /// A single line for a list row, or nil when there is nothing to say. Kept here so
    /// the watch and the phone cannot drift into describing the same state differently.
    static func headline(gapCount: Int) -> String? {
        switch gapCount {
        case 0: return nil
        case 1: return "1 feature is off — this machine's agent is out of date"
        default: return "\(gapCount) features are off — this machine's agent is out of date"
        }
    }
}

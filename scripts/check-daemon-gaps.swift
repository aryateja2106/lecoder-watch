// check-daemon-gaps — the capability-gap logic behind the "your agent is out of date"
// row. Compiled with -Onone by check-all.sh, because `assert` is a no-op under -O.
//
// The fleet numbers below are not invented: they are the two capability lists observed
// on 2026-08-27, one from the daemon actually running on the author's Mac and one from
// the daemon sitting in this repo. Keeping them literal is the point — if a future
// change makes a 0.4.1 daemon look up to date, this fails.

import Foundation

@main
struct CheckDaemonGaps {
    static func main() {

        // Exactly what meshd 0.4.1 advertises. Seven of the app's capabilities are absent.
        let v041 = ["events", "newPane", "paneTarget", "usage", "agents", "cmux", "tailscale",
                    "kb", "screenPeek", "input", "files", "push", "pair", "doctor", "wake"]

        // Exactly what the meshd in this repo advertises.
        let v050 = v041 + ["screenRegion", "openUrl", "power", "laPush", "sessionStatus",
                           "paste", "captureJoin"]

        // A current daemon owes the user no warning at all.
        assert(DaemonCapabilities.gaps(in: v050).isEmpty,
               "the current daemon must produce zero gaps, got \(DaemonCapabilities.gaps(in: v050).map(\.capability))")

        // The stale one owes them seven, and screenRegion — the blurry-text one — must be
        // among them, because that is the complaint this whole row exists to answer.
        let stale = DaemonCapabilities.gaps(in: v041)
        assert(stale.count == DaemonCapabilities.expected.count,
               "a 0.4.1 daemon should be missing every expected capability, got \(stale.count)")
        assert(stale.contains { $0.capability == "screenRegion" },
               "screenRegion must be reported missing on 0.4.1 — it is the reason text is unreadable")

        // Never heard from is not the same as out of date. A machine mid-first-poll must not
        // be accused of anything; a user who sees "7 features off" on a healthy machine learns
        // to ignore the warning before it is ever true.
        assert(DaemonCapabilities.gaps(in: nil).isEmpty,
               "an unpolled machine must produce no gaps")

        // An empty list is a real answer from a real daemon, unlike nil, so it does count.
        assert(DaemonCapabilities.gaps(in: []).count == DaemonCapabilities.expected.count,
               "a daemon advertising nothing is missing everything")

        // Only the missing ones. A gap list that included capabilities the daemon has would
        // send someone upgrading to fix a feature that already works.
        let partial = v041 + ["screenRegion", "paste"]
        let partialGaps = Set(DaemonCapabilities.gaps(in: partial).map(\.capability))
        assert(!partialGaps.contains("screenRegion") && !partialGaps.contains("paste"),
               "capabilities the daemon has must never be reported as gaps")
        assert(partialGaps.contains("power"),
               "capabilities the daemon lacks must still be reported")

        // No duplicate rows: two entries for one capability would double every count shown.
        let names = DaemonCapabilities.expected.map(\.capability)
        assert(Set(names).count == names.count, "expected[] must not repeat a capability")

        // Every row has to be able to say something to a human. A blank feature or symptom
        // renders as an empty line in the list, which reads as a rendering bug.
        for gap in DaemonCapabilities.expected {
            assert(!gap.feature.isEmpty, "\(gap.capability) has no feature name")
            assert(!gap.symptom.isEmpty, "\(gap.capability) has no symptom")
            assert(gap.symptom.count > 20, "\(gap.capability)'s symptom is too terse to help")
        }

        // The headline counts what it was handed, and stays silent at zero.
        assert(DaemonCapabilities.headline(gapCount: 0) == nil, "a healthy machine gets no headline")
        assert(DaemonCapabilities.headline(gapCount: 1)?.contains("1 feature is") == true,
               "one gap must read as singular")
        assert(DaemonCapabilities.headline(gapCount: 7)?.contains("7 features are") == true,
               "many gaps must read as plural")

        // The command is the whole point of the row — a warning with no fix is just nagging.
        assert(DaemonCapabilities.upgradeCommand.contains("--upgrade"),
               "the offered command must actually upgrade")
        assert(DaemonCapabilities.upgradeCommand.contains("mesh-install"),
               "the offered command must point at the installer that publishes releases")

        print("check-daemon-gaps: ok")
    }
}

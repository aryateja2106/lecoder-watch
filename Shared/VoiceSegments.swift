// VoiceSegments — pure accumulation for streaming speech recognition.
//
// SFSpeechRecognizer ends its task on a silence gap, on `isFinal`, or at the on-device
// ~60s ceiling. VoiceTranscriber restarts a fresh request each time that happens, so
// whatever the finishing task recognized must be folded into a running total instead of
// being overwritten by the next task's first partial — that overwrite was the bug: pause,
// and everything said before the pause vanished. This type owns none of that machinery,
// just the join logic, kept separate so it can be proven right without a microphone (see
// scripts/check-voice-accumulate.sh).
import Foundation

public struct VoiceSegments: Equatable {
    public private(set) var committed: String

    public init(committed: String = "") {
        self.committed = committed
    }

    /// One task has finished: fold its final text into the accumulated segments.
    /// Whitespace-only text (a task that ended without recognizing anything) is a no-op.
    public mutating func append(final: String) {
        let trimmed = final.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        committed = committed.isEmpty ? trimmed : "\(committed) \(trimmed)"
    }

    /// What to display right now: every committed segment plus the in-flight partial
    /// from whichever task is currently listening.
    public func compose(partial: String) -> String {
        let trimmedPartial = partial.trimmingCharacters(in: .whitespacesAndNewlines)
        if committed.isEmpty { return trimmedPartial }
        if trimmedPartial.isEmpty { return committed }
        return "\(committed) \(trimmedPartial)"
    }
}

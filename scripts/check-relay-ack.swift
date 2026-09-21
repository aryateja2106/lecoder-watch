import Foundation

// The watch → phone relay used to say "delivered" for every command the phone accepted,
// including the ones the daemon refused or the phone could not route (review ARCH-02).
// Fire-and-forget commands now answer RelayReply.encodeFailure(...) and the watch decodes
// it with RelayReply.failureReason(in:). Both halves are pure; this pins them so the two
// apps cannot drift apart again the way the clipboard prefix once did.
@main
struct CheckRelayAck {
    static func main() throws {
        // 1. Round-trip: encodeFailure → failureReason recovers the reason.
        let failure = RelayReply.encodeFailure("dead session")
        precondition(failure != nil, "encodeFailure must produce data")
        precondition(RelayReply.failureReason(in: failure) == "dead session",
                     "expected 'dead session', got \(RelayReply.failureReason(in: failure) ?? "nil")")

        // 2. A plain JSON-encoded string with no error prefix → nil (a real clipboard read).
        let plain = try JSONEncoder().encode("hello")
        precondition(RelayReply.failureReason(in: plain) == nil, "plain string must not read as a failure")

        // 3. nil data → nil (a fire-and-forget success).
        precondition(RelayReply.failureReason(in: nil) == nil, "nil data must return nil")

        // 4. A JSON-encoded structured payload (a snapshot, a listing) → nil.
        let structured = try JSONEncoder().encode(["a", "b"])
        precondition(RelayReply.failureReason(in: structured) == nil, "array payload must not read as a failure")

        // 5. Whitespace after the prefix is trimmed; an empty reason is not a failure line.
        let padded = try JSONEncoder().encode(RelayReply.errorPrefix + "   iPhone did not answer  ")
        precondition(RelayReply.failureReason(in: padded) == "iPhone did not answer", "reason must be trimmed")
        let empty = try JSONEncoder().encode(RelayReply.errorPrefix)
        precondition(RelayReply.failureReason(in: empty) == nil, "bare prefix carries no reason")

        // 6. The prefix constant is the documented value both apps compile against.
        precondition(RelayReply.errorPrefix == "mesh-error:", "errorPrefix changed — both halves must agree")

        print("check-relay-ack: OK")
    }
}

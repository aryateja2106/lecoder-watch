// TerminalKeyRouter.swift — turns the bytes a terminal emulator emits for keystrokes into meshd's `/send` vocabulary (text runs, named keys, ctrl-/alt- letters).
//
// Pure Foundation so scripts/check-native-terminal-keys.sh can compile it alone. Used by
// the phone's native terminal while it drives a pane over `/send`; the streaming pty
// route sends raw bytes and does not need it.
import Foundation

enum TerminalKeyRouter {
    enum Step: Equatable { case text(String), key(String), unsupported(String) }

    private static let escapes: [String: String] = [
        "[A": "up", "[B": "down", "[C": "right", "[D": "left",
        "[H": "home", "[F": "end", "[1~": "home", "[4~": "end",
        "[5~": "page-up", "[6~": "page-down", "[3~": "delete", "[Z": "shift-tab", "\r": "shift-enter",
    ]

    /// Streaming transport: fold an armed Ctrl/Alt into the first letter of the bytes and
    /// pass everything else through untouched. Ctrl-c is 0x03; Alt-b is ESC b.
    static func applyModifiers(_ bytes: [UInt8], ctrl: Bool, alt: Bool) -> [UInt8] {
        guard ctrl || alt, let i = bytes.firstIndex(where: { (0x61...0x7a).contains($0) || (0x41...0x5a).contains($0) }) else { return bytes }
        var out = bytes
        let lower = bytes[i] | 0x20
        if ctrl { out[i] = lower & 0x1f }
        else { out.replaceSubrange(i...i, with: [0x1b, lower]) }
        return out
    }

    /// Sticky Ctrl/Alt from the key bar apply to the first letter typed and no further.
    static func route(_ bytes: [UInt8], ctrl: Bool = false, alt: Bool = false) -> [Step] {
        var steps: [Step] = []
        var text: [UInt8] = []
        var i = 0
        var ctrl = ctrl, alt = alt
        func flush() {
            if !text.isEmpty { steps.append(.text(String(decoding: text, as: UTF8.self))); text.removeAll() }
        }
        while i < bytes.count {
            let b = bytes[i]
            if b == 0x1b {
                // Longest known suffix wins; a lone ESC is the Escape key.
                var matched = false
                for len in stride(from: 3, through: 1, by: -1) where i + len < bytes.count {
                    let suffix = String(decoding: bytes[(i + 1)...(i + len)], as: UTF8.self)
                    if let key = escapes[suffix] { flush(); steps.append(.key(key)); i += len + 1; matched = true; break }
                }
                if matched { continue }
                if i + 1 < bytes.count, (0x61...0x7a).contains(bytes[i + 1]) {
                    flush(); steps.append(.key("alt-\(Character(UnicodeScalar(bytes[i + 1])))")); i += 2; continue
                }
                flush(); steps.append(.key("escape")); i += 1; continue
            }
            switch b {
            case 0x0d: flush(); steps.append(.key("enter"))
            case 0x09: flush(); steps.append(.key("tab"))
            case 0x7f, 0x08: flush(); steps.append(.key("backspace"))
            case 0x01...0x1a:
                flush(); steps.append(.key("ctrl-\(Character(UnicodeScalar(b + 0x60)))"))
            case 0x00...0x1f: flush(); steps.append(.unsupported("Control byte \(b)"))
            default:
                let letter = (0x61...0x7a).contains(b) || (0x41...0x5a).contains(b)
                if (ctrl || alt) && letter {
                    flush()
                    let lower = Character(UnicodeScalar(b | 0x20))
                    steps.append(.key("\(ctrl ? "ctrl" : "alt")-\(lower)"))
                    ctrl = false; alt = false
                } else {
                    text.append(b)
                }
            }
            i += 1
        }
        flush()
        return steps
    }
}

// native-terminal-keys-test.swift — TerminalKeyRouter turns emulator bytes into the keys meshd accepts; run by check-native-terminal-keys.sh.
import Foundation

@main struct NativeTerminalKeysTest {
    static func main() {
        typealias S = TerminalKeyRouter.Step
        func expect(_ got: [S], _ want: [S], _ what: String) {
            if got != want { print("FAIL: \(what): got \(got), want \(want)"); exit(1) }
        }
        expect(TerminalKeyRouter.route(Array("ls -la".utf8)), [.text("ls -la")], "plain text is one run")
        expect(TerminalKeyRouter.route(Array("ls\r".utf8)), [.text("ls"), .key("enter")], "CR is Enter after the text")
        expect(TerminalKeyRouter.route([0x1b]), [.key("escape")], "lone ESC is Escape")
        expect(TerminalKeyRouter.route([0x1b, 0x5b, 0x41]), [.key("up")], "CSI A is Up")
        expect(TerminalKeyRouter.route([0x1b, 0x5b, 0x35, 0x7e]), [.key("page-up")], "CSI 5~ is Page Up")
        expect(TerminalKeyRouter.route([0x1b, 0x5b, 0x5a]), [.key("shift-tab")], "CSI Z is Shift-Tab")
        expect(TerminalKeyRouter.route([0x1b, 0x0d]), [.key("shift-enter")], "ESC CR is meta-Enter (newline without submit)")
        expect(TerminalKeyRouter.route([0x03]), [.key("ctrl-c")], "0x03 is ctrl-c")
        expect(TerminalKeyRouter.route([0x7f]), [.key("backspace")], "DEL is Backspace")
        expect(TerminalKeyRouter.route([0x09]), [.key("tab")], "HT is Tab")
        expect(TerminalKeyRouter.route([0x1b, 0x62]), [.key("alt-b")], "ESC b is alt-b (option as meta)")
        expect(TerminalKeyRouter.route(Array("c".utf8), ctrl: true), [.key("ctrl-c")], "armed Ctrl + c is ctrl-c")
        expect(TerminalKeyRouter.route(Array("cd".utf8), ctrl: true), [.key("ctrl-c"), .text("d")], "sticky Ctrl applies to one letter only")
        expect(TerminalKeyRouter.route(Array("X".utf8), alt: true), [.key("alt-x")], "armed Alt lowercases the letter")
        expect(TerminalKeyRouter.route(Array("1".utf8), ctrl: true), [.text("1")], "Ctrl on a digit is just the digit")
        expect(TerminalKeyRouter.route([0x1c]), [.unsupported("Control byte 28")], "unknown control bytes are named, not dropped silently")
        expect(TerminalKeyRouter.route(Array("héllo\r".utf8)), [.text("héllo"), .key("enter")], "UTF-8 survives the byte walk")
        func expectBytes(_ got: [UInt8], _ want: [UInt8], _ what: String) {
            if got != want { print("FAIL: \(what): got \(got), want \(want)"); exit(1) }
        }
        expectBytes(TerminalKeyRouter.applyModifiers(Array("c".utf8), ctrl: true, alt: false), [0x03], "stream: Ctrl + c is 0x03")
        expectBytes(TerminalKeyRouter.applyModifiers(Array("C".utf8), ctrl: true, alt: false), [0x03], "stream: Ctrl + C is 0x03 too")
        expectBytes(TerminalKeyRouter.applyModifiers(Array("b".utf8), ctrl: false, alt: true), [0x1b, 0x62], "stream: Alt + b is ESC b")
        expectBytes(TerminalKeyRouter.applyModifiers(Array("ls".utf8), ctrl: false, alt: false), Array("ls".utf8), "stream: nothing armed passes through")
        expectBytes(TerminalKeyRouter.applyModifiers([0x0d], ctrl: true, alt: false), [0x0d], "stream: Ctrl with no letter leaves the bytes alone")
        print("native-terminal-keys-test: ok (22 cases)")
    }
}

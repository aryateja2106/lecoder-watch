// mesh-input — macOS input injection for meshd. Reads NDJSON commands on stdin and
// posts real HID events through Quartz Event Services (the only way a remote client
// can drive this Mac's cursor/keyboard; a watch app cannot inject input itself).
//
//   mesh-input                    stream mode — one JSON object per line on stdin
//   mesh-input --check            print {"trusted":…}; exit 0 when Accessibility is granted
//   mesh-input --check --prompt   same, but ask macOS to show the Accessibility dialog
//
// Events (t = type):
//   {"t":"move","dx":3,"dy":-2}            relative cursor move (drag when button held)
//   {"t":"moveTo","x":0.5,"y":0.25}        absolute, normalized to the main display
//   {"t":"click","button":"left","count":2}
//   {"t":"down"} / {"t":"up"}              hold/release left button (drag lock)
//   {"t":"scroll","dx":0,"dy":-40}         pixel scroll
//   {"t":"key","key":"c","mods":["cmd"]}
//   {"t":"text","s":"hello"}               arbitrary Unicode, no keycode needed
//   {"t":"media","key":"playpause"}        media / brightness / backlight keys
//
// Without Accessibility permission for THIS binary, macOS silently drops every event.
// ponytail: one long-lived process reading stdin, so a drag streams at gesture rate
// instead of paying a process launch per event. If it ever needs to report per-event
// results, add a reply line on stdout and a reader in meshd.

import Foundation
import CoreGraphics
import ApplicationServices
import AppKit

let flags = Set(CommandLine.arguments.dropFirst())

// MARK: - Permission check mode

if flags.contains("--check") {
    let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
    let trusted = AXIsProcessTrustedWithOptions([promptKey: flags.contains("--prompt")] as CFDictionary)
    let path = (CommandLine.arguments.first ?? "mesh-input")
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
    print("{\"trusted\":\(trusted),\"path\":\"\(path)\"}")
    exit(trusted ? 0 : 1)
}

// MARK: - Event synthesis

let source = CGEventSource(stateID: .hidSystemState)
var leftIsDown = false

/// Virtual keycodes for the keys a wrist-sized key bar actually needs.
let KEYCODES: [String: CGKeyCode] = [
    "return": 36, "enter": 36, "tab": 48, "space": 49, "delete": 51, "backspace": 51,
    "escape": 53, "esc": 53, "forwarddelete": 117, "home": 115, "end": 119,
    "pageup": 116, "pagedown": 121, "left": 123, "right": 124, "down": 125, "up": 126,
    "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
    "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17,
    "o": 31, "u": 32, "i": 34, "p": 35, "l": 37, "j": 38, "k": 40, "n": 45, "m": 46,
    "1": 18, "2": 19, "3": 20, "4": 21, "5": 23, "6": 22, "7": 26, "8": 28, "9": 25, "0": 29,
    "-": 27, "=": 24, "[": 33, "]": 30, ";": 41, "'": 39, ",": 43, ".": 47, "/": 44,
    "\\": 42, "`": 50, "grave": 50,
    "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97,
    "f7": 98, "f8": 100, "f9": 101, "f10": 109, "f11": 103, "f12": 111,
]

/// Modifiers need both a flag (so the app sees ⌘) and a real key event (so things
/// like ⌘Tab, which watch the key being *held*, actually work).
let MODIFIERS: [String: (key: CGKeyCode, flag: CGEventFlags)] = [
    "cmd": (55, .maskCommand), "command": (55, .maskCommand), "meta": (55, .maskCommand),
    "shift": (56, .maskShift),
    "opt": (58, .maskAlternate), "option": (58, .maskAlternate), "alt": (58, .maskAlternate),
    "ctrl": (59, .maskControl), "control": (59, .maskControl),
    "fn": (63, .maskSecondaryFn),
]

func post(_ event: CGEvent?) {
    event?.post(tap: .cghidEventTap)
    usleep(1200)   // events posted back-to-back are occasionally dropped by the WindowServer
}

func cursor() -> CGPoint { CGEvent(source: nil)?.location ?? .zero }

func moveCursor(to point: CGPoint) {
    let type: CGEventType = leftIsDown ? .leftMouseDragged : .mouseMoved
    let from = cursor()
    let event = CGEvent(mouseEventSource: source, mouseType: type,
                        mouseCursorPosition: point, mouseButton: .left)
    // Some apps (editors, games, canvases) read raw deltas rather than positions.
    event?.setDoubleValueField(.mouseEventDeltaX, value: point.x - from.x)
    event?.setDoubleValueField(.mouseEventDeltaY, value: point.y - from.y)
    post(event)
}

func mouseButton(_ name: String?) -> CGMouseButton {
    switch (name ?? "left").lowercased() {
    case "right": return .right
    case "middle", "center", "other": return .center
    default: return .left
    }
}

func click(_ button: CGMouseButton, count: Int) {
    let point = cursor()
    let (downType, upType): (CGEventType, CGEventType)
    switch button {
    case .right: (downType, upType) = (.rightMouseDown, .rightMouseUp)
    case .center: (downType, upType) = (.otherMouseDown, .otherMouseUp)
    default: (downType, upType) = (.leftMouseDown, .leftMouseUp)
    }
    for n in 1...max(1, min(count, 3)) {
        for type in [downType, upType] {
            let event = CGEvent(mouseEventSource: source, mouseType: type,
                                mouseCursorPosition: point, mouseButton: button)
            event?.setIntegerValueField(.mouseEventClickState, value: Int64(n))
            post(event)
        }
    }
}

/// Hold/release the left button so a following `move` becomes a drag.
func hold(_ down: Bool) {
    let point = cursor()
    leftIsDown = down
    post(CGEvent(mouseEventSource: source,
                 mouseType: down ? .leftMouseDown : .leftMouseUp,
                 mouseCursorPosition: point, mouseButton: .left))
}

func scroll(dx: Int32, dy: Int32) {
    post(CGEvent(scrollWheelEvent2Source: source, units: .pixel,
                 wheelCount: 2, wheel1: dy, wheel2: dx, wheel3: 0))
}

func pressKey(_ name: String, mods: [String]) {
    guard let code = KEYCODES[name.lowercased()] else { return }
    let held = mods.compactMap { MODIFIERS[$0.lowercased()] }
    let allFlags = held.reduce(CGEventFlags()) { $0.union($1.flag) }

    var accumulated = CGEventFlags()
    for mod in held {
        accumulated.formUnion(mod.flag)
        let event = CGEvent(keyboardEventSource: source, virtualKey: mod.key, keyDown: true)
        event?.flags = accumulated
        post(event)
    }
    for isDown in [true, false] {
        let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: isDown)
        event?.flags = allFlags
        post(event)
    }
    for mod in held.reversed() {
        accumulated.subtract(mod.flag)
        let event = CGEvent(keyboardEventSource: source, virtualKey: mod.key, keyDown: false)
        event?.flags = accumulated
        post(event)
    }
}

/// Media, brightness and backlight live on the NX system-defined channel, not the
/// keyboard one — there is no virtual keycode for them. Subtype 8 with the key in the
/// high half of data1 is how the hardware Fn row reports itself.
let MEDIA_KEYS: [String: Int32] = [
    "volumeup": 0, "volumedown": 1,
    "brightnessup": 2, "brightnessdown": 3,
    "mute": 7,
    "playpause": 16, "play": 16, "pause": 16,
    "next": 17, "previous": 18, "prev": 18,
    "fastforward": 19, "rewind": 20,
    "keyboardbrightnessup": 21, "keyboardbrightnessdown": 22,
]

func pressMedia(_ name: String) {
    guard let code = MEDIA_KEYS[name.lowercased()] else { return }
    for isDown in [true, false] {
        let state: Int32 = isDown ? 0xA : 0xB
        let event = NSEvent.otherEvent(with: .systemDefined,
                                       location: .zero,
                                       modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(state) << 8),
                                       timestamp: 0,
                                       windowNumber: 0,
                                       context: nil,
                                       subtype: 8,
                                       data1: Int((code << 16) | (state << 8)),
                                       data2: -1)
        post(event?.cgEvent)
    }
}

/// Type arbitrary text without mapping it to keycodes — handles any layout and emoji.
func typeText(_ text: String) {
    let units = Array(text.utf16)
    guard !units.isEmpty else { return }
    for start in stride(from: 0, to: units.count, by: 16) {
        var chunk = Array(units[start..<min(start + 16, units.count)])
        for isDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: isDown)
            event?.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: &chunk)
            post(event)
        }
    }
}

// MARK: - Dispatch

func number(_ object: [String: Any], _ key: String, _ fallback: Double = 0) -> Double {
    (object[key] as? NSNumber)?.doubleValue ?? fallback
}

func clamp01(_ value: Double) -> Double { min(max(value, 0), 1) }

func apply(_ command: [String: Any]) {
    switch (command["t"] as? String ?? "").lowercased() {
    case "move":
        let from = cursor()
        moveCursor(to: CGPoint(x: from.x + number(command, "dx"), y: from.y + number(command, "dy")))
    case "moveto":
        // ponytail: normalized to the MAIN display only — same display `screencapture`
        // gives the watch, so tap-on-preview lands where you tapped. Extend to the
        // full arrangement (CGGetActiveDisplayList) if a second screen ever matters.
        let bounds = CGDisplayBounds(CGMainDisplayID())
        moveCursor(to: CGPoint(x: bounds.minX + bounds.width * clamp01(number(command, "x")),
                               y: bounds.minY + bounds.height * clamp01(number(command, "y"))))
    case "click":
        click(mouseButton(command["button"] as? String), count: Int(number(command, "count", 1)))
    case "down": hold(true)
    case "up": hold(false)
    case "scroll":
        scroll(dx: Int32(number(command, "dx").rounded()), dy: Int32(number(command, "dy").rounded()))
    case "key":
        pressKey(command["key"] as? String ?? "", mods: command["mods"] as? [String] ?? [])
    case "text":
        typeText(command["s"] as? String ?? "")
    case "media":
        pressMedia(command["key"] as? String ?? "")
    default:
        break
    }
}

while let line = readLine(strippingNewline: true) {
    guard !line.isEmpty,
          let data = line.data(using: .utf8),
          let command = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    else { continue }
    apply(command)
}

// stdin closed (meshd exited) — release anything we were holding.
if leftIsDown { hold(false) }

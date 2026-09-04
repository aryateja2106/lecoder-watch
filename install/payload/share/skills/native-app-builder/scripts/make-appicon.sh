#!/bin/sh
# make-appicon.sh — an app icon in one command, so no generated app ships iconless.
#
#   sh make-appicon.sh <path/to/Assets.xcassets> <sf-symbol-name> <hex-color> [<hex-color-2>]
#
# Renders the SF Symbol in white on a vertical gradient of the two colors (one color → a
# flat fill) into a 1024×1024 PNG and writes an AppIcon.appiconset with the single
# universal entry iOS 17+ accepts. Needs only macOS (Swift + AppKit), no dependencies.
set -eu
[ $# -ge 3 ] || { echo "usage: make-appicon.sh <Assets.xcassets> <sf-symbol> <hex> [<hex2>]" >&2; exit 2; }
ASSETS="$1"; SYMBOL="$2"; C1="$3"; C2="${4:-$3}"
SET="$ASSETS/AppIcon.appiconset"
mkdir -p "$SET"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
cat >"$TMP/icon.swift" <<'EOF'
import AppKit
let args = CommandLine.arguments
let out = args[1], symbol = args[2]
func color(_ hex: String) -> NSColor {
    var h = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")); if h.count == 3 { h = h.map { "\($0)\($0)" }.joined() }
    let v = UInt32(h, radix: 16) ?? 0x3366FF
    return NSColor(calibratedRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: 1)
}
let size = NSSize(width: 1024, height: 1024)
let image = NSImage(size: size)
image.lockFocus()
NSGradient(starting: color(args[3]), ending: color(args[4]))!.draw(in: NSRect(origin: .zero, size: size), angle: -90)
let config = NSImage.SymbolConfiguration(pointSize: 560, weight: .semibold)
if let glyph = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(config) {
    let tinted = NSImage(size: glyph.size); tinted.lockFocus()
    glyph.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1)
    NSColor.white.set(); NSRect(origin: .zero, size: glyph.size).fill(using: .sourceAtop)
    tinted.unlockFocus()
    let r = NSRect(x: (1024 - tinted.size.width) / 2, y: (1024 - tinted.size.height) / 2, width: tinted.size.width, height: tinted.size.height)
    tinted.draw(in: r)
} else {
    FileHandle.standardError.write("unknown SF Symbol \(symbol); drawing a plain tile\n".data(using: .utf8)!)
}
image.unlockFocus()
guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
try! png.write(to: URL(fileURLWithPath: out))
EOF
swiftc -O -o "$TMP/icon" "$TMP/icon.swift" 2>/dev/null || swiftc -o "$TMP/icon" "$TMP/icon.swift"
"$TMP/icon" "$SET/AppIcon.png" "$SYMBOL" "$C1" "$C2"
# AppKit renders at the display's backing scale (2048px on a Retina Mac); Xcode wants exactly 1024.
sips -z 1024 1024 "$SET/AppIcon.png" >/dev/null
cat >"$SET/Contents.json" <<'EOF'
{
  "images" : [
    { "filename" : "AppIcon.png", "idiom" : "universal", "platform" : "ios", "size" : "1024x1024" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
EOF
echo "ok $SET/AppIcon.png"

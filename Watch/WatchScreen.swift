import WatchKit

/// Screen-class helpers for watch layout. Width in points is the stable signal:
/// 40–41mm watches report ~162–176pt; 45mm+ report ~198pt and up.
enum WatchScreen {
    /// True on 40–41mm-class watches (and smaller). 45mm+ keeps the full chrome.
    static var isCompact: Bool {
        WKInterfaceDevice.current().screenBounds.width < compactWidthCutoff
    }

    /// 45mm Series 7+ width is 198pt; stay just under so 44mm (184pt) is compact too.
    static let compactWidthCutoff: CGFloat = 190

    /// Tiny provider glyph for dense rows — Claude/Codex only.
    static func providerMark(for agentType: String) -> (symbol: String, label: String)? {
        switch agentType.lowercased() {
        case "claude": return ("sparkles", "Claude")
        case "codex": return ("curlybraces", "Codex")
        default: return nil
        }
    }
}

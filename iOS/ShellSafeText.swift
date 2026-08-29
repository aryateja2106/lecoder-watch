import SwiftUI

/// Undo iOS smart punctuation on text that is going to reach a shell.
///
/// Every field here already calls `.autocorrectionDisabled()`, which says nothing about
/// smart punctuation: iOS still rewrites `--flag` into `–flag` and `"x"` into curly
/// quotes on the way to bash, the command fails, and nothing on screen explains why.
///
/// This used to be six `UITextField.appearance()` / `UITextView.appearance()` calls in
/// `MeshRelayApp.init()`. That crashed the app. Setting *any* `UITextInputTraits`
/// property through the `UITextField` appearance proxy throws when UIKit replays the
/// stored invocation onto a field entering a window — measured on iOS 26.5 and 27.0
/// alike, and for `smartQuotesType`, `smartDashesType`, `smartInsertDeleteType` and
/// plain `autocorrectionType` equally — so every sheet containing a `TextField` died on
/// presentation. The `UITextView` half was harmless, but a global proxy that has to be
/// remembered is what let one line take out every screen, so both are gone.
///
/// Normalising the bound value is the supported equivalent and it is local: a field that
/// does not opt in is unaffected, and there is no launch-time global left to break.
extension String {
    /// The exact inverse of the substitutions iOS makes while typing.
    var shellSafePunctuation: String {
        var out = self
        for (smart, plain) in [
            ("\u{201C}", "\""), ("\u{201D}", "\""),   // “ ”
            ("\u{2018}", "'"),  ("\u{2019}", "'"),    // ‘ ’
            ("\u{2013}", "--"), ("\u{2014}", "---"),  // – — (iOS makes these from -- and ---)
            ("\u{2026}", "..."),                      // …
        ] {
            out = out.replacingOccurrences(of: smart, with: plain)
        }
        return out
    }
}

extension Binding where Value == String {
    /// Use on any field whose text becomes a command, host, path or URL.
    var shellSafe: Binding<String> {
        Binding(get: { wrappedValue },
                set: { newValue in
                    let cleaned = newValue.shellSafePunctuation
                    // Only write back on a real change: an unconditional assignment on
                    // every keystroke fights SwiftUI's own text buffer and drops
                    // characters mid-word.
                    if cleaned != wrappedValue { wrappedValue = cleaned }
                })
    }
}

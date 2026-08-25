import Foundation

/// Finding the link an agent just printed, so the wrist can push it to the Mac.
///
/// This is the wrist's answer to the one thing it genuinely cannot do: an agent
/// finishes and prints a preview URL, a CI link, a PR — and the screen it printed it on
/// is 40mm wide with no browser worth the name. "Open on Mac" turns that dead-end into
/// one tap, using meshd 0.5.0's `/open`.
///
/// Deliberately narrow. Terminals wrap lines, paint colour codes and leave sentence
/// punctuation glued to the end of a URL, so anything clever here would eventually open
/// the wrong page on somebody's Mac — which is worse than showing no button. So: the
/// first whitespace-delimited run that starts with http:// or https://, trailing
/// punctuation trimmed, and it must parse to a URL with a host. Everything else is
/// declined.
func firstLink(in text: String) -> URL? {
    for token in text.split(whereSeparator: { $0.isWhitespace }) {
        var candidate = String(token)
        let lower = candidate.lowercased()
        guard lower.hasPrefix("http://") || lower.hasPrefix("https://") else { continue }
        // "…see https://example.com/x)." — the bracket and the stop belong to the
        // sentence, not the address.
        while let last = candidate.last, ")]}>,.;:'\"`".contains(last) { candidate.removeLast() }
        // A bare scheme is not a link.
        guard candidate.lowercased() != "http://", candidate.lowercased() != "https://" else { continue }
        guard let url = URL(string: candidate), let host = url.host, !host.isEmpty else { continue }
        return url
    }
    return nil
}

/// The link worth offering out of a block of terminal output, newest first.
///
/// Agents print the URL at the end of a run, so the tail is where it lives; scanning
/// from the bottom also means a fresh link beats one from twenty minutes ago that has
/// scrolled up but not off.
func lastLink(in lines: [String]) -> URL? {
    for line in lines.reversed() {
        if let url = firstLink(in: line) { return url }
    }
    return nil
}

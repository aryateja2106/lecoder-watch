// FileViewer.swift — read a file off a machine on the phone: Markdown rendered, HTML shown, code and text with a pinch to size — because most of watching an agent work is reading what it wrote.
//
// One screen for the three shapes an agent leaves behind. Markdown is what agents
// write most (reports, READMEs, plans), so it renders as text a person can read on a
// phone rather than as raw symbols; HTML is what they build, shown in a WKWebView with
// scripts allowed but no network identity of ours (a bare string load, no cookies,
// no bearer); everything else is monospaced text that scrolls both ways and never
// wraps. Binary files, and anything the daemon will not read, say so.
import SwiftUI
import WebKit

struct FileViewer: View {
    let machine: Machine
    let entry: FsEntry
    @EnvironmentObject var store: MeshStore

    @State private var text: String?
    @State private var truncated = false
    @State private var failure: String?
    @AppStorage("terminalFontSize") private var fontSize: Double = 12
    @State private var magnifyStart: Double?

    private var ext: String { (entry.name as NSString).pathExtension.lowercased() }
    private var isMarkdown: Bool { ["md", "markdown", "mdx"].contains(ext) }
    private var isHTML: Bool { ["html", "htm"].contains(ext) }

    var body: some View {
        Group {
            if let failure {
                ContentUnavailableView("Can't show this file", systemImage: "doc.questionmark", description: Text(failure))
            } else if let text {
                if isHTML {
                    HTMLView(html: text)
                        .ignoresSafeArea(edges: .bottom)
                } else if isMarkdown {
                    ScrollView {
                        MarkdownDocument(source: text)
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    ScrollView([.horizontal, .vertical]) {
                        Text(text)
                            .font(.system(size: min(22, max(9, fontSize)), design: .monospaced))
                            .textSelection(.enabled)
                            .fixedSize(horizontal: true, vertical: true)
                            .padding(12)
                    }
                    .gesture(MagnifyGesture().onChanged { value in
                        let start = magnifyStart ?? fontSize
                        if magnifyStart == nil { magnifyStart = start }
                        fontSize = min(22, max(9, start * Double(value.magnification)))
                    }.onEnded { _ in magnifyStart = nil })
                }
            } else {
                ProgressView("Reading \(entry.name)…")
            }
        }
        .safeAreaInset(edge: .bottom) {
            if truncated {
                Text("Showing the first 256 KB — the rest is on \(machine.host).")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity).padding(8).background(.thinMaterial)
            }
        }
        .navigationTitle(entry.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let text {
                ShareLink(item: text, subject: Text(entry.name)) { Image(systemName: "square.and.arrow.up") }
                Button { UIPasteboard.general.string = text } label: { Image(systemName: "doc.on.doc") }
                    .accessibilityLabel("Copy contents")
            }
        }
        .task(id: entry.path) { await load() }
    }

    private func load() async {
        do {
            let file = try await store.client(for: machine).fsRead(path: entry.path, max: 262_144)
            text = file.text
            truncated = file.truncated ?? false
        } catch let error as MeshClient.MeshError {
            failure = error.reason ?? "The machine refused to read it."
        } catch {
            failure = "Couldn't reach \(machine.host)."
        }
    }
}

/// HTML from the machine, rendered locally. Loaded as a string: no origin, no cookies,
/// no token of ours in scope, and links open in Safari rather than inside this view.
private struct HTMLView: UIViewRepresentable {
    let html: String

    func makeUIView(context: Context) -> WKWebView {
        let web = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        web.navigationDelegate = context.coordinator
        web.loadHTMLString(html, baseURL: nil)
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, WKNavigationDelegate {
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if action.navigationType == .linkActivated, let url = action.request.url {
                UIApplication.shared.open(url)
                return decisionHandler(.cancel)
            }
            decisionHandler(.allow)
        }
    }
}

/// A whole Markdown file, block by block — headings, paragraphs, nested lists, fenced code,
/// quotes, rules — on Foundation's inline parser (bold, italic, code, links). The chat
/// view's `MarkdownBlocks` handles an agent's short replies; a README needs headings and
/// nesting it does not. Tables stay as their source in a code block.
struct MarkdownDocument: View {
    let source: String

    private enum Block {
        case heading(Int, String), paragraph(String), code(String), quote(String), item(Int, String, ordered: Bool), rule
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .heading(let level, let text):
                    inline(text)
                        .font(level == 1 ? .title2.bold() : level == 2 ? .title3.bold() : .headline)
                        .padding(.top, level <= 2 ? 6 : 2)
                case .paragraph(let text):
                    inline(text).font(.body)
                case .code(let text):
                    ScrollView(.horizontal, showsIndicators: false) {
                        Text(text)
                            .font(.system(.footnote, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(10)
                    }
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
                case .quote(let text):
                    HStack(alignment: .top, spacing: 8) {
                        Rectangle().fill(Color.secondary.opacity(0.4)).frame(width: 3)
                        inline(text).font(.body).foregroundStyle(.secondary)
                    }
                case .item(let depth, let text, let ordered):
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(ordered ? "•" : "•").font(.body).foregroundStyle(.secondary)
                        inline(text).font(.body)
                    }
                    .padding(.leading, CGFloat(depth) * 14)
                case .rule:
                    Divider()
                }
            }
        }
    }

    private func inline(_ s: String) -> Text {
        var options = AttributedString.MarkdownParsingOptions()
        options.interpretedSyntax = .inlineOnlyPreservingWhitespace
        if let attributed = try? AttributedString(markdown: s, options: options) { return Text(attributed) }
        return Text(s)
    }

    private var blocks: [Block] {
        var out: [Block] = []
        var paragraph: [String] = []
        var code: [String]? = nil
        var table: [String] = []
        func flush() {
            if !paragraph.isEmpty { out.append(.paragraph(paragraph.joined(separator: " "))); paragraph.removeAll() }
            // A table is one block, monospaced, scrolling sideways — the columns line up
            // the way the author drew them, and a phone reads it like a spreadsheet.
            if !table.isEmpty { out.append(.code(table.joined(separator: "\n"))); table.removeAll() }
        }
        for raw in source.components(separatedBy: "\n") {
            let line = raw.replacingOccurrences(of: "\t", with: "    ")
            if let open = code {
                if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") { out.append(.code(open.joined(separator: "\n"))); code = nil }
                else { code!.append(line) }
                continue
            }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("|") { if !paragraph.isEmpty { out.append(.paragraph(paragraph.joined(separator: " "))); paragraph.removeAll() }; table.append(trimmed); continue }
            if !table.isEmpty { flush() }
            if trimmed.hasPrefix("```") { flush(); code = []; continue }
            if trimmed.isEmpty { flush(); continue }
            if trimmed == "---" || trimmed == "***" || trimmed == "___" { flush(); out.append(.rule); continue }
            if let hashes = trimmed.prefix(while: { $0 == "#" }).count as Int?, hashes >= 1, hashes <= 6, trimmed.dropFirst(hashes).first == " " {
                flush(); out.append(.heading(hashes, String(trimmed.dropFirst(hashes + 1)))); continue
            }
            if trimmed.hasPrefix("> ") || trimmed == ">" { flush(); out.append(.quote(String(trimmed.dropFirst(trimmed == ">" ? 1 : 2)))); continue }
            let indent = line.prefix(while: { $0 == " " }).count
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") {
                flush(); out.append(.item(indent / 2, String(trimmed.dropFirst(2)), ordered: false)); continue
            }
            if let dot = trimmed.firstIndex(of: "."), trimmed[..<dot].allSatisfy(\.isNumber), !trimmed[..<dot].isEmpty,
               trimmed[trimmed.index(after: dot)...].hasPrefix(" ") {
                flush(); out.append(.item(indent / 2, String(trimmed[trimmed.index(dot, offsetBy: 2)...]), ordered: true)); continue
            }
            paragraph.append(trimmed)
        }
        if let open = code { out.append(.code(open.joined(separator: "\n"))) }
        flush()
        return out
    }
}

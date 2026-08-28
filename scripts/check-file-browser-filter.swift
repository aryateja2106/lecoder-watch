import Foundation

// Run: swiftc Shared/Models.swift scripts/check-file-browser-filter.swift -o /tmp/cfbf && /tmp/cfbf

func entry(_ name: String, dir: Bool = false) -> FsEntry {
    FsEntry(name: name, path: "/x/\(name)", kind: dir ? "dir" : "file", size: 0, modifiedISO: nil)
}

@main
struct CheckFileBrowserFilter {
    static func main() {
        let listing = [
            entry(".git", dir: true),
            entry(".env"),
            entry("Package.swift"),
            entry("Sources", dir: true),
            entry("README.md"),
        ]

        // Default view: dotfiles and dotfolders gone, everything else stays, order kept.
        let visible = filterFsEntries(listing, showHidden: false, query: "")
        assert(visible.map(\.name) == ["Package.swift", "Sources", "README.md"])

        // Toggled on: nothing is dropped for being a dotfile.
        let all = filterFsEntries(listing, showHidden: true, query: "")
        assert(all.count == listing.count)

        // Search is case-insensitive substring, applied after the hidden filter —
        // a dotfile does not resurface just because the query happens to match it.
        assert(filterFsEntries(listing, showHidden: false, query: "package").map(\.name) == ["Package.swift"])
        assert(filterFsEntries(listing, showHidden: false, query: "ENV").isEmpty)
        assert(filterFsEntries(listing, showHidden: true, query: "env").map(\.name) == [".env"])

        // Whitespace-only query behaves like no query.
        assert(filterFsEntries(listing, showHidden: true, query: "   ").count == listing.count)

        // No match anywhere: empty, not a crash.
        assert(filterFsEntries(listing, showHidden: true, query: "zzz").isEmpty)

        print("check-file-browser-filter: OK")
    }
}

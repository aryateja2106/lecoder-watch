// GuidesView.swift — the short how-tos a new owner needs: pairing, letting agents install apps on this phone and watch, granting a Mac, a Linux desktop, overnight agents.
//
// Static text on purpose. Every step here is something the app cannot do for the person —
// a switch in iOS Settings, a permission dialog on the Mac, a command on the machine — so
// the honest help is to say exactly where the switch is. Add a guide by adding an entry.
import SwiftUI

struct Guide: Identifiable {
    let id: String
    let title: String
    let symbol: String
    let summary: String
    let steps: [String]
}

extension Guide {
    static let all: [Guide] = [
        Guide(id: "pair", title: "Pair a machine", symbol: "qrcode.viewfinder",
              summary: "One command on the machine, one scan here.",
              steps: [
                "On the Mac or Linux box, run the install command from Machines → ＋ (it keeps an existing token).",
                "Run `mesh pair` there. It prints a QR code and an eight-character code, good for ten minutes.",
                "Scan the QR with the Camera app, or tap ＋ here and type the code. Pairing one machine adopts every machine it already knows.",
                "Your watch picks the fleet up the next time its app opens.",
              ]),
        Guide(id: "developer-mode", title: "Let agents install apps on this iPhone", symbol: "iphone.gen3.badge.play",
              summary: "Developer Mode once, then every native build installs from the Apps tab.",
              steps: [
                "iPhone: Settings → Privacy & Security → Developer Mode → on, then restart when asked.",
                "On the Mac that builds: `mesh apps config --team <TEAMID> --prefix com.yourname` so builds are signed for your devices (the team ID is in Xcode → Settings → Accounts).",
                "For cable-free installs: `mesh apps ota --enable` on that Mac. It serves builds over Tailscale HTTPS, which is what iOS's installer insists on.",
                "First launch of a new build: Settings → General → VPN & Device Management → trust the developer certificate.",
                "Then: Apps tab → Install. \"On this iPhone\" appears once the app has been opened from here.",
              ]),
        Guide(id: "watch", title: "Apps on Apple Watch", symbol: "applewatch",
              summary: "The watch build rides inside the iPhone app.",
              steps: [
                "Apple Watch: Settings → Privacy & Security → Developer Mode → on.",
                "Build the iPhone app with its watch target; installing the iPhone build installs the watch app with it.",
              ]),
        Guide(id: "mac-control", title: "Control a Mac from here", symbol: "macbook",
              summary: "Two permissions on the Mac, granted once.",
              steps: [
                "Machines → the Mac → Setup: tap \"Grant on <Mac>\". Two dialogs open on the Mac's own screen.",
                "Approve Accessibility (clicks and keys) and Screen Recording (the screen you see) under System Settings → Privacy & Security.",
                "Pull to refresh. Setup should read \"all pass\"; Remote → Screen & control is live.",
                "Sleep, lock, screenshot-to-clipboard and the rest live under Power on the machine's page and under System on the watch.",
              ]),
        Guide(id: "linux", title: "Control a Linux desktop", symbol: "pc",
              summary: "An X11 session, three small tools, no VNC server.",
              steps: [
                "The machine needs a logged-in X11 desktop (`:0`). Install `xdotool`, `scrot` and `xclip` (`apt install xdotool scrot xclip`).",
                "Run the install command; the daemon runs as your user and starts at login (`loginctl enable-linger` keeps it up after logout).",
                "If the desktop is not `:0`, set `MESH_DISPLAY` in `~/.mesh/meshd.env` and restart the daemon.",
                "Running apps, clipboard, screenshots and power actions then work the same as on a Mac.",
              ]),
        Guide(id: "overnight", title: "Run an agent while you are away", symbol: "moon.stars",
              summary: "Start it from here, answer it from your wrist.",
              steps: [
                "Terminal → a machine → New session. Pick the CLI (Claude, Codex, Cursor…), a folder and type the task.",
                "Run `mesh hooks install` once on that machine so the agent's questions reach this phone.",
                "When it stops at a question, the bell and the watch buzz. Continue answers the highlighted choice; Open session shows the conversation.",
                "Agents started in a plain terminal outside LeSearch still report, but nothing here can answer them — start them from New session.",
                "Sessions live in tmux on the machine: close the app, come back, they are still there.",
              ]),
    ]
}

struct GuidesView: View {
    var body: some View {
        List {
            Section {
                Text("Less Search. More Agents.")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("The parts no app can do for you — where the switches are.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(Guide.all) { guide in
                Section {
                    DisclosureGroup {
                        ForEach(Array(guide.steps.enumerated()), id: \.offset) { index, step in
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text("\(index + 1)")
                                    .font(.caption.monospacedDigit().weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 18, alignment: .trailing)
                                Text(step).font(.subheadline)
                            }
                            .padding(.vertical, 2)
                        }
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(guide.title).font(.headline)
                                Text(guide.summary).font(.caption).foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: guide.symbol)
                        }
                    }
                }
            }
        }
        .navigationTitle("Guides")
    }
}

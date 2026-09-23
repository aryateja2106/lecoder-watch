// Shared catalogue for every machine-level action offered by the phone and watch.
/// The machine-level actions a wrist or a thumb can fire at `POST /system`. One list for
/// both apps; `action` is meshd's own vocabulary and is sent verbatim.
enum PowerAction: String, CaseIterable, Identifiable {
    case lock, displaysleep, sleep, screensaver, screenshot, restart, shutdown

    var id: String { rawValue }

    var label: String {
        switch self {
        case .lock: "Lock"
        case .displaysleep: "Sleep display"
        case .sleep: "Sleep"
        case .screensaver: "Screen saver"
        case .screenshot: "Screenshot → clipboard"
        case .restart: "Restart…"
        case .shutdown: "Shut Down…"
        }
    }

    var symbol: String {
        switch self {
        case .lock: "lock.fill"
        case .displaysleep: "display"
        case .sleep: "moon.fill"
        case .screensaver: "sparkles.tv"
        case .screenshot: "camera.viewfinder"
        case .restart: "arrow.clockwise.circle"
        case .shutdown: "power"
        }
    }

    /// Restart and Shut Down are not reversible from anywhere in the app; everything else is
    /// reversible from the machine's own keyboard, so only these two confirm.
    var confirms: Bool { self == .restart || self == .shutdown }

    /// Consequence line for the confirm dialogs (restart/shutdown), nil otherwise.
    func consequence(machineName: String) -> (title: String, verb: String, consequence: String)? {
        switch self {
        case .restart:
            ("Restart \(machineName)?", "Restart", "Every session on it stops. Anything unsaved there is lost, and agents mid-task will not come back on their own.")
        case .shutdown:
            ("Shut down \(machineName)?", "Shut Down", "Every session stops and the machine goes dark. After that only its own power button, or a wake packet from a machine on the same network, brings it back.")
        default:
            nil
        }
    }

    static let reversible: [PowerAction] = [.lock, .displaysleep, .sleep, .screensaver, .screenshot]
    static let irreversible: [PowerAction] = [.restart, .shutdown]
}

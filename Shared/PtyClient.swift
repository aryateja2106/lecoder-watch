// PtyClient.swift — the phone's end of meshd's `GET /agents/:name/pty` WebSocket: raw pty bytes in, keystrokes out, resize/ping as JSON, reconnect with backoff.
//
// Mirrors install/payload/meshd/pty.ts. Binary frames are the pane's bytes and the
// emulator's keystrokes; text frames are the control messages. The socket is opened with
// the machine's bearer on the upgrade request, tried against each of the machine's
// addresses the way every HTTP call is.
import Foundation

@MainActor
final class PtyClient {
    enum State: Equatable { case idle, connecting, open, closed(String?) }

    private let machine: Machine
    private let session: String
    private let pane: String?
    private var task: URLSessionWebSocketTask?
    private var wantOpen = false
    private var attempt = 0
    private var cols = 80
    private var rows = 24
    private var pinger: Task<Void, Never>?
    /// Bytes from the pane, on the main actor, in arrival order.
    var onBytes: ((Data) -> Void)?
    var onState: ((State) -> Void)?
    private(set) var state: State = .idle { didSet { if state != oldValue { onState?(state) } } }

    init(machine: Machine, session: String, pane: String? = nil) {
        self.machine = machine
        self.session = session
        self.pane = pane
    }

    private var path: String {
        var p = "/agents/\(MeshClient.pathSegment(session))/pty?cols=\(cols)&rows=\(rows)"
        if let pane, !pane.isEmpty, let enc = pane.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            p += "&pane=\(enc)"
        }
        return p
    }

    func connect(cols: Int, rows: Int) {
        self.cols = cols; self.rows = rows
        wantOpen = true
        attempt = 0
        open()
    }

    private func open() {
        guard wantOpen else { return }
        state = .connecting
        // The address order MeshClient uses: loopback first on the simulator, then the
        // tailnet IP, then the name. One socket at a time; the next address is tried on
        // failure through the same backoff path.
        let bases = machine.baseURLs
        guard !bases.isEmpty else { state = .closed("no address"); return }
        let base = bases[attempt % bases.count]
        guard var comps = URLComponents(url: base, resolvingAgainstBaseURL: false) else { state = .closed("bad address"); return }
        comps.scheme = comps.scheme == "https" ? "wss" : "ws"
        guard let url = URL(string: path, relativeTo: comps.url) else { state = .closed("bad address"); return }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(machine.token)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 8
        let t = URLSession.shared.webSocketTask(with: req)
        task = t
        t.resume()
        receive(on: t)
        // The first successful receive marks the socket open; a JSON ping fires it
        // immediately instead of waiting for the pane to print something.
        t.send(.string(#"{"t":"ping"}"#)) { [weak self] err in
            guard let self, let err else { return }
            Task { @MainActor in self.failed(t, "\(err.localizedDescription)") }
        }
    }

    private func receive(on t: URLSessionWebSocketTask) {
        t.receive { [weak self] result in
            Task { @MainActor in
                guard let self, self.task === t else { return }
                switch result {
                case .success(let msg):
                    if self.state != .open {
                        self.state = .open
                        self.attempt = 0
                        self.startPinger(t)
                    }
                    switch msg {
                    case .data(let d): self.onBytes?(d)
                    case .string(let s): self.control(s)
                    @unknown default: break
                    }
                    self.receive(on: t)
                case .failure(let err):
                    self.failed(t, err.localizedDescription)
                }
            }
        }
    }

    private func control(_ s: String) {
        guard let obj = try? JSONSerialization.jsonObject(with: Data(s.utf8)) as? [String: Any],
              let t = obj["t"] as? String else { return }
        switch t {
        case "exit": failed(task, "the attach ended")
        case "error": failed(task, obj["msg"] as? String ?? "daemon error")
        default: break
        }
    }

    private func failed(_ t: URLSessionWebSocketTask?, _ why: String) {
        guard t == nil || t === task else { return }
        pinger?.cancel(); pinger = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        guard wantOpen else { state = .closed(nil); return }
        state = .closed(why)
        // 0.5 s → 8 s, the same curve the peek screen's polling uses when a machine drops.
        let delay = min(8.0, 0.5 * pow(2.0, Double(min(attempt, 4))))
        attempt += 1
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            guard self.wantOpen, self.task == nil else { return }
            self.open()
        }
    }

    private func startPinger(_ t: URLSessionWebSocketTask) {
        pinger?.cancel()
        pinger = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                guard let self, self.task === t else { return }
                t.send(.string(#"{"t":"ping"}"#)) { _ in }
            }
        }
    }

    func send(_ bytes: [UInt8]) {
        guard let task, state == .open else { return }
        task.send(.data(Data(bytes))) { [weak self] err in
            guard let self, let err else { return }
            Task { @MainActor in self.failed(task, err.localizedDescription) }
        }
    }

    func resize(cols: Int, rows: Int) {
        guard cols != self.cols || rows != self.rows else { return }
        self.cols = cols; self.rows = rows
        guard let task, state == .open else { return }
        task.send(.string(#"{"t":"resize","cols":\#(cols),"rows":\#(rows)}"#)) { _ in }
    }

    func close() {
        wantOpen = false
        pinger?.cancel(); pinger = nil
        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
        state = .closed(nil)
    }
}

// PairView.swift — the pairing QR, on the Mac's own screen.
//
// Same code path as `mesh pair`: GET /pair/new over loopback (the daemon refuses to
// mint a code for anyone else), then the same deep link rendered as the same QR. The
// difference is only that this one is drawn with CoreImage instead of half-block
// characters in a terminal.
//
// Minting is not free of consequence: meshd keeps exactly one pending code, so opening
// this window or pressing Regenerate invalidates whatever `mesh pair` printed earlier.
// That is the intended behaviour — one code, ten minutes, one use.
import SwiftUI
import CoreImage.CIFilterBuiltins
import AppKit

struct PairView: View {
    @State private var code: LocalDaemon.PairCode?
    @State private var address = ""
    @State private var expiresAt: Date?
    @State private var expired = false
    @State private var failure: String?
    @State private var minting = false

    private static let side: CGFloat = 220

    var body: some View {
        VStack(spacing: 16) {
            Text("Pair your iPhone").font(.title2.weight(.semibold))

            if let failure {
                problem(failure)
            } else if address.isEmpty && code != nil {
                // A QR pointing at nothing is worse than no QR: it scans, opens the app,
                // and fails somewhere the user cannot see.
                problem("This Mac has no Tailscale or LAN address right now, so a phone would have nowhere to connect.")
            } else if let code {
                qr(for: code)
                details(for: code)
            } else {
                ProgressView().controlSize(.small)
            }

            Spacer(minLength: 0)

            Button(minting ? "Asking meshd…" : "Regenerate") { Task { await mint() } }
                .disabled(minting)
        }
        .padding(24)
        .frame(minWidth: 340, minHeight: 480)
        .task { await mint() }
    }

    @ViewBuilder
    private func qr(for code: LocalDaemon.PairCode) -> some View {
        let link = LocalDaemon.pairingLink(address: address, port: code.port, code: code.code)
        ZStack {
            RoundedRectangle(cornerRadius: 10).fill(.white)
            if let image = Self.qrImage(link, side: Self.side) {
                Image(nsImage: image)
                    // Nearest-neighbour, or the scaler blurs module edges into something
                    // a camera has to work to read.
                    .interpolation(.none)
                    .resizable()
                    .frame(width: Self.side, height: Self.side)
            }
        }
        // The white margin is the quiet zone the QR spec requires — CoreImage does not
        // add one, and most cameras refuse a code that runs to the edge.
        .frame(width: Self.side + 24, height: Self.side + 24)
        .opacity(expired ? 0.25 : 1)
        .overlay {
            if expired {
                Text("This code has expired").font(.headline)
            }
        }
    }

    @ViewBuilder
    private func details(for code: LocalDaemon.PairCode) -> some View {
        VStack(spacing: 10) {
            Text(code.pretty)
                .font(.system(.title, design: .monospaced).weight(.medium))
                .textSelection(.enabled)

            Text("\(address) · port \(code.port)")
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            if let expiresAt, !expired {
                HStack(spacing: 4) {
                    Text("Expires in")
                    Text(expiresAt, style: .timer).monospacedDigit()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Text("Point the iPhone's Camera app at the square and tap the banner. No QR reader? Open LeSearch Mesh → Machines → Add machine and type the code. It works once.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func problem(_ text: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "bolt.horizontal.circle").font(.largeTitle).foregroundStyle(.orange)
            Text(text)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 30)
    }

    private func mint() async {
        guard !minting else { return }
        minting = true
        defer { minting = false }
        do {
            let fresh = try await LocalDaemon.pairNew()
            code = fresh
            address = LocalDaemon.reachableAddress()
            expiresAt = Self.parse(fresh.expiresISO) ?? Date().addingTimeInterval(TimeInterval(fresh.ttlSec))
            expired = false
            failure = nil
            await watchForExpiry()
        } catch {
            failure = error.localizedDescription
            code = nil
        }
    }

    /// The countdown text is free; knowing the moment it hits zero is not, and a QR that
    /// silently stops working is the kind of thing you debug for ten minutes.
    private func watchForExpiry() async {
        guard let expiresAt else { return }
        let seconds = expiresAt.timeIntervalSinceNow
        guard seconds > 0 else { expired = true; return }
        try? await Task.sleep(for: .seconds(seconds))
        if !Task.isCancelled, self.expiresAt == expiresAt { expired = true }
    }

    private static func parse(_ iso: String) -> Date? {
        let withMillis = ISO8601DateFormatter()
        withMillis.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withMillis.date(from: iso) { return date }
        return ISO8601DateFormatter().date(from: iso)
    }

    /// Correction level M, the same trade `mesh pair` makes: enough redundancy for a
    /// phone held at an angle, without inflating the module count until the squares are
    /// too small to read off a Retina display.
    private static func qrImage(_ text: String, side: CGFloat) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage, output.extent.width > 0 else { return nil }
        let scale = side / output.extent.width
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cg = CIContext().createCGImage(scaled, from: scaled.extent) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: side, height: side))
    }
}

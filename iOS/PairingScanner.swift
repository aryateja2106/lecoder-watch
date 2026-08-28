import SwiftUI
import AVFoundation

/// Camera-based reader for a `meshwatch://pair` QR, opened from inside the pairing
/// sheet. It recognizes the code and parses it with `parsePairingLink` — the exact
/// same rules `MeshStore.open(url:)` applies to a link the system Camera hands off —
/// then hands the three fields back to the caller. It does not pair anything itself:
/// the human still reads the prefilled code on the pairing form and taps Pair, and
/// that comparison against what the terminal printed is the security property this
/// scanner must not shortcut.
struct PairingScannerSheet: View {
    @Environment(\.dismiss) private var dismiss
    var onScanned: (PairingLink) -> Void

    @State private var rejection: String?

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                QRCaptureView { payload in
                    guard let url = URL(string: payload), let link = parsePairingLink(url) else {
                        rejection = "That QR isn't a MeshWatch pairing code."
                        return
                    }
                    rejection = nil
                    onScanned(link)
                }
                .ignoresSafeArea()

                if let rejection {
                    Text(rejection)
                        .font(.callout)
                        .foregroundStyle(.white)
                        .padding(10)
                        .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 10))
                        .padding(.bottom, 40)
                        .transition(.opacity)
                        .animation(.default, value: rejection)
                }
            }
            .navigationTitle("Scan pairing code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

/// UIKit bridge for the capture session — SwiftUI has no QR reader of its own.
private struct QRCaptureView: UIViewControllerRepresentable {
    var onDecode: (String) -> Void

    func makeUIViewController(context: Context) -> ScannerViewController {
        let vc = ScannerViewController()
        vc.onDecode = onDecode
        return vc
    }

    func updateUIViewController(_ uiViewController: ScannerViewController, context: Context) {}
}

/// QR-only capture: one input, one metadata output, one preview layer. Runs the
/// session on a background queue (Apple's own guidance — starting it on the main
/// thread stalls the sheet's opening animation) and stops it the moment the view
/// goes away, so a cancelled scan doesn't leave the camera light on.
private final class ScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onDecode: ((String) -> Void)?
    private let session = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var lastValue: String?
    private var lastFired = Date.distantPast

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { return }
        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { return }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.qr]

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        preview.frame = view.bounds
        view.layer.addSublayer(preview)
        previewLayer = preview
    }

    // `CALayer.autoresizingMask` is a macOS-only API (NSView layer-backing) —
    // unavailable on iOS despite compiling on some SDKs, so the preview layer's
    // frame is kept in sync by hand instead of relying on it.
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !session.isRunning else { return }
        DispatchQueue.global(qos: .userInitiated).async { [session] in session.startRunning() }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        guard session.isRunning else { return }
        DispatchQueue.global(qos: .userInitiated).async { [session] in session.stopRunning() }
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput,
                         didOutput metadataObjects: [AVMetadataObject],
                         from connection: AVCaptureConnection) {
        guard let code = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              code.type == .qr, let value = code.stringValue else { return }
        // The delegate fires many times a second for the same frame; without this, a
        // rejected scan would flash a fresh "not a pairing code" toast on every tick
        // instead of giving someone time to read it and re-aim.
        let now = Date()
        guard value != lastValue || now.timeIntervalSince(lastFired) > 1 else { return }
        lastValue = value
        lastFired = now
        onDecode?(value)
    }
}

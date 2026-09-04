// VoiceInput — the one voice-input sheet.
//
// Replaces the old two-step flow in AgentChatView.swift (VoiceRecordingSheet, a
// read-only "Listening…" screen, handing off on Stop to TranscriptionCorrectionSheet, a
// separate review screen with quick-insert keyword chips) with a single screen: the
// transcript is editable the whole time, Stop pauses without losing anything, Resume
// appends instead of starting over, and there is nowhere for the text to go missing
// between "recording" and "review" because there is no longer a handoff between them.
// Those two old sheets are superseded, not deleted — see the report for why.
import SwiftUI

public struct VoiceInputSheet: View {
    let onSend: (String) -> Void
    let onCancel: () -> Void

    @State private var transcriber = VoiceTranscriber.shared
    @State private var text: String = ""
    @State private var isRecording = true
    @State private var didFinish = false

    public init(onSend: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        self.onSend = onSend
        self.onCancel = onCancel
    }

    private var trimmedText: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var currentLevel: Float {
        if case .recording(let level, _) = transcriber.state { return level }
        return 0
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                LevelMeter(level: currentLevel)
                    .frame(height: 10)
                    .padding(.horizontal, 24)
                    .padding(.top, 8)

                ZStack(alignment: .topLeading) {
                    TextEditor(text: $text)
                        .font(.body)
                        .padding(10)
                        .frame(maxHeight: .infinity)
                        .background(Color(.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 14))

                    if text.isEmpty {
                        Text(isRecording ? "Listening…" : "Nothing recognized yet.")
                            .foregroundStyle(.secondary)
                            .padding(18)
                            .allowsHitTesting(false)
                    }
                }
                .padding(.horizontal, 16)

                if case .error(let message) = transcriber.state {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal, 16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                stopResumeButton

                if !isRecording && trimmedText.isEmpty {
                    Button {
                        Task {
                            await transcriber.transcribeAgain()
                            text = transcriber.recognizedText
                        }
                    } label: {
                        Label("Transcribe again", systemImage: "arrow.clockwise")
                            .font(.subheadline)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color(.tertiarySystemFill))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }

                HStack(spacing: 16) {
                    Button {
                        didFinish = true
                        onCancel()
                    } label: {
                        Text("Cancel")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color(.tertiarySystemFill))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }

                    Button {
                        didFinish = true
                        onSend(trimmedText)
                    } label: {
                        Text("Send")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(trimmedText.isEmpty ? Color.gray.opacity(0.4) : Color.accentColor)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .disabled(trimmedText.isEmpty)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Voice Input")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear {
            Task { await transcriber.startRecording() }
        }
        .onChange(of: transcriber.recognizedText) { _, new in
            if isRecording { text = new }
        }
        .onDisappear {
            // Covers every way out — Send, Cancel, or an interactive swipe-dismiss the
            // buttons below never see — so the mic never keeps listening in the background.
            transcriber.cancelRecording()
            if !didFinish { onCancel() }
        }
    }

    private var stopResumeButton: some View {
        Button {
            if isRecording {
                isRecording = false
                Task { await transcriber.stopRecording() }
            } else {
                isRecording = true
                Task { await transcriber.resumeRecording(withText: text) }
            }
        } label: {
            Label(isRecording ? "Stop" : "Resume", systemImage: isRecording ? "stop.fill" : "mic.fill")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(isRecording ? Color.red : Color.accentColor)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .padding(.horizontal, 16)
    }
}

private struct LevelMeter: View {
    let level: Float

    var body: some View {
        GeometryReader { geo in
            RoundedRectangle(cornerRadius: 5)
                .fill(Color(.tertiarySystemFill))
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color.accentColor)
                        .frame(width: geo.size.width * CGFloat(level))
                        .animation(.easeOut(duration: 0.1), value: level)
                }
        }
    }
}

#Preview {
    VoiceInputSheet(onSend: { _ in }, onCancel: {})
}

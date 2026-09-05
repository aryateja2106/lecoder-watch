// VoiceInput — the one voice-input sheet.
//
// Replaces the old two-step flow in AgentChatView.swift (VoiceRecordingSheet, a
// read-only "Listening…" screen, handing off on Stop to TranscriptionCorrectionSheet, a
// separate review screen with quick-insert keyword chips) with a single screen: Stop
// pauses without losing anything, Resume appends instead of starting over, and there is
// nowhere for the text to go missing between "recording" and "review" because there is
// no longer a handoff between them. Those two old sheets are superseded, not deleted —
// see the report for why.
//
// The transcript is the user's whenever the recognizer is not writing to it. While it is
// listening, a tap on the transcript stops the session (the way tapping into text ends
// Apple's own dictation) — an edit made while the recognizer was still streaming used to
// be overwritten by its next partial a moment later. Recording truth comes from the
// transcriber's state, not a local flag: a phone call, a refused permission, or a
// recognizer that gave up all end the session without a tap on Stop, and the sheet has
// to follow.
import SwiftUI

public struct VoiceInputSheet: View {
    let onSend: (String) -> Void
    let onCancel: () -> Void

    @State private var transcriber = VoiceTranscriber.shared
    @State private var text: String = ""
    @State private var didFinish = false

    public init(onSend: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        self.onSend = onSend
        self.onCancel = onCancel
    }

    private var trimmedText: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var isRecording: Bool {
        if case .recording = transcriber.state { return true }
        return false
    }

    private var isStopping: Bool { transcriber.state == .processing }

    private var currentLevel: Float {
        if case .recording(let level, _) = transcriber.state { return level }
        return 0
    }

    private var placeholder: String {
        if isRecording { return "Listening…" }
        if isStopping { return "Finishing…" }
        return "Nothing recognized yet."
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
                        Text(placeholder)
                            .foregroundStyle(.secondary)
                            .padding(18)
                            .allowsHitTesting(false)
                    }

                    if isRecording {
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture { stop() }
                    }
                }
                .padding(.horizontal, 16)

                Text(transcriber.recognitionMode)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if case .error(let message) = transcriber.state {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal, 16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                stopResumeButton

                if !isRecording && !isStopping && trimmedText.isEmpty {
                    Button {
                        Task { await transcriber.transcribeAgain() }
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
            // Mirror while listening and while the last words of a stopped session are
            // still landing; once stopped, the editor belongs to the user.
            if isRecording || isStopping { text = new }
        }
        .onChange(of: transcriber.state) { _, new in
            // Stop (by tap, by a phone call, by "Transcribe again") hands over the final
            // text exactly once, after the recognizer's last word has been folded in.
            if case .readyForReview(let final) = new { text = final }
        }
        .onDisappear {
            // Covers every way out — Send, Cancel, or an interactive swipe-dismiss the
            // buttons below never see — so the mic never keeps listening in the background.
            transcriber.cancelRecording()
            if !didFinish { onCancel() }
        }
    }

    private func stop() {
        Task { await transcriber.stopRecording() }
    }

    private var stopResumeButton: some View {
        Button {
            if isRecording {
                stop()
            } else {
                Task { await transcriber.resumeRecording(withText: text) }
            }
        } label: {
            Label(isRecording ? "Stop" : (isStopping ? "Stopping…" : "Resume"),
                  systemImage: isRecording ? "stop.fill" : "mic.fill")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(isRecording ? Color.red : Color.accentColor)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .disabled(isStopping)
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

// VoiceTranscriber — on-device speech to text for the chat composer.
//
// Apple's recognizer with requiresOnDeviceRecognition, an AVAudioEngine tap for both the
// recognition buffer and the level meter, and a state machine the sheet renders. Nothing
// leaves the phone. An earlier draft also posted audio to a "Nemotron server" on the Mac at
// a port and route that do not exist; that path was removed rather than ported.
//
// A recognition TASK is not the same thing as the recording SESSION. Apple ends a task on
// a silence gap, on the on-device ~60s ceiling, or on a real error — and the previous code
// treated every one of those as "replace recognizedText with whatever comes next," so a
// pause made everything said before it disappear. `segments` (VoiceSegments) is the fix:
// each finished task's text is folded into `committed`, then a fresh request starts on the
// SAME running engine tap — the user should never see the recognizer "start over." The
// audio itself is also captured independently to a temp `.caf` file as a safety net: if
// recognition produces nothing, `transcribeAgain()` re-runs it as a one-shot file request.
import Foundation
import AVFoundation
import Speech
import Observation

public enum VoiceTranscriberState: Equatable {
    case idle
    case recording(audioLevel: Float, partialText: String)
    case processing
    case readyForReview(text: String)
    case error(message: String)

    public static func == (lhs: VoiceTranscriberState, rhs: VoiceTranscriberState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.processing, .processing):
            return true
        case (.recording(let lLevel, let lText), .recording(let rLevel, let rText)):
            return abs(lLevel - rLevel) < 0.05 && lText == rText
        case (.readyForReview(let lText), .readyForReview(let rText)):
            return lText == rText
        case (.error(let lMsg), .error(let rMsg)):
            return lMsg == rMsg
        default:
            return false
        }
    }
}

@Observable
@MainActor
public final class VoiceTranscriber: NSObject {
    public static let shared = VoiceTranscriber()

    public var state: VoiceTranscriberState = .idle
    /// Committed segments plus whatever the live task has recognized so far. Never
    /// reset except by `startRecording()` (a genuinely new session) or `cancelRecording()`.
    public var recognizedText: String { segments.compose(partial: partialText) }
    /// The most recent safety-net recording. Set as soon as its file is created, so
    /// "Transcribe again" has something to work with even if live recognition never
    /// produced a word.
    public private(set) var lastRecordingURL: URL?

    private let speechRecognizer = SFSpeechRecognizer(locale: Locale.current)
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    private var audioSampleRate: Double = 16000.0
    private var recordingFile: AVAudioFile?

    private var segments = VoiceSegments()
    private var partialText: String = ""
    /// Bumped on every fresh `startRecording()`/`cancelRecording()` so a completion
    /// callback from an already-torn-down task can never mutate the session that
    /// replaced it (a fast cancel-then-restart can otherwise race a late callback).
    private var generation = 0
    /// True from the moment `stopRecording()` begins until it finishes reading the
    /// final text. A task's completion callback arriving in that window should still
    /// commit its text — otherwise the last few words of a segment get lost — but must
    /// not restart a new request; `stopRecording()` owns what happens next.
    private var isStoppingSession = false

    public override init() {
        super.init()
    }

    // MARK: - Permission Checks

    public func requestPermissions() async -> Bool {
        let micAllowed = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }

        guard micAllowed else {
            state = .error(message: "Microphone permission denied. Enable in iPhone Settings.")
            return false
        }

        let speechAllowed = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }

        guard speechAllowed else {
            state = .error(message: "Speech recognition permission denied.")
            return false
        }

        return true
    }

    // MARK: - Recording & Transcription Control

    /// Starts a brand-new session: clears any previously accumulated text.
    public func startRecording() async {
        guard await requestPermissions() else { return }
        generation += 1
        stopAndReset()
        segments = VoiceSegments()
        partialText = ""
        await beginEngineSession()
    }

    /// Resumes after `stopRecording()` without losing what was already said.
    /// `text` is the caller's current (possibly hand-edited) buffer — it becomes the new
    /// committed baseline so a fresh request appends after it rather than after whatever
    /// the recognizer itself last committed.
    public func resumeRecording(withText text: String) async {
        if case .recording = state { return }
        guard await requestPermissions() else { return }
        segments = VoiceSegments(committed: text.trimmingCharacters(in: .whitespacesAndNewlines))
        partialText = ""
        await beginEngineSession()
    }

    /// Stops the recognizer but keeps `recognizedText` intact for review/editing.
    public func stopRecording() async {
        guard case .recording = state else { return }

        isStoppingSession = true
        state = .processing
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()

        // Give the in-flight task's final callback a moment to land and commit its text.
        try? await Task.sleep(for: .milliseconds(350))

        recordingFile = nil // finalize the safety-net file for this segment
        let finalText = recognizedText.trimmingCharacters(in: .whitespacesAndNewlines)
        if finalText.isEmpty {
            state = .idle
        } else {
            state = .readyForReview(text: finalText)
        }

        try? AVAudioSession.sharedInstance().setActive(false)
    }

    public func cancelRecording() {
        generation += 1
        isStoppingSession = false
        stopAndReset()
        segments = VoiceSegments()
        partialText = ""
        state = .idle
    }

    /// Safety net for when live recognition produced nothing: re-runs the captured
    /// audio file as a one-shot on-device request.
    public func transcribeAgain() async {
        guard let url = lastRecordingURL else {
            state = .error(message: "No recording to transcribe.")
            return
        }
        state = .processing
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = false
        if speechRecognizer?.supportsOnDeviceRecognition == true {
            request.requiresOnDeviceRecognition = true
        }
        do {
            let text = try await recognizeToCompletion(request).trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty {
                state = .error(message: "Could not transcribe the recording.")
            } else {
                segments.append(final: text)
                partialText = ""
                state = .readyForReview(text: recognizedText)
            }
        } catch {
            state = .error(message: "Transcription failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Engine Session

    /// Everything a running session needs: audio route, a fresh recognition request, the
    /// tap that feeds both the recognizer and the safety-net file, and the engine itself.
    /// Shared by `startRecording()` and `resumeRecording(withText:)` — the only difference
    /// between them is whether `segments`/`partialText` were reset first.
    private func beginEngineSession() async {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

            let inputNode = audioEngine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)
            audioSampleRate = recordingFormat.sampleRate

            let url = Self.newRecordingURL()
            recordingFile = try? AVAudioFile(forWriting: url, settings: recordingFormat.settings)
            if recordingFile != nil { lastRecordingURL = url }
            Self.pruneOldRecordings()

            isStoppingSession = false
            startRecognitionTask()

            inputNode.removeTap(onBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
                guard let self else { return }

                self.recognitionRequest?.append(buffer)
                try? self.recordingFile?.write(from: buffer)

                guard let channelData = buffer.floatChannelData?[0] else { return }
                let frames = Int(buffer.frameLength)
                var sum: Float = 0.0
                for i in 0..<frames {
                    let sample = channelData[i]
                    sum += sample * sample
                }
                let rms = sqrt(sum / Float(frames))
                let normalizedLevel = min(max((rms - 0.01) / 0.2, 0.0), 1.0)

                Task { @MainActor in
                    guard case .recording = self.state else { return }
                    self.state = .recording(audioLevel: normalizedLevel, partialText: self.partialText)
                }
            }

            audioEngine.prepare()
            try audioEngine.start()
            state = .recording(audioLevel: 0.0, partialText: partialText)

        } catch {
            state = .error(message: "Audio engine error: \(error.localizedDescription)")
            stopAndReset()
        }
    }

    /// Configures and starts one SFSpeechAudioBufferRecognitionRequest/Task pair against
    /// the currently running engine tap. Called once per engine session and again, mid
    /// session, every time a task ends but the user hasn't asked to stop.
    private func startRecognitionTask() {
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        if speechRecognizer?.supportsOnDeviceRecognition == true {
            request.requiresOnDeviceRecognition = true
        }
        recognitionRequest = request

        let mySession = generation
        recognitionTask = speechRecognizer?.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            Task { @MainActor in
                self.handleRecognitionEvent(generation: mySession, result: result, error: error)
            }
        }
    }

    /// One callback from the live streaming task: either a growing partial, or the task
    /// ending (isFinal, the ~60s ceiling, a silence gap, or a real error) — all of which
    /// look the same from here and all get folded into `segments` the same way.
    private func handleRecognitionEvent(generation gen: Int, result: SFSpeechRecognitionResult?, error: Error?) {
        guard gen == generation else { return } // a torn-down session's stray callback

        let isLive: Bool
        if case .recording = state { isLive = true } else { isLive = isStoppingSession }
        guard isLive else { return }

        if let result, !result.isFinal, error == nil {
            partialText = result.bestTranscription.formattedString
            if case .recording(let level, _) = state {
                state = .recording(audioLevel: level, partialText: partialText)
            }
            return
        }

        segments.append(final: result?.bestTranscription.formattedString ?? partialText)
        partialText = ""

        guard !isStoppingSession, case .recording(let level, _) = state else { return }
        state = .recording(audioLevel: level, partialText: "")
        startRecognitionTask()
    }

    private func recognizeToCompletion(_ request: SFSpeechRecognitionRequest) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            var didResume = false
            speechRecognizer?.recognitionTask(with: request) { result, error in
                guard !didResume else { return }
                if let result, result.isFinal {
                    didResume = true
                    continuation.resume(returning: result.bestTranscription.formattedString)
                } else if let error {
                    didResume = true
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func stopAndReset() {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        recordingFile = nil
    }

    // MARK: - Safety-Net Recording File

    private static func newRecordingURL() -> URL {
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        return FileManager.default.temporaryDirectory.appendingPathComponent("voice-\(stamp).caf")
    }

    private static func pruneOldRecordings(keep: Int = 5) {
        let dir = FileManager.default.temporaryDirectory
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
        let recordings = files
            .filter { $0.lastPathComponent.hasPrefix("voice-") && $0.pathExtension == "caf" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent } // ISO8601 names sort newest-first
        for url in recordings.dropFirst(keep) {
            try? FileManager.default.removeItem(at: url)
        }
    }
}

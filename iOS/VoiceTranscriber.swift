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
//
// Session lifecycle, and why it is strict about it. Four ways a session used to end
// without the sheet noticing, each of which read as "voice input is flaky":
//   1. Stop tapped, then Resume before the old task's final callback landed: the late
//      final appended its text a second time and started a fresh task on a tap that no
//      longer existed. Stop now bumps `generation` once it has read the text, so a late
//      callback is ignored, and it waits (capped) for that final instead of a fixed 350ms.
//   2. A phone call, Siri, or another app taking the microphone: the engine stopped, the
//      state stayed `.recording`, the meter froze, nothing ever arrived again. Interruption
//      and route-change notifications now end or restart the session explicitly.
//   3. A recognizer that fails on every start (no network for the server path, a locale
//      with no model): the old code restarted it forever, which from the outside looked
//      exactly like listening. Fast repeated failures now surface as `.error`.
//   4. SFSpeechRecognizer(locale:) returning nil for the phone's locale: every optional
//      chain silently did nothing. The recognizer now falls back to en-US and reports
//      which engine (on-device or Apple's servers) is actually doing the work.
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
    /// Which engine the words come from. Shown in the sheet so a flaky session can be
    /// told apart from a flaky network: on-device recognition never needs the network,
    /// Apple's servers do, and they cap one request at about a minute.
    public var recognitionMode: String {
        guard let speechRecognizer else { return "Speech recognition is not available on this phone." }
        let locale = speechRecognizer.locale.identifier
        return speechRecognizer.supportsOnDeviceRecognition
            ? "On-device recognition · \(locale)"
            : "Apple server recognition · \(locale) · needs network"
    }

    /// The phone's locale first, en-US when Speech has no recognizer for it at all. A nil
    /// recognizer used to mean every optional chain below silently did nothing: the sheet
    /// sat on "Listening…" with the meter moving and not one word arriving.
    private let speechRecognizer: SFSpeechRecognizer? =
        SFSpeechRecognizer(locale: Locale.current) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    private var audioSampleRate: Double = 16000.0
    private var recordingFile: AVAudioFile?

    private var segments = VoiceSegments()
    private var partialText: String = ""
    /// Bumped on every fresh `startRecording()`/`resumeRecording()`/`cancelRecording()`
    /// and at the end of `stopRecording()`, so a completion callback from an already
    /// torn-down task can never mutate the session that replaced it.
    private var generation = 0
    /// True from the moment `stopRecording()` begins until it finishes reading the
    /// final text. A task's completion callback arriving in that window should still
    /// commit its text — otherwise the last few words of a segment get lost — but must
    /// not restart a new request; `stopRecording()` owns what happens next.
    private var isStoppingSession = false
    /// Set by the live task's final callback; `stopRecording()` waits on it.
    private var liveTaskFinished = false
    /// When the live task started, for telling a normal silence-ended task (seconds
    /// long) from a recognizer that dies the moment it starts.
    private var taskStartedAt = Date.distantPast
    private var quickFailures = 0
    private static let maxQuickFailures = 5
    /// When the engine session started; a configuration-change notification inside the
    /// first half second is our own setup, not a route change worth restarting for.
    private var sessionStartedAt = Date.distantPast
    /// An interruption ended our session; resume when the system says the other party
    /// is done, unless the sheet has gone away meanwhile.
    private var resumeAfterInterruption = false

    public override init() {
        super.init()
        let center = NotificationCenter.default
        center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            let type = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt)
                .flatMap(AVAudioSession.InterruptionType.init(rawValue:))
            let options = AVAudioSession.InterruptionOptions(
                rawValue: note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0)
            Task { @MainActor [weak self] in await self?.handleInterruption(type: type, options: options) }
        }
        center.addObserver(forName: .AVAudioEngineConfigurationChange, object: audioEngine, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.handleConfigurationChange() }
        }
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
        generation += 1
        let mine = generation
        // The permission prompts are real awaits: if the sheet was dismissed while they
        // were up, `cancelRecording()` has moved on and this session must not start.
        guard await requestPermissions(), mine == generation else { return }
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
        generation += 1
        let mine = generation
        guard await requestPermissions(), mine == generation else { return }
        stopAndReset()
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

        // Wait for the in-flight task's final callback so its last words commit. It
        // usually lands well under half a second; the cap keeps a stalled server request
        // from holding the sheet on "Stopping…".
        let deadline = ContinuousClock.now + .seconds(2)
        while recognitionTask != nil, !liveTaskFinished, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(40))
        }

        // From here on the old task is history: a final that arrives late used to append
        // its text a second time and start a fresh task on a tap that no longer existed.
        generation += 1
        isStoppingSession = false
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        recordingFile = nil // finalize the safety-net file for this segment

        let finalText = recognizedText.trimmingCharacters(in: .whitespacesAndNewlines)
        state = finalText.isEmpty ? .idle : .readyForReview(text: finalText)

        try? AVAudioSession.sharedInstance().setActive(false)
    }

    public func cancelRecording() {
        generation += 1
        isStoppingSession = false
        resumeAfterInterruption = false
        quickFailures = 0
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
        guard let speechRecognizer, speechRecognizer.isAvailable else {
            state = .error(message: "Speech recognition is not available right now (\(Locale.current.identifier)). Check the network, or enable Dictation for this language in Settings › General › Keyboard.")
            return
        }
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
            quickFailures = 0
            sessionStartedAt = Date()
            startRecognitionTask()

            // The meter only needs to move when the level actually moved: every buffer
            // (about 45 a second) used to hop to the main actor and redraw the sheet.
            var lastSentLevel: Float = -1
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
                guard abs(normalizedLevel - lastSentLevel) >= 0.03 else { return }
                lastSentLevel = normalizedLevel

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
        liveTaskFinished = false
        taskStartedAt = Date()

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

        liveTaskFinished = true
        let finalText = result?.bestTranscription.formattedString ?? partialText
        segments.append(final: finalText)
        partialText = ""

        // A task that ends on silence after a few seconds is normal. One that dies with
        // an error within a second of starting, five times running, is a recognizer that
        // cannot work right now (no network on the server path, no model for the locale).
        let endedEmpty = finalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if endedEmpty, error != nil, Date().timeIntervalSince(taskStartedAt) < 1 {
            quickFailures += 1
        } else {
            quickFailures = 0
        }

        guard !isStoppingSession, case .recording(let level, _) = state else { return }
        if quickFailures >= Self.maxQuickFailures, let error {
            generation += 1
            stopAndReset()
            state = .error(message: "Speech recognition keeps failing: \(error.localizedDescription)")
            return
        }
        state = .recording(audioLevel: level, partialText: "")
        startRecognitionTask()
    }

    // MARK: - System Events

    /// A phone call, Siri, or another app taking the microphone stops the engine under
    /// us. End the session the same way Stop does so the sheet shows Resume with the
    /// text intact; when the system says the interruption is over, pick up again.
    private func handleInterruption(type: AVAudioSession.InterruptionType?, options: AVAudioSession.InterruptionOptions) async {
        switch type {
        case .began:
            guard case .recording = state else { return }
            await stopRecording()
            resumeAfterInterruption = true
        case .ended:
            guard resumeAfterInterruption else { return }
            resumeAfterInterruption = false
            if options.contains(.shouldResume) {
                await resumeRecording(withText: recognizedText)
            }
        default:
            return
        }
    }

    /// The engine's input format changed (AirPods came or went, a call re-routed audio)
    /// and the engine stopped itself. Keep everything recognized so far and start a fresh
    /// tap in the new format.
    private func handleConfigurationChange() async {
        guard case .recording = state, !isStoppingSession, !audioEngine.isRunning,
              Date().timeIntervalSince(sessionStartedAt) > 0.5 else { return }
        generation += 1
        stopAndReset()
        segments.append(final: partialText)
        partialText = ""
        await beginEngineSession()
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

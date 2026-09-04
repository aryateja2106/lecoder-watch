// VoiceTranscriber — on-device speech to text for the chat composer.
//
// Apple's recognizer with requiresOnDeviceRecognition, an AVAudioEngine tap for both the
// recognition buffer and the level meter, and a state machine the sheet renders. Nothing
// leaves the phone. An earlier draft also posted audio to a "Nemotron server" on the Mac at
// a port and route that do not exist; that path was removed rather than ported.
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
    public var recognizedText: String = ""

    private let speechRecognizer = SFSpeechRecognizer(locale: Locale.current)
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    private var audioSampleRate: Double = 16000.0

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

    public func startRecording() async {
        guard await requestPermissions() else { return }

        // Reset state
        stopAndReset()
        recognizedText = ""

        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

            recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
            guard let recognitionRequest = recognitionRequest else {
                state = .error(message: "Unable to allocate speech request.")
                return
            }

            // On-device offline execution: zero battery/cloud waste
            if #available(iOS 13.0, *), speechRecognizer?.supportsOnDeviceRecognition == true {
                recognitionRequest.requiresOnDeviceRecognition = true
            }
            recognitionRequest.shouldReportPartialResults = true

            let inputNode = audioEngine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)
            audioSampleRate = recordingFormat.sampleRate

            recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
                guard let self = self else { return }
                Task { @MainActor in
                    if let result = result {
                        let text = result.bestTranscription.formattedString
                        self.recognizedText = text
                        if case .recording(let level, _) = self.state {
                            self.state = .recording(audioLevel: level, partialText: text)
                        }
                    }

                    if error != nil || result?.isFinal == true {
                        // Handled when user stops
                    }
                }
            }

            // Install audio tap for metering and recognition buffer
            inputNode.removeTap(onBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
                guard let self = self else { return }

                // Pass buffer to speech recognizer
                self.recognitionRequest?.append(buffer)

                // Calculate audio level (RMS power)
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
                    if case .recording(_, let text) = self.state {
                        self.state = .recording(audioLevel: normalizedLevel, partialText: text)
                    }
                }
            }

            audioEngine.prepare()
            try audioEngine.start()
            state = .recording(audioLevel: 0.0, partialText: "")

        } catch {
            state = .error(message: "Audio engine error: \(error.localizedDescription)")
            stopAndReset()
        }
    }

    public func stopRecording() async {
        guard case .recording = state else { return }

        state = .processing
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()

        // Allow final transcription to settle
        try? await Task.sleep(for: .milliseconds(350))

        let finalText = recognizedText.trimmingCharacters(in: .whitespacesAndNewlines)
        if finalText.isEmpty {
            state = .idle
        } else {
            state = .readyForReview(text: finalText)
        }

        try? AVAudioSession.sharedInstance().setActive(false)
    }

    public func cancelRecording() {
        stopAndReset()
        state = .idle
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
    }
}

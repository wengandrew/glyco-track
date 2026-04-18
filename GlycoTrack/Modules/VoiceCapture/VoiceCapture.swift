import Foundation
import Speech
import AVFoundation

enum VoiceCaptureError: Error, LocalizedError {
    case notAuthorized
    case recognizerUnavailable
    case audioEngineFailure(Error)

    var errorDescription: String? {
        switch self {
        case .notAuthorized: return "Speech recognition not authorized. Please enable in Settings."
        case .recognizerUnavailable: return "Speech recognizer is not available on this device."
        case .audioEngineFailure(let err): return "Audio engine error: \(err.localizedDescription)"
        }
    }
}

@MainActor
final class VoiceCapture: ObservableObject {
    @Published var isRecording: Bool = false
    @Published var transcript: String = ""
    @Published var error: VoiceCaptureError?

    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let recognizer: SFSpeechRecognizer?

    private var silenceTimer: Timer?
    private let silenceThreshold: TimeInterval = 2.0

    var onTranscriptFinalized: ((String) -> Void)?

    init() {
        self.recognizer = SFSpeechRecognizer(locale: .current)
    }

    func requestAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    func startRecording() async throws {
        guard let recognizer, recognizer.isAvailable else {
            throw VoiceCaptureError.recognizerUnavailable
        }

        let authorized = await requestAuthorization()
        guard authorized else {
            throw VoiceCaptureError.notAuthorized
        }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let engine = AVAudioEngine()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = false

        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            request.append(buffer)
            self?.resetSilenceTimer()
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            throw VoiceCaptureError.audioEngineFailure(error)
        }

        self.audioEngine = engine
        self.recognitionRequest = request

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            Task { @MainActor in
                if let result {
                    self.transcript = result.bestTranscription.formattedString
                }
                if error != nil || result?.isFinal == true {
                    self.stopRecording()
                }
            }
        }

        isRecording = true
        resetSilenceTimer()
    }

    func stopRecording() {
        silenceTimer?.invalidate()
        silenceTimer = nil

        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()

        audioEngine = nil
        recognitionRequest = nil
        recognitionTask = nil

        try? AVAudioSession.sharedInstance().setActive(false)
        isRecording = false

        let finalTranscript = transcript
        if !finalTranscript.isEmpty {
            onTranscriptFinalized?(finalTranscript)
        }
    }

    private func resetSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: silenceThreshold, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.stopRecording()
            }
        }
    }
}

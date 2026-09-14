import AVFoundation
import Speech

enum LocalVoiceCaptureError: LocalizedError {
    case unavailable, speechPermission, microphonePermission, microphoneUnavailable, captureFailed
    var errorDescription: String? {
        switch self {
        case .unavailable: "On-device speech is unavailable for your language on this Mac. You can keep typing; no online fallback is used."
        case .speechPermission: "Speech recognition access is unavailable. You can review ARCHi's access in System Settings or keep typing."
        case .microphonePermission: "Microphone access is unavailable. You can review ARCHi's access in System Settings or keep typing."
        case .microphoneUnavailable: "No usable microphone is available. Connect one or keep typing."
        case .captureFailed: "Local dictation stopped. Your typed draft is unchanged; click Dictate to try again."
        }
    }
}

/// This adapter has no provider, file-writing or model-download path. Audio
/// buffers go directly to an explicitly on-device Apple recognition request.
@MainActor
final class AppleVoiceCaptureService: VoiceCaptureService {
    private var generation = UUID()
    private let authorization: any VoiceCaptureAuthorization
    private let sessionFactory: @MainActor () -> (any OnDeviceSpeechSession)?
    private var session: (any OnDeviceSpeechSession)?

    init(authorization: any VoiceCaptureAuthorization = AppleVoiceAuthorization(),
         sessionFactory: @escaping @MainActor () -> (any OnDeviceSpeechSession)? = { AppleOnDeviceSpeechSession() }) {
        self.authorization = authorization
        self.sessionFactory = sessionFactory
    }

    func start(onEvent: @escaping @MainActor (VoiceCaptureEvent) -> Void) async throws {
        cancel()
        let token = generation
        let speechAuthorized = await authorization.speechAuthorized()
        try requireCurrent(token)
        guard speechAuthorized else { throw LocalVoiceCaptureError.speechPermission }
        guard let session = sessionFactory(), session.supportsOnDeviceRecognition, session.isAvailable else {
            throw LocalVoiceCaptureError.unavailable
        }
        let microphoneGranted = await authorization.microphoneAuthorized()
        try requireCurrent(token)
        guard microphoneGranted else { throw LocalVoiceCaptureError.microphonePermission }
        // The capability can change while a system permission prompt is open.
        guard session.supportsOnDeviceRecognition, session.isAvailable else { throw LocalVoiceCaptureError.unavailable }
        self.session = session
        do {
            try session.start { [weak self] event in
                guard self?.generation == token else { return }
                onEvent(event)
            }
        } catch { cancel(); throw error }
    }

    func finish() { session?.finish() }
    func cancel() {
        generation = UUID()
        session?.cancel()
        session = nil
    }
    private func requireCurrent(_ token: UUID) throws {
        guard token == generation, !Task.isCancelled else { throw CancellationError() }
    }
}

@MainActor
protocol VoiceCaptureAuthorization {
    func speechAuthorized() async -> Bool
    func microphoneAuthorized() async -> Bool
}

@MainActor
protocol OnDeviceSpeechSession: AnyObject {
    var supportsOnDeviceRecognition: Bool { get }
    var isAvailable: Bool { get }
    func start(onEvent: @escaping @MainActor (VoiceCaptureEvent) -> Void) throws
    func finish()
    func cancel()
}

@MainActor
final class AppleOnDeviceSpeechSession: OnDeviceSpeechSession {
    private let recognizer: SFSpeechRecognizer
    private var generation = UUID()
    private var engine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognition: SFSpeechRecognitionTask?
    private var tapInstalled = false

    var supportsOnDeviceRecognition: Bool { recognizer.supportsOnDeviceRecognition }
    var isAvailable: Bool { recognizer.isAvailable }

    init?() {
        guard let recognizer = SFSpeechRecognizer(locale: Locale.current) else { return nil }
        self.recognizer = recognizer
    }

    func start(onEvent: @escaping @MainActor (VoiceCaptureEvent) -> Void) throws {
        cancel()
        let token = generation
        guard recognizer.supportsOnDeviceRecognition, recognizer.isAvailable else {
            throw LocalVoiceCaptureError.unavailable
        }
        let request = Self.localRecognitionRequest()
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate.isFinite, format.sampleRate > 0, format.channelCount > 0 else {
            throw LocalVoiceCaptureError.microphoneUnavailable
        }
        self.engine = engine
        self.request = request
        recognition = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let final = result?.isFinal ?? false
            let failed = error != nil
            Task { @MainActor [weak self] in
                guard let self, self.generation == token else { return }
                if final, let text { onEvent(.final(text)) }
                else if failed { onEvent(.failed(LocalVoiceCaptureError.captureFailed.errorDescription!)) }
                else if let text { onEvent(.partial(text)) }
            }
        }
        input.installTap(onBus: 0, bufferSize: 1_024, format: format) { buffer, _ in request.append(buffer) }
        tapInstalled = true
        do {
            engine.prepare()
            try engine.start()
        } catch {
            cancel()
            throw LocalVoiceCaptureError.captureFailed
        }
    }

    func finish() {
        stopAudio()
        request?.endAudio()
    }

    func cancel() {
        generation = UUID()
        stopAudio()
        request?.endAudio()
        recognition?.cancel()
        recognition = nil
        request = nil
    }

    private func stopAudio() {
        if tapInstalled { engine?.inputNode.removeTap(onBus: 0); tapInstalled = false }
        engine?.stop()
        engine = nil
    }

    static func localRecognitionRequest() -> SFSpeechAudioBufferRecognitionRequest {
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        request.taskHint = .dictation
        return request
    }

}

@MainActor
struct AppleVoiceAuthorization: VoiceCaptureAuthorization {
    func speechAuthorized() async -> Bool {
        let current = SFSpeechRecognizer.authorizationStatus()
        guard current == .notDetermined else { return current == .authorized }
        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
        }
    }

    func microphoneAuthorized() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { continuation.resume(returning: $0) }
            }
        default: return false
        }
    }
}

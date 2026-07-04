import AVFoundation
import Foundation

@MainActor
final class AudioRecorder: NSObject, ObservableObject {
    static let levelHistoryCapacity = 80

    @Published private(set) var isRecording = false
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var level: Double = 0
    /// 최근 레벨 히스토리(시간순, 마지막이 최신). 파형이 실제 소리를 따라 흐르게 하는 소스.
    @Published private(set) var levelHistory: [Double] = Array(repeating: 0, count: levelHistoryCapacity)
    @Published private(set) var liveTranscript = ""
    @Published var errorMessage: String?

    private var engine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private var liveSpeech: LiveSpeechTranscriptionSession?
    private var startedAt: Date?
    private var currentURL: URL?
    private var meterTimer: Timer?
    private var latestBufferLevel: Double = 0
    private var didFailDuringRecording = false
    private let fileManager = FileManager.default

    func start(outputURL: URL) async {
        guard !isRecording else {
            return
        }

        let granted = await requestMicrophoneAccess()
        guard granted else {
            errorMessage = L10n.t("error.mic.permissionRequired", AppLanguage.current)
            return
        }

        do {
            try fileManager.createDirectory(
                at: outputURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            let liveSpeech = await LiveSpeechTranscriptionSession.make { [weak self] transcript in
                self?.liveTranscript = transcript
            }
            let engine = AVAudioEngine()
            let inputNode = engine.inputNode
            let inputFormat = inputNode.outputFormat(forBus: 0)
            let audioFile = try AVAudioFile(forWriting: outputURL, settings: inputFormat.settings)

            // @Sendable로 표시하지 않으면 클로저가 @MainActor 격리를 상속받아, AVFAudio가
            // 오디오 스레드에서 호출할 때 swift_task_checkIsolated가 트랩(SIGTRAP)을 낸다.
            // 메인 액터 상태 갱신은 nonisolated 헬퍼를 통해 hop한다.
            inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { @Sendable [weak self, weak liveSpeech] buffer, _ in
                var failure: String?
                do {
                    try audioFile.write(from: buffer)
                } catch {
                    failure = error.localizedDescription
                }

                liveSpeech?.append(buffer)

                let bufferLevel = Self.normalizedLevel(from: buffer)
                self?.ingestTapResult(level: bufferLevel, failure: failure)
            }

            engine.prepare()
            try engine.start()

            self.engine = engine
            self.audioFile = audioFile
            self.liveSpeech = liveSpeech
            currentURL = outputURL
            startedAt = Date()
            elapsed = 0
            level = 0
            levelHistory = Array(repeating: 0, count: Self.levelHistoryCapacity)
            latestBufferLevel = 0
            liveTranscript = ""
            didFailDuringRecording = false
            isRecording = true
            errorMessage = nil
            startMetering()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func stop() -> RecordedAudio? {
        guard isRecording, let engine, let startedAt, let currentURL else {
            return nil
        }

        stopMetering()
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()

        let duration = Date().timeIntervalSince(startedAt)
        let liveTranscript = liveSpeech?.finish(duration: duration)
        self.engine = nil
        self.audioFile = nil
        self.liveSpeech = nil
        self.startedAt = nil
        self.currentURL = nil
        isRecording = false
        elapsed = duration
        level = 0
        levelHistory = Array(repeating: 0, count: Self.levelHistoryCapacity)
        latestBufferLevel = 0

        if didFailDuringRecording {
            return nil
        }

        return RecordedAudio(
            url: currentURL,
            startedAt: startedAt,
            duration: duration,
            liveTranscript: liveTranscript
        )
    }

    // 실시간 오디오 스레드에서 호출된다. Sendable 값만 받아 메인 액터로 hop한다.
    nonisolated private func ingestTapResult(level: Double, failure: String?) {
        Task { @MainActor in
            self.latestBufferLevel = level
            if let failure {
                self.didFailDuringRecording = true
                self.errorMessage = failure
            }
        }
    }

    private func requestMicrophoneAccess() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    private func startMetering() {
        stopMetering()
        meterTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.engine != nil else {
                    return
                }

                // attack은 즉시, decay는 완만하게 — 파형이 뚝뚝 끊기지 않게.
                self.level = max(self.latestBufferLevel, self.level * 0.72)
                self.levelHistory.removeFirst()
                self.levelHistory.append(self.level)

                if let startedAt = self.startedAt {
                    self.elapsed = Date().timeIntervalSince(startedAt)
                }
            }
        }
    }

    private func stopMetering() {
        meterTimer?.invalidate()
        meterTimer = nil
    }

    nonisolated private static func normalizedLevel(from buffer: AVAudioPCMBuffer) -> Double {
        guard let channelData = buffer.floatChannelData,
              buffer.frameLength > 0 else {
            return 0
        }

        let channelCount = Int(buffer.format.channelCount)
        let frameLength = Int(buffer.frameLength)
        var sum: Float = 0

        for channel in 0..<channelCount {
            let samples = channelData[channel]
            for frame in 0..<frameLength {
                let sample = samples[frame]
                sum += sample * sample
            }
        }

        let meanSquare = sum / Float(max(1, frameLength * max(1, channelCount)))
        let rootMeanSquare = sqrt(meanSquare)
        return min(1, Double(rootMeanSquare) * 8)
    }
}

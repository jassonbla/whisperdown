import AVFoundation
import Foundation
import Speech

// 공유 가변 상태(latestText/latestResultWasFinal)는 `lock`으로 보호되고,
// request/task는 생성 이후 append/finish에서만 순차 접근하므로 스레드 안전하다.
final class LiveSpeechTranscriptionSession: @unchecked Sendable {
    private let request: SFSpeechAudioBufferRecognitionRequest
    private var task: SFSpeechRecognitionTask?
    private let lock = NSLock()
    private var latestText = ""
    private var latestResultWasFinal = false
    private let engineNote: String
    private let onUpdate: @MainActor (String) -> Void

    static func make(
        localeIdentifier: String = "ko_KR",
        onUpdate: @escaping @MainActor (String) -> Void
    ) async -> LiveSpeechTranscriptionSession? {
        let authorizationStatus = await requestSpeechAuthorization()
        guard authorizationStatus == .authorized,
              let recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeIdentifier)),
              recognizer.isAvailable else {
            return nil
        }

        return LiveSpeechTranscriptionSession(recognizer: recognizer, onUpdate: onUpdate)
    }

    private init(
        recognizer: SFSpeechRecognizer,
        onUpdate: @escaping @MainActor (String) -> Void
    ) {
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }

        self.request = request
        self.engineNote = recognizer.supportsOnDeviceRecognition
            ? "Apple Speech live ko-KR on-device"
            : "Apple Speech live ko-KR"
        self.onUpdate = onUpdate

        task = recognizer.recognitionTask(with: request) { [weak self] result, _ in
            guard let self, let result else {
                return
            }

            let text = result.bestTranscription.formattedString
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                return
            }

            self.lock.lock()
            self.latestText = text
            self.latestResultWasFinal = result.isFinal
            self.lock.unlock()

            Task { @MainActor in
                self.onUpdate(text)
            }
        }
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        request.append(buffer)
    }

    func finish(duration: TimeInterval) -> TranscriptResult? {
        request.endAudio()
        task?.cancel()
        task = nil

        lock.lock()
        let text = latestText
        let wasFinal = latestResultWasFinal
        lock.unlock()

        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            return nil
        }

        return TranscriptResult(
            text: trimmedText,
            segments: [
                SpeakerSegment(
                    speaker: "Speaker 1",
                    startTime: 0,
                    endTime: duration,
                    text: trimmedText
                )
            ],
            engineNote: "\(engineNote)\(wasFinal ? "" : " draft")"
        )
    }

    private static func requestSpeechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }
}

import Foundation
import Speech

struct AppleSpeechTranscriptionEngine: Sendable {
    /// SFTranscription(비-Sendable 클래스)을 actor 경계 밖으로 내보내지 않기 위한 값 스냅샷
    private struct RecognizedTranscript: Sendable {
        let formattedString: String
        let lastSegmentEnd: TimeInterval?
    }

    func transcribe(
        audio: RecordedAudio,
        onStageChange: @MainActor @Sendable (TranscriptionStage) -> Void = { _ in }
    ) async throws -> TranscriptResult {
        await onStageChange(.converting)

        let authorizationStatus = await requestSpeechAuthorization()
        guard authorizationStatus == .authorized else {
            throw AppleSpeechTranscriptionError.speechRecognitionNotAuthorized
        }

        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ko_KR")) else {
            throw AppleSpeechTranscriptionError.recognizerUnavailable
        }

        guard recognizer.isAvailable else {
            throw AppleSpeechTranscriptionError.recognizerUnavailable
        }

        await onStageChange(.transcribing)

        let transcription = try await recognize(audioURL: audio.url, recognizer: recognizer)
        let text = transcription.formattedString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw AppleSpeechTranscriptionError.emptyTranscript
        }

        await onStageChange(.finalizing)

        let segmentEnd = max(audio.duration, transcription.lastSegmentEnd ?? audio.duration)

        return TranscriptResult(
            text: text,
            segments: [
                SpeakerSegment(
                    speaker: "Speaker 1",
                    startTime: 0,
                    endTime: segmentEnd,
                    text: text
                )
            ],
            engineNote: "Apple Speech ko-KR"
        )
    }

    private func requestSpeechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }

    private func recognize(audioURL: URL, recognizer: SFSpeechRecognizer) async throws -> RecognizedTranscript {
        try await withCheckedThrowingContinuation { continuation in
            let request = SFSpeechURLRecognitionRequest(url: audioURL)
            request.shouldReportPartialResults = false
            if recognizer.supportsOnDeviceRecognition {
                request.requiresOnDeviceRecognition = true
            }

            var didResume = false
            var task: SFSpeechRecognitionTask?
            task = recognizer.recognitionTask(with: request) { result, error in
                if let result, result.isFinal {
                    guard !didResume else {
                        return
                    }
                    didResume = true
                    task?.cancel()
                    let best = result.bestTranscription
                    let recognized = RecognizedTranscript(
                        formattedString: best.formattedString,
                        lastSegmentEnd: best.segments.last.map { $0.timestamp + $0.duration }
                    )
                    continuation.resume(returning: recognized)
                    return
                }

                if let error {
                    guard !didResume else {
                        return
                    }
                    didResume = true
                    task?.cancel()
                    continuation.resume(throwing: AppleSpeechTranscriptionError.recognitionFailed(error.localizedDescription))
                }
            }
        }
    }
}

enum AppleSpeechTranscriptionError: LocalizedError {
    case speechRecognitionNotAuthorized
    case recognizerUnavailable
    case emptyTranscript
    case recognitionFailed(String)

    var errorDescription: String? {
        switch self {
        case .speechRecognitionNotAuthorized:
            return "음성 인식 권한이 없어 전사를 실행하지 못했습니다."
        case .recognizerUnavailable:
            return "한국어 음성 인식 엔진을 사용할 수 없습니다."
        case .emptyTranscript:
            return "전사 결과가 비어 있습니다. 마이크 입력 또는 음성 크기를 확인해 주세요."
        case .recognitionFailed(let message):
            return "전사 실패: \(message)"
        }
    }
}

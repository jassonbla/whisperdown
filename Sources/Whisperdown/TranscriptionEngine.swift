import Foundation

struct TranscriptionEngine: Sendable {
    private let whisper = WhisperCppTranscriptionEngine()
    private let appleSpeech = AppleSpeechTranscriptionEngine()

    func transcribe(
        audio: RecordedAudio,
        onStageChange: @MainActor @Sendable (TranscriptionStage) -> Void = { _ in },
        onProgress: @escaping @MainActor @Sendable (Double) -> Void = { _ in },
        onActivity: @escaping @MainActor @Sendable (TranscriptionActivity) -> Void = { _ in },
        onPartialText: @escaping @MainActor @Sendable (String) -> Void = { _ in },
        onDiarization: @escaping @MainActor @Sendable (DiarizationStepState) -> Void = { _ in }
    ) async throws -> TranscriptResult {
        if whisper.isConfigured {
            return try await whisper.transcribe(
                audio: audio,
                onStageChange: onStageChange,
                onProgress: onProgress,
                onActivity: onActivity,
                onPartialText: onPartialText,
                onDiarization: onDiarization
            )
        }

        // 폴백 이중화: macOS 26+는 신형 SpeechAnalyzer(장문 특화, 실측 47분→16.7초) 우선,
        // 어떤 이유로든 실패하면 구형 SFSpeechRecognizer 경로로 조용히 내려간다.
        if #available(macOS 26.0, *) {
            do {
                var result = try await SpeechAnalyzerTranscriptionEngine()
                    .transcribe(audio: audio, onStageChange: onStageChange)
                result.engineNote = "\(result.engineNote) fallback. whisper.cpp is not configured."
                return result
            } catch {
                // 구형 경로로 계속
            }
        }

        do {
            var result = try await appleSpeech.transcribe(audio: audio, onStageChange: onStageChange)
            result.engineNote = "\(result.engineNote) fallback. whisper.cpp is not configured."
            return result
        } catch {
            throw TranscriptionEngineError.whisperNotConfiguredAndFallbackFailed(error.localizedDescription)
        }
    }
}

enum TranscriptionEngineError: LocalizedError {
    case whisperNotConfiguredAndFallbackFailed(String)

    var errorDescription: String? {
        switch self {
        case .whisperNotConfiguredAndFallbackFailed(let fallbackError):
            return """
            whisper.cpp가 아직 설정되지 않았고 Apple Speech fallback도 실패했습니다.

            whisper.cpp 설치 후 모델 파일을 ~/Library/Application Support/Whisperdown/Models/ 에 넣어 주세요.

            Apple Speech 오류: \(fallbackError)
            """
        }
    }
}

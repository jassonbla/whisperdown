import Foundation

struct TranscriptionEngine: Sendable {
    private let whisper = WhisperCppTranscriptionEngine()
    private let appleSpeech = AppleSpeechTranscriptionEngine()

    func transcribe(audio: RecordedAudio) async throws -> TranscriptResult {
        if whisper.isConfigured {
            return try await whisper.transcribe(audio: audio)
        }

        do {
            var result = try await appleSpeech.transcribe(audio: audio)
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

            whisper.cpp 설치 후 모델 파일을 ~/Library/Application Support/Voice to Markdown/Models/ 에 넣어 주세요.

            Apple Speech 오류: \(fallbackError)
            """
        }
    }
}

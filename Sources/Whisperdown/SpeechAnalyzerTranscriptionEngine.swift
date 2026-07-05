import Foundation
import Speech
import AVFoundation

enum SpeechAnalyzerError: LocalizedError {
    case localeNotInstalled
    case emptyTranscript
    case analysisFailed(String)

    var errorDescription: String? {
        switch self {
        case .localeNotInstalled:
            return L10n.t("error.engine.speechAnalyzer.localeNotInstalled", AppLanguage.current)
        case .emptyTranscript:
            return L10n.t("error.engine.speechAnalyzer.empty", AppLanguage.current)
        case .analysisFailed(let message):
            return String(format: L10n.t("error.engine.speechAnalyzer.failed", AppLanguage.current), message)
        }
    }
}

/// macOS 26의 SpeechAnalyzer/SpeechTranscriber 기반 폴백 전사 엔진 —
/// 구형 SFSpeechRecognizer의 후속(장문 특화, 실측: 47분 m4a를 16.7초에 전사).
/// FoundationModelsSummarizer와 같은 격리 규율: 26+ 타입은 이 파일 밖으로 새지 않고,
/// 파사드가 `if #available`로 선택하며 실패 시 구형 엔진으로 이중 폴백한다.
@available(macOS 26.0, *)
struct SpeechAnalyzerTranscriptionEngine: Sendable {
    func transcribe(
        audio: RecordedAudio,
        onStageChange: @MainActor @Sendable (TranscriptionStage) -> Void
    ) async throws -> TranscriptResult {
        await onStageChange(.converting)

        let locale = Locale(identifier: "ko_KR")
        let installed = await SpeechTranscriber.installedLocales
        guard installed.contains(where: { $0.identifier(.bcp47) == locale.identifier(.bcp47) }) else {
            throw SpeechAnalyzerError.localeNotInstalled
        }

        await onStageChange(.transcribing)

        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [],
            attributeOptions: [.audioTimeRange]
        )
        let analyzer = SpeechAnalyzer(modules: [transcriber])

        do {
            let file = try AVAudioFile(forReading: audio.url)

            // 결과 수집을 분석과 병행 — results 스트림은 finalizeAndFinish 후 종료된다.
            let collector = Task {
                var collected: [(text: String, start: TimeInterval?, end: TimeInterval?)] = []
                for try await result in transcriber.results {
                    let text = String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { continue }

                    var start: TimeInterval?
                    var end: TimeInterval?
                    for run in result.text.runs {
                        guard let range = run.audioTimeRange else { continue }
                        let runStart = range.start.seconds
                        let runEnd = range.end.seconds
                        start = min(start ?? runStart, runStart)
                        end = max(end ?? runEnd, runEnd)
                    }
                    collected.append((text, start, end))
                }
                return collected
            }

            if let last = try await analyzer.analyzeSequence(from: file) {
                try await analyzer.finalizeAndFinish(through: last)
            } else {
                await analyzer.cancelAndFinishNow()
            }

            let results = try await collector.value

            await onStageChange(.finalizing)

            guard !results.isEmpty else {
                throw SpeechAnalyzerError.emptyTranscript
            }

            // 결과 단위 세그먼트 — 구형 폴백의 통짜 1세그먼트와 달리 문단화를 공짜로 얻는다.
            var segments: [SpeakerSegment] = []
            var cursor: TimeInterval = 0
            for result in results {
                let start = result.start ?? cursor
                let end = max(result.end ?? start, start)
                segments.append(SpeakerSegment(
                    speaker: "Speaker 1",
                    startTime: start,
                    endTime: end,
                    text: result.text
                ))
                cursor = end
            }

            let text = results.map(\.text).joined(separator: " ")
            return TranscriptResult(
                text: text,
                segments: segments,
                engineNote: "Apple SpeechAnalyzer ko-KR on-device"
            )
        } catch let error as SpeechAnalyzerError {
            throw error
        } catch {
            throw SpeechAnalyzerError.analysisFailed(String(error.localizedDescription.prefix(200)))
        }
    }
}

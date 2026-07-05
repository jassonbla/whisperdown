import Foundation

struct WhisperCppTranscriptionEngine: Sendable {
    private var fileManager: FileManager { .default }

    var isConfigured: Bool {
        executableURL != nil && modelURL != nil && ffmpegURL != nil
    }

    /// 구성 요소별 상태 스냅샷. 매 호출마다 파일시스템을 재검사하므로
    /// 모델 다운로드/설치 완료 직후에도 최신 상태를 반환한다.
    func status() -> EngineStatus {
        EngineStatus(
            whisperCLI: executableURL.map(EngineStatus.Item.found) ?? .missing,
            ffmpeg: ffmpegURL.map(EngineStatus.Item.found) ?? .missing,
            model: modelURL.map(EngineStatus.Item.found) ?? .missing
        )
    }

    func transcribe(
        audio: RecordedAudio,
        onStageChange: @MainActor @Sendable (TranscriptionStage) -> Void = { _ in },
        onProgress: @escaping @MainActor @Sendable (Double) -> Void = { _ in },
        onActivity: @escaping @MainActor @Sendable (TranscriptionActivity) -> Void = { _ in },
        onPartialText: @escaping @MainActor @Sendable (String) -> Void = { _ in },
        onDiarization: @escaping @MainActor @Sendable (DiarizationStepState) -> Void = { _ in }
    ) async throws -> TranscriptResult {
        guard let executableURL else {
            throw WhisperCppError.executableMissing
        }

        guard let modelURL else {
            throw WhisperCppError.modelMissing(modelDirectory.path)
        }

        guard let ffmpegURL else {
            throw WhisperCppError.ffmpegMissing
        }

        let workingDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("Whisperdown-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
        defer {
            try? fileManager.removeItem(at: workingDirectory)
        }

        let wavURL = workingDirectory.appendingPathComponent("input.wav")
        let outputBaseURL = workingDirectory.appendingPathComponent("transcript")
        let outputTextURL = workingDirectory.appendingPathComponent("transcript.txt")
        let outputJSONURL = workingDirectory.appendingPathComponent("transcript.json")

        await onStageChange(.converting)

        try await ProcessRunner.run(
            executableURL: ffmpegURL,
            arguments: [
                "-y",
                "-nostdin",
                "-i", audio.url.path,
                "-ar", "16000",
                "-ac", "1",
                "-c:a", "pcm_s16le",
                wavURL.path
            ]
        )

        var whisperArguments = [
            "-m", modelURL.path,
            "-f", wavURL.path,
            "-l", "ko",
            "-otxt",
            "-oj",
            "-ojf",
            "-of", outputBaseURL.path,
            "-nt",
            "-pp"
        ]

        if usesGPU {
            // Metal 경로 하드닝 (47분 실녹음 실측): 기본 플래그의 GPU 디코드는 15분 지점부터
            // 반복 루프에 빠져 이후 32분을 통째로 날렸다 (동일 문장 1,389회). flash-attn을 꺼도
            // 재발했고, 엔트로피 임계값을 2.4→2.8로 올리자(반복=저엔트로피 출력 시 온도 폴백 강제)
            // 전 구간 무결 + 2회 재실행 바이트 동일. GPU는 이 플래그와 함께만 신뢰할 수 있다.
            whisperArguments.append(contentsOf: ["-et", "2.8"])
        } else {
            whisperArguments.append("--no-gpu")
        }

        // 화자 분리는 whisper와 같은 wav를 소비하므로 병렬 실행한다 (RTF ~0.05, 보통 먼저 끝남).
        // 어떤 실패도 전사를 깨지 않는다 — Task<..., Never> + 내부 catch로 조용히 폴백.
        let diarizer = SpeakerDiarizationEngine()
        var diarizationTask: Task<[SpeakerTurn]?, Never>?
        if diarizer.isConfigured {
            await onDiarization(.running)
            diarizationTask = Task {
                do {
                    let turns = try await diarizer.diarize(wavURL: wavURL)
                    let speakerCount = Set(turns.map(\.speakerIndex)).count
                    await onDiarization(.done(speakerCount: speakerCount))
                    return turns
                } catch {
                    await onDiarization(.skipped)
                    return nil
                }
            }
        }

        await onStageChange(.transcribing)
        await onActivity(.loadingModel)

        do {
            try await ProcessRunner.run(
                executableURL: executableURL,
                arguments: whisperArguments,
                onStderrLine: { line in
                    if line.hasPrefix("main: processing") {
                        Task { await onActivity(.analyzing) }
                        return
                    }
                    if let fraction = Self.parseProgressFraction(from: line) {
                        Task { await onProgress(fraction) }
                    }
                },
                onStdoutText: onPartialText
            )
        } catch {
            // defer가 워크디렉토리를 지우기 전에 사이드카 프로세스 종료를 보장
            diarizationTask?.cancel()
            _ = await diarizationTask?.value
            throw error
        }

        // 스테퍼 무결성 계약: .finalizing 발화 전에 diarization 터미널 상태를 해소한다.
        // 평시에는 이미 끝나 있어 즉시 통과; 60초 캡으로 행 걸림 방지.
        let turns = await Self.resolveTurns(diarizationTask, timeoutSeconds: 60, onTimeout: onDiarization)

        await onStageChange(.finalizing)

        let text = try String(contentsOf: outputTextURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !text.isEmpty else {
            throw WhisperCppError.emptyTranscript
        }

        let payload = (try? Data(contentsOf: outputJSONURL))
            .flatMap { try? JSONDecoder().decode(WhisperJSONOutput.self, from: $0) }

        try validateTranscript(text: text, audioDuration: audio.duration, payload: payload)

        var segments = [
            SpeakerSegment(
                speaker: "Speaker 1",
                startTime: 0,
                endTime: audio.duration,
                text: text
            )
        ]
        var engineNote = "whisper.cpp \(modelURL.lastPathComponent)\(usesGPU ? "" : " CPU safe mode")"

        if let turns,
           let payload,
           let merged = SpeakerTurnMerger.merge(turns: turns, tokens: payload.tokenTimings) {
            segments = merged
            let speakerCount = Set(merged.map(\.speaker)).count
            engineNote += " + diarization (\(speakerCount) speaker\(speakerCount == 1 ? "" : "s"))"
        }

        return TranscriptResult(text: text, segments: segments, engineNote: engineNote)
    }

    /// diarization Task를 타임아웃과 레이스시켜 해소한다. 타임아웃 시 취소 + .skipped 통지.
    private static func resolveTurns(
        _ task: Task<[SpeakerTurn]?, Never>?,
        timeoutSeconds: UInt64,
        onTimeout: @escaping @MainActor @Sendable (DiarizationStepState) -> Void
    ) async -> [SpeakerTurn]? {
        guard let task else {
            return nil
        }

        return await withTaskGroup(of: [SpeakerTurn]?.self) { group in
            group.addTask { await task.value }
            group.addTask {
                try? await Task.sleep(nanoseconds: timeoutSeconds * 1_000_000_000)
                return nil
            }

            let first = await group.next() ?? nil
            group.cancelAll()

            if first == nil {
                task.cancel()
                _ = await task.value
                await onTimeout(.skipped)
            }

            return first
        }
    }

    private var executableURL: URL? {
        firstExistingFile([
            environmentURL("WHISPERDOWN_WHISPER_CLI"),
            Bundle.main.url(forResource: "whisper-cli", withExtension: nil),
            URL(fileURLWithPath: "/opt/homebrew/bin/whisper-cli"),
            URL(fileURLWithPath: "/usr/local/bin/whisper-cli")
        ])
    }

    private var ffmpegURL: URL? {
        firstExistingFile([
            environmentURL("WHISPERDOWN_FFMPEG"),
            URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg"),
            URL(fileURLWithPath: "/usr/local/bin/ffmpeg"),
            URL(fileURLWithPath: "/usr/bin/ffmpeg")
        ])
    }

    private var modelURL: URL? {
        if let environmentModel = environmentURL("WHISPERDOWN_WHISPER_MODEL"),
           fileManager.fileExists(atPath: environmentModel.path) {
            return environmentModel
        }

        let preferredNames = [
            "ggml-large-v3-turbo.bin",
            "ggml-large-v3.bin",
            "ggml-medium.bin",
            "ggml-small.bin",
            "ggml-base.bin"
        ]

        for name in preferredNames {
            let candidate = modelDirectory.appendingPathComponent(name)
            if fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
        }

        guard let contents = try? fileManager.contentsOfDirectory(
            at: modelDirectory,
            includingPropertiesForKeys: nil
        ) else {
            return nil
        }

        return contents
            .filter { $0.pathExtension == "bin" && $0.lastPathComponent.hasPrefix("ggml-") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .first
    }

    private var usesGPU: Bool {
        let value = ProcessInfo.processInfo.environment["WHISPERDOWN_WHISPER_GPU"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        return ["1", "true", "yes", "on"].contains(value)
    }

    /// ggml 모델 보관 디렉토리. ModelDownloadManager의 다운로드 목적지와 공유.
    static var modelDirectory: URL {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)

        return appSupport
            .appendingPathComponent("Whisperdown", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
    }

    private var modelDirectory: URL {
        Self.modelDirectory
    }

    private func environmentURL(_ name: String) -> URL? {
        guard let value = ProcessInfo.processInfo.environment[name], !value.isEmpty else {
            return nil
        }

        return URL(fileURLWithPath: value)
    }

    private func firstExistingFile(_ urls: [URL?]) -> URL? {
        urls.compactMap(\.self).first { url in
            fileManager.fileExists(atPath: url.path)
        }
    }

    /// "whisper_print_progress_callback: progress =  42%" → 0.42
    /// 30초 미만 클립은 100%를 초과하는 값이 나올 수 있어 0...1로 클램프한다.
    static func parseProgressFraction(from line: String) -> Double? {
        guard line.hasPrefix("whisper_print_progress_callback:"),
              let match = line.firstMatch(of: #/progress\s*=\s*(\d+)%/#),
              let percent = Double(match.1) else {
            return nil
        }

        return min(max(percent, 0), 100) / 100
    }

    private func validateTranscript(text: String, audioDuration: TimeInterval, payload: WhisperJSONOutput?) throws {
        guard let payload else {
            return
        }

        let normalized = text
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if audioDuration <= 30, Self.commonHallucinations.contains(normalized) {
            throw WhisperCppError.lowConfidenceTranscript(text)
        }

        let contentTokens = payload.transcription
            .flatMap { $0.tokens ?? [] }
            .filter { token in
                let value = token.text.trimmingCharacters(in: .whitespacesAndNewlines)
                return !value.isEmpty && value != "[_EOT_]"
            }

        guard let firstProbability = contentTokens.first?.p else {
            return
        }

        if Self.commonHallucinations.contains(normalized), firstProbability < 0.2 {
            throw WhisperCppError.lowConfidenceTranscript(text)
        }
    }

    private static let commonHallucinations: Set<String> = [
        "시청해주셔서감사합니다.",
        "시청해주셔서감사합니다",
        "구독좋아요부탁드립니다.",
        "구독좋아요부탁드립니다"
    ]
}

private struct WhisperJSONOutput: Decodable {
    let transcription: [WhisperJSONSegment]

    /// 화자 병합용 토큰 타이밍 (offsets 없는 토큰은 제외)
    var tokenTimings: [WhisperTokenTiming] {
        transcription
            .flatMap { $0.tokens ?? [] }
            .compactMap { token in
                guard let offsets = token.offsets else {
                    return nil
                }
                return WhisperTokenTiming(text: token.text, fromMs: offsets.from, toMs: offsets.to)
            }
    }
}

private struct WhisperJSONSegment: Decodable {
    let tokens: [WhisperJSONToken]?
}

private struct WhisperJSONToken: Decodable {
    struct Offsets: Decodable {
        let from: Int   // 밀리초
        let to: Int
    }

    let text: String
    let p: Double?
    let offsets: Offsets?
}

enum WhisperCppError: LocalizedError {
    case executableMissing
    case modelMissing(String)
    case ffmpegMissing
    case emptyTranscript
    case lowConfidenceTranscript(String)
    case processLaunchFailed(String, String)
    case processFailed(String, String)

    var errorDescription: String? {
        switch self {
        case .executableMissing:
            return L10n.t("error.engine.executableMissing", AppLanguage.current)
        case .modelMissing(let directory):
            return String(format: L10n.t("error.engine.modelMissing", AppLanguage.current), directory)
        case .ffmpegMissing:
            return L10n.t("error.engine.ffmpegMissing", AppLanguage.current)
        case .emptyTranscript:
            return L10n.t("error.engine.emptyTranscript", AppLanguage.current)
        case .lowConfidenceTranscript(let text):
            return String(format: L10n.t("error.engine.lowConfidence", AppLanguage.current), text)
        case .processLaunchFailed(let executable, let message):
            return String(format: L10n.t("error.engine.processLaunchFailed", AppLanguage.current), executable, message)
        case .processFailed(let executable, let output):
            return String(format: L10n.t("error.engine.processFailed", AppLanguage.current), executable, output)
        }
    }
}

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
        onPartialText: @escaping @MainActor @Sendable (String) -> Void = { _ in }
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

        try await run(
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

        if !usesGPU {
            whisperArguments.append("--no-gpu")
        }

        await onStageChange(.transcribing)
        await onActivity(.loadingModel)

        try await run(
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

        await onStageChange(.finalizing)

        let text = try String(contentsOf: outputTextURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !text.isEmpty else {
            throw WhisperCppError.emptyTranscript
        }

        try validateTranscript(text: text, audioDuration: audio.duration, jsonURL: outputJSONURL)

        return TranscriptResult(
            text: text,
            segments: [
                SpeakerSegment(
                    speaker: "Speaker 1",
                    startTime: 0,
                    endTime: audio.duration,
                    text: text
                )
            ],
            engineNote: "whisper.cpp \(modelURL.lastPathComponent)\(usesGPU ? "" : " CPU safe mode")"
        )
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

    private func run(
        executableURL: URL,
        arguments: [String],
        onStderrLine: @escaping @Sendable (String) -> Void = { _ in },
        onStdoutText: (@MainActor @Sendable (String) -> Void)? = nil
    ) async throws {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.executableURL = executableURL
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        // 종료 상태만 전달. AsyncStream은 순회 전에 yield돼도 버퍼링하므로
        // run() 전에 핸들러를 걸고 뒤에서 await해도 안전하다.
        let terminationStatuses = AsyncStream<Int32> { continuation in
            process.terminationHandler = { finished in
                continuation.yield(finished.terminationStatus)
                continuation.finish()
            }
        }

        do {
            try process.run()
        } catch {
            throw WhisperCppError.processLaunchFailed(executableURL.path, error.localizedDescription)
        }

        // 두 파이프를 동시에 라인 단위로 드레인(파이프 버퍼 데드락 방지).
        // stderr 라인은 스트리밍 콜백에 전달하면서 에러 보고용 전체 캡처도 유지.
        let stderrTask = Task<String, Never> {
            var captured = ""
            do {
                for try await line in errorPipe.fileHandleForReading.bytes.lines {
                    onStderrLine(line)
                    captured += line + "\n"
                }
            } catch {}
            return captured
        }
        // stdout은 -np 제거 후 세그먼트 텍스트가 개행 없이 실시간 burst로 도착하므로
        // 라인 단위가 아닌 chunk 단위로 읽는다. readabilityHandler가 burst당 1회 호출돼
        // MainActor 홉이 자연스럽게 코얼레싱되고, 순차 await가 청크 순서를 보장한다.
        let stdoutHandle = outputPipe.fileHandleForReading
        let stdoutChunks = AsyncStream<Data> { continuation in
            stdoutHandle.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty {
                    handle.readabilityHandler = nil
                    continuation.finish()
                } else {
                    continuation.yield(data)
                }
            }
        }
        let stdoutTask = Task<String, Never> {
            var captured = ""
            var pending = Data()
            for await chunk in stdoutChunks {
                pending.append(chunk)
                let text = Self.consumeCompleteUTF8(&pending)
                guard !text.isEmpty else { continue }
                captured += text
                if let onStdoutText {
                    await onStdoutText(text)
                }
            }
            if !pending.isEmpty {
                captured += String(decoding: pending, as: UTF8.self)
            }
            return captured
        }

        var status: Int32 = -1
        for await value in terminationStatuses {
            status = value
        }

        let errorOutput = await stderrTask.value
        let output = await stdoutTask.value

        guard status == 0 else {
            throw WhisperCppError.processFailed(
                executableURL.lastPathComponent,
                output + errorOutput
            )
        }
    }

    /// pending에서 완결된 UTF-8 프리픽스만 디코드해 반환하고,
    /// 잘린 멀티바이트 꼬리(최대 3바이트)는 pending에 남긴다.
    static func consumeCompleteUTF8(_ pending: inout Data) -> String {
        guard !pending.isEmpty else {
            return ""
        }

        var holdback = 0
        let tail = [UInt8](pending.suffix(4))
        for (offset, byte) in tail.enumerated().reversed() {
            if byte & 0b1100_0000 == 0b1000_0000 {
                continue
            }
            let expected: Int
            switch byte {
            case 0x00..<0x80: expected = 1
            case 0xC0..<0xE0: expected = 2
            case 0xE0..<0xF0: expected = 3
            case 0xF0..<0xF8: expected = 4
            default:          expected = 1
            }
            let available = tail.count - offset
            if available < expected {
                holdback = available
            }
            break
        }

        let complete = pending.prefix(pending.count - holdback)
        let text = String(decoding: complete, as: UTF8.self)
        pending = Data(pending.suffix(holdback))
        return text
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

    private func validateTranscript(text: String, audioDuration: TimeInterval, jsonURL: URL) throws {
        guard let data = try? Data(contentsOf: jsonURL),
              let payload = try? JSONDecoder().decode(WhisperJSONOutput.self, from: data) else {
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
}

private struct WhisperJSONSegment: Decodable {
    let tokens: [WhisperJSONToken]?
}

private struct WhisperJSONToken: Decodable {
    let text: String
    let p: Double?
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

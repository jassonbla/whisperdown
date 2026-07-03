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

    func transcribe(audio: RecordedAudio) async throws -> TranscriptResult {
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
            .appendingPathComponent("VoiceToMarkdown-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
        defer {
            try? fileManager.removeItem(at: workingDirectory)
        }

        let wavURL = workingDirectory.appendingPathComponent("input.wav")
        let outputBaseURL = workingDirectory.appendingPathComponent("transcript")
        let outputTextURL = workingDirectory.appendingPathComponent("transcript.txt")
        let outputJSONURL = workingDirectory.appendingPathComponent("transcript.json")

        try await run(
            executableURL: ffmpegURL,
            arguments: [
                "-y",
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
            "-np"
        ]

        if !usesGPU {
            whisperArguments.append("--no-gpu")
        }

        try await run(executableURL: executableURL, arguments: whisperArguments)

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
            environmentURL("VOICE_TO_MARKDOWN_WHISPER_CLI"),
            Bundle.main.url(forResource: "whisper-cli", withExtension: nil),
            URL(fileURLWithPath: "/opt/homebrew/bin/whisper-cli"),
            URL(fileURLWithPath: "/usr/local/bin/whisper-cli")
        ])
    }

    private var ffmpegURL: URL? {
        firstExistingFile([
            environmentURL("VOICE_TO_MARKDOWN_FFMPEG"),
            URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg"),
            URL(fileURLWithPath: "/usr/local/bin/ffmpeg"),
            URL(fileURLWithPath: "/usr/bin/ffmpeg")
        ])
    }

    private var modelURL: URL? {
        if let environmentModel = environmentURL("VOICE_TO_MARKDOWN_WHISPER_MODEL"),
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
        let value = ProcessInfo.processInfo.environment["VOICE_TO_MARKDOWN_WHISPER_GPU"]?
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
            .appendingPathComponent("Voice to Markdown", isDirectory: true)
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

    private func run(executableURL: URL, arguments: [String]) async throws {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let outputPipe = Pipe()
            let errorPipe = Pipe()

            process.executableURL = executableURL
            process.arguments = arguments
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            process.terminationHandler = { process in
                let output = String(
                    data: outputPipe.fileHandleForReading.readDataToEndOfFile(),
                    encoding: .utf8
                ) ?? ""
                let errorOutput = String(
                    data: errorPipe.fileHandleForReading.readDataToEndOfFile(),
                    encoding: .utf8
                ) ?? ""

                if process.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    continuation.resume(
                        throwing: WhisperCppError.processFailed(
                            executableURL.lastPathComponent,
                            output + errorOutput
                        )
                    )
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: WhisperCppError.processLaunchFailed(executableURL.path, error.localizedDescription))
            }
        }
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
            return "whisper.cpp 실행 파일 whisper-cli를 찾지 못했습니다. Homebrew whisper-cpp를 설치하거나 VOICE_TO_MARKDOWN_WHISPER_CLI를 설정해 주세요."
        case .modelMissing(let directory):
            return "whisper.cpp 모델 파일을 찾지 못했습니다. ggml 모델을 \(directory)에 넣거나 VOICE_TO_MARKDOWN_WHISPER_MODEL을 설정해 주세요."
        case .ffmpegMissing:
            return "오디오 변환에 필요한 ffmpeg를 찾지 못했습니다."
        case .emptyTranscript:
            return "whisper.cpp 전사 결과가 비어 있습니다."
        case .lowConfidenceTranscript(let text):
            return "전사 결과 신뢰도가 낮아 완료 처리하지 않았습니다. 감지된 문구: \(text)"
        case .processLaunchFailed(let executable, let message):
            return "\(executable) 실행에 실패했습니다: \(message)"
        case .processFailed(let executable, let output):
            return "\(executable) 실행 중 오류가 발생했습니다: \(output)"
        }
    }
}

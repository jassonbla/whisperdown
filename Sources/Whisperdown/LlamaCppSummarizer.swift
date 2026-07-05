import Foundation

enum LlamaSummaryError: LocalizedError {
    case timeout
    case processFailed(String)

    var errorDescription: String? {
        switch self {
        case .timeout:
            return L10n.t("summary.error.timeout", AppLanguage.current)
        case .processFailed(let message):
            return String(format: L10n.t("summary.error.processFailed", AppLanguage.current), message)
        }
    }
}

/// llama.cpp 요약 사이드카의 설치 레이아웃/해석 체인 (SpeakerDiarizationEngine 미러).
/// bin/에 llama-cli와 dylib들이 형제로 놓인다 — 릴리스 tar.gz의 평면 디렉토리를 통째로 옮긴 것.
enum LlamaSummaryEngine {
    static var summaryDirectory: URL {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)

        return appSupport
            .appendingPathComponent("Whisperdown", isDirectory: true)
            .appendingPathComponent("Summary", isDirectory: true)
    }

    static var runtimeDirectory: URL {
        summaryDirectory.appendingPathComponent("llama.cpp", isDirectory: true)
    }

    static var modelsDirectory: URL {
        summaryDirectory.appendingPathComponent("Models", isDirectory: true)
    }

    static func uninstall() throws {
        try FileManager.default.removeItem(at: summaryDirectory)
    }

    static func removeModel(fileName: String) {
        try? FileManager.default.removeItem(at: modelsDirectory.appendingPathComponent(fileName))
    }

    static func availability(modelFileName: String?) -> SummaryAvailability {
        guard cliURL != nil else {
            return .modelUnavailable("llama-cli")
        }
        guard let modelFileName, modelURL(fileName: modelFileName) != nil else {
            return .modelUnavailable("model")
        }
        return .available
    }

    // MARK: 해석 체인 (env → 설치 경로 → 시스템 경로)

    /// 실측 확정: 최신 llama.cpp에서 llama-cli는 채팅 UI 전용(-no-cnv 제거, stdout에 배너/에코 오염).
    /// raw 완성은 llama-completion이 담당한다.
    static var cliURL: URL? {
        firstExistingFile([
            environmentURL("WHISPERDOWN_LLAMA_CLI"),
            runtimeDirectory.appendingPathComponent("bin/llama-completion"),
            URL(fileURLWithPath: "/opt/homebrew/bin/llama-completion"),
            URL(fileURLWithPath: "/usr/local/bin/llama-completion")
        ])
    }

    static func modelURL(fileName: String) -> URL? {
        firstExistingFile([
            environmentURL("WHISPERDOWN_SUMMARY_MODEL"),
            modelsDirectory.appendingPathComponent(fileName)
        ])
    }

    private static func environmentURL(_ name: String) -> URL? {
        guard let value = ProcessInfo.processInfo.environment[name], !value.isEmpty else {
            return nil
        }
        return URL(fileURLWithPath: value)
    }

    private static func firstExistingFile(_ urls: [URL?]) -> URL? {
        urls.compactMap(\.self).first { FileManager.default.fileExists(atPath: $0.path) }
    }
}

/// GGUF 로컬 모델 백엔드. 컨텍스트가 커서(128K+) 청크 분할이 필요 없다 —
/// contextCharBudget 60k는 3시간 회의 전사본도 단일 패스로 덮는다.
/// 호출마다 모델을 새로 로드한다(5~20초) — 백그라운드 요약이라 수용; llama-server 상주는 v2 후보.
struct LlamaCppSummaryBackend: SummaryBackend {
    let cliURL: URL
    let modelURL: URL

    var contextCharBudget: Int { 60_000 }
    var glossaryCharBudget: Int { 4_000 }

    /// 생성 캡 10분 — 대형 모델의 콜드 로드 + 긴 프리필을 감안한 보수적 상한.
    static let timeoutSeconds: UInt64 = 600

    func respond(instructions: String, prompt: String) async throws -> String {
        let cli = cliURL
        let model = modelURL

        // 실측 확정된 호출: raw Gemma 턴 포맷을 임시 파일로 전달(-f).
        // --jinja는 시작 시 챗 포맷 예시 렌더에 필요(없으면 abort). 생성 텍스트는 stdout, 로그는 stderr.
        let promptFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("Whisperdown-summary-\(UUID().uuidString).txt")
        let rawPrompt = "<start_of_turn>user\n\(instructions)\n\n\(prompt)<end_of_turn>\n<start_of_turn>model\n"
        try rawPrompt.write(to: promptFile, atomically: true, encoding: .utf8)
        defer {
            try? FileManager.default.removeItem(at: promptFile)
        }

        let output = try await Self.withTimeout(seconds: Self.timeoutSeconds) {
            do {
                return try await ProcessRunner.run(
                    executableURL: cli,
                    arguments: [
                        "-m", model.path,
                        "-f", promptFile.path,
                        "--jinja",
                        "--no-display-prompt",
                        "--temp", "0.2",
                        "-c", "65536",
                        "-n", "4096",
                        "--no-warmup"
                    ]
                )
            } catch let error as WhisperCppError {
                // ProcessRunner는 whisper 시절 에러 타입을 던진다 — 요약 문맥으로 리매핑.
                throw LlamaSummaryError.processFailed(Self.compactMessage(from: error))
            }
        }

        return Self.extractFinalAnswer(from: output.stdout)
    }

    /// Gemma 4는 thinking 모델 — stdout이 "<|channel>thought …사고 과정… <channel|>최종 답변" 형태다.
    /// 마지막 채널 마커 이후가 실제 답변이고, 사고 과정은 요약 품질에 기여하므로 억제하지 않고 잘라낸다.
    /// 마커가 없으면(비-thinking 모델) 전체를 그대로 쓴다. 말미의 "> EOF by user"는 stdin EOF 노이즈.
    static func extractFinalAnswer(from stdout: String) -> String {
        var text = stdout
        if let marker = text.range(of: "<channel|>", options: .backwards) {
            text = String(text[marker.upperBound...])
        }
        if let eof = text.range(of: "> EOF by user") {
            text = String(text[..<eof.lowerBound])
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// task.value vs sleep 레이스 (WhisperCppTranscriptionEngine.resolveTurns 패턴).
    /// 타임아웃 시 작업을 취소해 ProcessRunner의 onCancel이 프로세스를 종료하게 한다.
    private static func withTimeout<T: Sendable>(
        seconds: UInt64,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        let work = Task { try await operation() }

        let winner = await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                _ = try? await work.value
                return true
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: seconds * 1_000_000_000)
                return false
            }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }

        guard winner else {
            work.cancel()
            _ = try? await work.value
            throw LlamaSummaryError.timeout
        }

        return try await work.value
    }

    private static func compactMessage(from error: WhisperCppError) -> String {
        let text = error.localizedDescription
        return String(text.prefix(200))
    }
}

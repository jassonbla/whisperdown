import Foundation

/// 화자 분리 결과의 한 턴: "누가(speakerIndex) 언제(start...end) 말했나".
struct SpeakerTurn: Equatable, Sendable {
    let start: TimeInterval
    let end: TimeInterval
    let speakerIndex: Int
}

/// 화자 분리 구성 요소별 상태. EngineStatus와 달리 앱 준비 게이트에 참여하지 않는다(선택 기능).
struct DiarizationStatus: Equatable, Sendable {
    var cli: EngineStatus.Item
    var segmentationModel: EngineStatus.Item
    var embeddingModel: EngineStatus.Item

    var isFullyConfigured: Bool {
        cli.isFound && segmentationModel.isFound && embeddingModel.isFound
    }
}

enum DiarizationError: Error {
    case cliMissing
    case modelMissing
    case emptyResult
}

/// sherpa-onnx 오프라인 화자 분리 사이드카.
/// whisper-cli와 동일한 서브프로세스 패턴 — 바이너리/모델을 파일시스템에서 해석하고 ProcessRunner로 실행.
struct SpeakerDiarizationEngine: Sendable {
    private var fileManager: FileManager { .default }

    var isConfigured: Bool {
        cliURL != nil && segmentationModelURL != nil && embeddingModelURL != nil
    }

    func status() -> DiarizationStatus {
        DiarizationStatus(
            cli: cliURL.map(EngineStatus.Item.found) ?? .missing,
            segmentationModel: segmentationModelURL.map(EngineStatus.Item.found) ?? .missing,
            embeddingModel: embeddingModelURL.map(EngineStatus.Item.found) ?? .missing
        )
    }

    func diarize(wavURL: URL) async throws -> [SpeakerTurn] {
        guard let cliURL else {
            throw DiarizationError.cliMissing
        }
        guard let segmentationModelURL, let embeddingModelURL else {
            throw DiarizationError.modelMissing
        }

        let output = try await ProcessRunner.run(
            executableURL: cliURL,
            arguments: [
                "--clustering.cluster-threshold=\(clusterThreshold)",
                "--segmentation.pyannote-model=\(segmentationModelURL.path)",
                "--embedding.model=\(embeddingModelURL.path)",
                wavURL.path
            ]
        )

        let turns = output.stdout
            .split(whereSeparator: \.isNewline)
            .compactMap { Self.parseTurnLine(String($0)) }

        guard !turns.isEmpty else {
            throw DiarizationError.emptyResult
        }

        return turns
    }

    /// "1.583 -- 3.406 speaker_00" → SpeakerTurn. config dump/"Started" 라인은 불일치로 자연 폐기.
    static func parseTurnLine(_ line: String) -> SpeakerTurn? {
        guard let match = line.firstMatch(of: #/^\s*(\d+(?:\.\d+)?)\s*--\s*(\d+(?:\.\d+)?)\s+speaker_(\d+)\s*$/#),
              let start = TimeInterval(match.1),
              let end = TimeInterval(match.2),
              let speakerIndex = Int(match.3),
              end > start else {
            return nil
        }

        return SpeakerTurn(start: start, end: end, speakerIndex: speakerIndex)
    }

    // MARK: 설치 경로

    /// 사이드카 루트: ~/Library/Application Support/Whisperdown/Diarization
    static var diarizationDirectory: URL {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)

        return appSupport
            .appendingPathComponent("Whisperdown", isDirectory: true)
            .appendingPathComponent("Diarization", isDirectory: true)
    }

    /// sherpa-onnx 런타임 (bin/ + lib/, rpath 상대 참조라 함께 있어야 함)
    static var runtimeDirectory: URL {
        diarizationDirectory.appendingPathComponent("sherpa-onnx", isDirectory: true)
    }

    static var modelsDirectory: URL {
        diarizationDirectory.appendingPathComponent("Models", isDirectory: true)
    }

    static func uninstall() throws {
        try FileManager.default.removeItem(at: diarizationDirectory)
    }

    // MARK: 해석 체인 (whisper 엔진과 동일 관례: env → 설치 위치 → 시스템 경로)

    private var cliURL: URL? {
        firstExistingFile([
            environmentURL("WHISPERDOWN_DIARIZE_CLI"),
            Self.runtimeDirectory.appendingPathComponent("bin/sherpa-onnx-offline-speaker-diarization"),
            URL(fileURLWithPath: "/opt/homebrew/bin/sherpa-onnx-offline-speaker-diarization"),
            URL(fileURLWithPath: "/usr/local/bin/sherpa-onnx-offline-speaker-diarization")
        ])
    }

    private var segmentationModelURL: URL? {
        firstExistingFile([
            environmentURL("WHISPERDOWN_DIARIZE_SEGMENTATION"),
            Self.modelsDirectory.appendingPathComponent("pyannote-segmentation-3-0.onnx")
        ])
    }

    private var embeddingModelURL: URL? {
        firstExistingFile([
            environmentURL("WHISPERDOWN_DIARIZE_EMBEDDING"),
            Self.modelsDirectory.appendingPathComponent("nemo_en_titanet_small.onnx")
        ])
    }

    private var clusterThreshold: String {
        let value = ProcessInfo.processInfo.environment["WHISPERDOWN_DIARIZE_THRESHOLD"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let value, Double(value) != nil {
            return value
        }

        return "0.85"
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
}

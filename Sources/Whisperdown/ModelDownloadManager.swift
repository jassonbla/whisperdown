import Foundation

/// whisper.cpp ggml 모델의 인앱 다운로드 매니저 (LM Studio식).
///
/// - `URLSessionDownloadTask` + delegate 기반. delegate 콜백은 세션 큐(비메인)에서 오므로
///   `nonisolated`로 받고 Sendable 값만 스냅샷해 `Task { @MainActor }`로 hop한다
///   (AudioRecorder 탭 콜백과 동일한 검증된 패턴).
/// - 파일명은 요청 URL의 lastPathComponent로 식별해 delegate에서 MainActor 상태를 읽지 않는다.
/// - 완료 시 크기·ggml 매직 검증 후 `WhisperCppTranscriptionEngine.modelDirectory`로 원자적 이동.
///   엔진의 모델 탐색은 매 전사마다 디렉토리를 재검사하므로 이동 즉시 자동 활성화된다.
/// - resume(이어받기)은 v1 범위 제외. HuggingFace가 Range를 지원하므로 추후
///   `.download` 부분 파일 크기 기반 Range 재개로 확장 가능.
@MainActor
final class ModelDownloadManager: NSObject, ObservableObject {
    static let shared = ModelDownloadManager()

    enum DownloadState: Equatable {
        case idle
        case downloading(fraction: Double, receivedBytes: Int64, totalBytes: Int64)
        case failed(String)
        case installed
    }

    @Published private(set) var states: [String: DownloadState] = [:]

    private var downloadTasks: [String: URLSessionDownloadTask] = [:]

    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = true
        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }()

    override private init() {
        super.init()
        refreshInstalled()
    }

    /// 전체 다운로드 가능 항목 (whisper 모델 + 화자 분리 자산). delegate 콜백에서도 조회하므로 nonisolated.
    nonisolated static var allItems: [DownloadableItem] {
        ModelCatalog.all.map(\.downloadItem) + DiarizationCatalog.all
    }

    func state(for model: WhisperModel) -> DownloadState {
        states[model.fileName] ?? .idle
    }

    func state(forFileName fileName: String) -> DownloadState {
        states[fileName] ?? .idle
    }

    var isAnyDownloadActive: Bool {
        states.values.contains { state in
            if case .downloading = state {
                return true
            }

            return false
        }
    }

    /// 진행 중 다운로드의 대표 진행률 (글로벌 인디케이터용).
    var activeDownloadFraction: Double? {
        for state in states.values {
            if case .downloading(let fraction, _, _) = state {
                return fraction
            }
        }

        return nil
    }

    /// 설치된 항목 스캔 → states 갱신. 다운로드 중인 항목은 건드리지 않는다.
    func refreshInstalled() {
        for item in Self.allItems {
            if case .downloading = states[item.fileName] {
                continue
            }

            let installed = FileManager.default.fileExists(atPath: item.installedProbeURL.path)
            states[item.fileName] = installed ? .installed : .idle
        }
    }

    func startDownload(_ item: DownloadableItem) {
        guard downloadTasks[item.fileName] == nil else {
            return
        }

        states[item.fileName] = .downloading(fraction: 0, receivedBytes: 0, totalBytes: item.approximateBytes)

        let task = session.downloadTask(with: item.downloadURL)
        downloadTasks[item.fileName] = task
        task.resume()
    }

    func startDownload(_ model: WhisperModel) {
        startDownload(model.downloadItem)
    }

    func cancelDownload(_ item: DownloadableItem) {
        cancelDownload(fileName: item.fileName)
    }

    func cancelDownload(_ model: WhisperModel) {
        cancelDownload(fileName: model.fileName)
    }

    private func cancelDownload(fileName: String) {
        downloadTasks[fileName]?.cancel()
        downloadTasks[fileName] = nil
        states[fileName] = .idle
    }

    // MARK: - delegate 결과 반영 (MainActor)

    fileprivate func applyProgress(fileName: String, received: Int64, total: Int64) {
        // 취소 직후 늦게 도착한 콜백은 무시
        guard downloadTasks[fileName] != nil else {
            return
        }

        let fraction = total > 0 ? Double(received) / Double(total) : 0
        states[fileName] = .downloading(fraction: min(1, fraction), receivedBytes: received, totalBytes: total)
    }

    fileprivate func applyCompletion(fileName: String, result: Result<Void, ModelDownloadError>) {
        downloadTasks[fileName] = nil

        switch result {
        case .success:
            states[fileName] = .installed
        case .failure(.cancelled):
            states[fileName] = .idle
        case .failure(let error):
            states[fileName] = .failed(error.localizedDescription)
        }
    }
}

enum ModelDownloadError: LocalizedError, Sendable {
    case cancelled
    case network(String)
    case tooSmall(expected: Int64, actual: Int64)
    case invalidFormat
    case fileSystem(String)
    case extractFailed(String)

    var errorDescription: String? {
        switch self {
        case .cancelled:
            return L10n.t("error.download.cancelled", AppLanguage.current)
        case .network(let message):
            return String(format: L10n.t("error.download.network", AppLanguage.current), message)
        case .tooSmall(let expected, let actual):
            let expectedText = ByteCountFormatter.string(fromByteCount: expected, countStyle: .file)
            let actualText = ByteCountFormatter.string(fromByteCount: actual, countStyle: .file)
            return String(format: L10n.t("error.download.tooSmall", AppLanguage.current), expectedText, actualText)
        case .invalidFormat:
            return L10n.t("error.download.invalidFormat", AppLanguage.current)
        case .fileSystem(let message):
            return String(format: L10n.t("error.download.fileSystem", AppLanguage.current), message)
        case .extractFailed(let message):
            return String(format: L10n.t("error.download.extractFailed", AppLanguage.current), message)
        }
    }
}

// MARK: - URLSessionDownloadDelegate (세션 큐에서 호출 — nonisolated)

extension ModelDownloadManager: URLSessionDownloadDelegate {
    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard let fileName = downloadTask.originalRequest?.url?.lastPathComponent else {
            return
        }

        let expected = totalBytesExpectedToWrite > 0
            ? totalBytesExpectedToWrite
            : Self.allItems.first { $0.fileName == fileName }?.approximateBytes ?? 0

        Task { @MainActor in
            self.applyProgress(fileName: fileName, received: totalBytesWritten, total: expected)
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let fileName = downloadTask.originalRequest?.url?.lastPathComponent else {
            return
        }

        // location의 임시 파일은 이 메서드 반환 즉시 삭제되므로 검증·이동을 동기로 수행한다.
        let result = Self.validateAndInstall(from: location, fileName: fileName)

        Task { @MainActor in
            self.applyCompletion(fileName: fileName, result: result)
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let error, let fileName = task.originalRequest?.url?.lastPathComponent else {
            return
        }

        let result: Result<Void, ModelDownloadError> = (error as? URLError)?.code == .cancelled
            ? .failure(.cancelled)
            : .failure(.network(error.localizedDescription))

        Task { @MainActor in
            self.applyCompletion(fileName: fileName, result: result)
        }
    }

    /// 항목 종류별 검증·설치. 실패 시 임시 파일 정리.
    private nonisolated static func validateAndInstall(
        from location: URL,
        fileName: String
    ) -> Result<Void, ModelDownloadError> {
        let fileManager = FileManager.default

        guard let item = allItems.first(where: { $0.fileName == fileName }) else {
            try? fileManager.removeItem(at: location)
            return .failure(.invalidFormat)
        }

        let actualSize = (try? fileManager.attributesOfItem(atPath: location.path)[.size] as? Int64)
            .flatMap { $0 } ?? 0

        if Double(actualSize) < Double(item.approximateBytes) * 0.98 {
            try? fileManager.removeItem(at: location)
            return .failure(.tooSmall(expected: item.approximateBytes, actual: actualSize))
        }

        switch item.kind {
        case .whisperModel:
            // ggml 매직(0x67676d6c) — 디스크 선두 4바이트는 리틀엔디언 "lmgg".
            guard hasMagic(location, [0x6C, 0x6D, 0x67, 0x67]) || hasMagic(location, [0x67, 0x67, 0x6D, 0x6C]) else {
                try? fileManager.removeItem(at: location)
                return .failure(.invalidFormat)
            }
            return install(from: location, to: item.installedProbeURL)

        case .diarizationEmbeddingModel:
            // ONNX(protobuf)는 저비용 매직이 없어 크기 검사만.
            return install(from: location, to: item.installedProbeURL)

        case .diarizationRuntime:
            guard hasMagic(location, [0x42, 0x5A, 0x68]) else {   // "BZh"
                try? fileManager.removeItem(at: location)
                return .failure(.invalidFormat)
            }
            // 아카이브 최상위 <root>/{bin,lib}을 런타임 디렉토리로 이동 (rpath 상대 참조라 함께 있어야 함)
            return extractAndInstall(archive: location) { staging in
                let root = staging.appendingPathComponent(DiarizationCatalog.runtimeArchiveRoot, isDirectory: true)
                let destination = SpeakerDiarizationEngine.runtimeDirectory
                try replaceItem(at: destination.appendingPathComponent("bin"), with: root.appendingPathComponent("bin"))
                try replaceItem(at: destination.appendingPathComponent("lib"), with: root.appendingPathComponent("lib"))
            }

        case .diarizationSegmentationModel:
            guard hasMagic(location, [0x42, 0x5A, 0x68]) else {
                try? fileManager.removeItem(at: location)
                return .failure(.invalidFormat)
            }
            return extractAndInstall(archive: location) { staging in
                let source = staging
                    .appendingPathComponent("sherpa-onnx-pyannote-segmentation-3-0", isDirectory: true)
                    .appendingPathComponent("model.onnx")
                try replaceItem(
                    at: SpeakerDiarizationEngine.modelsDirectory.appendingPathComponent("pyannote-segmentation-3-0.onnx"),
                    with: source
                )
            }
        }
    }

    private nonisolated static func hasMagic(_ url: URL, _ bytes: [UInt8]) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url),
              let header = try? handle.read(upToCount: bytes.count) else {
            return false
        }
        try? handle.close()
        return header == Data(bytes)
    }

    private nonisolated static func install(from location: URL, to destination: URL) -> Result<Void, ModelDownloadError> {
        let fileManager = FileManager.default
        do {
            try fileManager.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.moveItem(at: location, to: destination)
            return .success(())
        } catch {
            try? fileManager.removeItem(at: location)
            return .failure(.fileSystem(error.localizedDescription))
        }
    }

    /// tar.bz2를 스테이징에 추출 후 place 클로저로 배치. URLSession delegate 큐(비메인)에서
    /// 동기 실행되므로 waitUntilExit가 안전하다.
    private nonisolated static func extractAndInstall(
        archive: URL,
        place: (URL) throws -> Void
    ) -> Result<Void, ModelDownloadError> {
        let fileManager = FileManager.default
        let staging = fileManager.temporaryDirectory
            .appendingPathComponent("Whisperdown-extract-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? fileManager.removeItem(at: staging)
            try? fileManager.removeItem(at: archive)
        }

        do {
            try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)

            let tar = Process()
            tar.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
            tar.arguments = ["-xjf", archive.path, "-C", staging.path]
            tar.standardOutput = FileHandle.nullDevice
            tar.standardError = FileHandle.nullDevice
            try tar.run()
            tar.waitUntilExit()

            guard tar.terminationStatus == 0 else {
                return .failure(.extractFailed("tar exit \(tar.terminationStatus)"))
            }

            try place(staging)
            return .success(())
        } catch {
            return .failure(.extractFailed(error.localizedDescription))
        }
    }

    private nonisolated static func replaceItem(at destination: URL, with source: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.moveItem(at: source, to: destination)
    }
}

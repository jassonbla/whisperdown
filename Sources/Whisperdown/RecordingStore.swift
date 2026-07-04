import AppKit
import Foundation

@MainActor
final class RecordingStore: ObservableObject {
    @Published private(set) var recordings: [Recording] = []
    @Published private(set) var markdownDirectory: URL

    private let fileManager = FileManager.default
    private let metadataDirectoryName = ".whisperdown"
    private let audioDirectoryName = "Recordings"
    private let indexFileName = "index.json"

    init() {
        let savedPath = UserDefaults.standard.string(forKey: "markdownDirectory")
        if let savedPath {
            markdownDirectory = URL(fileURLWithPath: savedPath)
        } else {
            let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
                ?? fileManager.homeDirectoryForCurrentUser
            markdownDirectory = documents.appendingPathComponent("Whisperdown", isDirectory: true)
        }

        ensureDirectories()
        load()

        NotificationCenter.default.addObserver(
            forName: .openMarkdownFolderRequested,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.openMarkdownFolder()
            }
        }

        NotificationCenter.default.addObserver(
            forName: .markdownDirectoryChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.reloadMarkdownDirectoryFromDefaults()
            }
        }
    }

    private func reloadMarkdownDirectoryFromDefaults() {
        guard let savedPath = UserDefaults.standard.string(forKey: "markdownDirectory") else {
            return
        }

        let url = URL(fileURLWithPath: savedPath)
        guard url != markdownDirectory else {
            return
        }

        markdownDirectory = url
        ensureDirectories()
        load()
    }

    var audioDirectory: URL {
        markdownDirectory.appendingPathComponent(audioDirectoryName, isDirectory: true)
    }

    private var metadataDirectory: URL {
        markdownDirectory.appendingPathComponent(metadataDirectoryName, isDirectory: true)
    }

    private var indexURL: URL {
        metadataDirectory.appendingPathComponent(indexFileName)
    }

    func chooseMarkdownDirectory() {
        let panel = NSOpenPanel()
        panel.title = L10n.t("settings.markdownFolder.pickerTitle", AppLanguage.current)
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = markdownDirectory

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        markdownDirectory = url
        UserDefaults.standard.set(url.path, forKey: "markdownDirectory")
        ensureDirectories()
        load()
    }

    func openMarkdownFolder() {
        ensureDirectories()
        NSWorkspace.shared.open(markdownDirectory)
    }

    /// 녹음 삭제. 인덱스에서 제거하고 오디오/마크다운 파일은 휴지통으로 이동한다(복구 가능).
    func remove(_ recording: Recording) {
        recordings.removeAll { $0.id == recording.id }
        save()

        for url in [recording.audioURL, recording.markdownURL]
        where fileManager.fileExists(atPath: url.path) {
            try? fileManager.trashItem(at: url, resultingItemURL: nil)
        }
    }

    func add(_ recording: Recording) {
        recordings.insert(recording, at: 0)
        save()
    }

    func update(_ recording: Recording) {
        guard let index = recordings.firstIndex(where: { $0.id == recording.id }) else {
            return
        }

        recordings[index] = recording
        recordings.sort { $0.createdAt > $1.createdAt }
        save()
    }

    func uniqueMarkdownURL(for date: Date, title: String) -> URL {
        let base = "\(AppFormatters.fileDate.string(from: date))_\(title.markdownFilenameSafe)_추출"
        return uniqueURL(in: markdownDirectory, baseName: base, extensionName: "md")
    }

    func uniqueAudioURL(for date: Date) -> URL {
        let base = "\(AppFormatters.fileDate.string(from: date))_recording"
        return uniqueURL(in: audioDirectory, baseName: base, extensionName: "caf")
    }

    func ensureDirectories() {
        try? fileManager.createDirectory(at: markdownDirectory, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: audioDirectory, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: metadataDirectory, withIntermediateDirectories: true)
    }

    private func uniqueURL(in directory: URL, baseName: String, extensionName: String) -> URL {
        ensureDirectories()

        var candidate = directory
            .appendingPathComponent(baseName)
            .appendingPathExtension(extensionName)

        var suffix = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = directory
                .appendingPathComponent("\(baseName)-\(suffix)")
                .appendingPathExtension(extensionName)
            suffix += 1
        }

        return candidate
    }

    private func load() {
        guard let data = try? Data(contentsOf: indexURL) else {
            recordings = []
            return
        }

        do {
            let decoded = try JSONDecoder().decode([Recording].self, from: data)
            let migrated = decoded.map(migrateRecordingIfNeeded)
            let didMigrate = zip(decoded, migrated).contains { before, after in
                before != after
            }

            recordings = migrated
                .sorted { $0.createdAt > $1.createdAt }

            if didMigrate {
                save()
                rewriteMigratedMarkdowns(before: decoded, after: migrated)
            }
        } catch {
            recordings = []
        }
    }

    private func migrateRecordingIfNeeded(_ recording: Recording) -> Recording {
        if recording.status == .processing {
            return failedRecording(
                from: recording,
                note: L10n.t("store.migration.interrupted", AppLanguage.current)
            )
        }

        guard recording.status == .ready else {
            return recording
        }

        if isLiveDraftSavedAsFinal(recording) {
            return failedRecording(
                from: recording,
                note: L10n.t("store.migration.liveDraftBug", AppLanguage.current)
            )
        }

        if isLegacyPlaceholder(recording) {
            return failedRecording(
                from: recording,
                note: L10n.t("store.migration.legacyPlaceholder", AppLanguage.current)
            )
        }

        if isKnownLowConfidenceHallucination(recording) {
            return failedRecording(
                from: recording,
                note: L10n.t("store.migration.hallucination", AppLanguage.current)
            )
        }

        return recording
    }

    private func isLiveDraftSavedAsFinal(_ recording: Recording) -> Bool {
        recording.engineNote.contains("Apple Speech live")
            && recording.engineNote.contains("draft")
    }

    private func failedRecording(from recording: Recording, note: String) -> Recording {
        var migrated = recording
        migrated.title = String(format: L10n.t("processor.failureTitlePrefix", AppLanguage.current), AppFormatters.fileDate.string(from: recording.createdAt))
        migrated.status = .failed
        migrated.transcript = ""
        migrated.segments = []
        migrated.engineNote = note
        return migrated
    }

    private func isLegacyPlaceholder(_ recording: Recording) -> Bool {
        let values = [recording.title, recording.transcript, recording.engineNote]
            + recording.segments.map(\.text)

        return values.contains { value in
            value.contains("전사 대기 중입니다")
                || value.contains("로컬 전사 엔진이 아직 연결되지 않았습니다")
                || value.contains("whisper.cpp 모델 연결 후")
        }
    }

    private func isKnownLowConfidenceHallucination(_ recording: Recording) -> Bool {
        guard recording.duration <= 30,
              recording.engineNote.contains("whisper.cpp") else {
            return false
        }

        let values = [recording.title, recording.transcript] + recording.segments.map(\.text)
        return values.contains { value in
            Self.commonWhisperHallucinations.contains(Self.normalizedTranscript(value))
        }
    }

    private static let commonWhisperHallucinations: Set<String> = [
        "시청해주셔서감사합니다.",
        "시청해주셔서감사합니다",
        "구독좋아요부탁드립니다.",
        "구독좋아요부탁드립니다"
    ]

    private static func normalizedTranscript(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func rewriteMigratedMarkdowns(before: [Recording], after: [Recording]) {
        let markdownWriter = MarkdownWriter()

        for (original, migrated) in zip(before, after) where original != migrated {
            let markdown = markdownWriter.render(recording: migrated)
            try? markdown.write(to: migrated.markdownURL, atomically: true, encoding: .utf8)
        }
    }

    private func save() {
        ensureDirectories()

        do {
            let data = try JSONEncoder.pretty.encode(recordings)
            try data.write(to: indexURL, options: [.atomic])
        } catch {
            assertionFailure("Failed to save recordings index: \(error)")
        }
    }
}

private extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

import Foundation

@MainActor
final class RecordingProcessor: ObservableObject {
    @Published private(set) var isProcessing = false
    @Published private(set) var processingMessage: String?

    private let transcriptionEngine = TranscriptionEngine()
    private let titleExtractor = TitleExtractor()
    private let markdownWriter = MarkdownWriter()

    func process(
        audio: RecordedAudio,
        store: RecordingStore,
        onCreated: (Recording) -> Void = { _ in }
    ) async -> Recording? {
        isProcessing = true
        processingMessage = L10n.t("processor.preparing", AppLanguage.current)
        defer {
            isProcessing = false
            processingMessage = nil
        }

        let transcribingLabel = L10n.t("detail.badge.transcribing", AppLanguage.current)
        var recording = Recording(
            title: transcribingLabel,
            createdAt: audio.startedAt,
            duration: audio.duration,
            markdownURL: store.uniqueMarkdownURL(for: audio.startedAt, title: transcribingLabel),
            audioURL: audio.url,
            status: .processing,
            transcript: L10n.t("processor.transcribingPlaceholder", AppLanguage.current),
            segments: [],
            engineNote: L10n.t("processor.transcribingNote", AppLanguage.current)
        )

        store.add(recording)
        onCreated(recording)

        do {
            processingMessage = transcribingLabel
            let transcript = try await transcriptionEngine.transcribe(audio: audio)
            let title = titleExtractor.title(from: transcript.text, fallbackDate: audio.startedAt)
            let markdownURL = store.uniqueMarkdownURL(for: audio.startedAt, title: title)

            recording.title = title
            recording.markdownURL = markdownURL
            recording.transcript = transcript.text
            recording.segments = transcript.segments
            recording.engineNote = transcript.engineNote

            let markdown = markdownWriter.render(recording: recording)
            try markdown.write(to: markdownURL, atomically: true, encoding: .utf8)
            recording.status = .ready
            store.update(recording)
            return recording
        } catch {
            let failureTitle = String(format: L10n.t("processor.failureTitlePrefix", AppLanguage.current), AppFormatters.fileDate.string(from: audio.startedAt))
            recording.title = failureTitle
            recording.markdownURL = store.uniqueMarkdownURL(for: audio.startedAt, title: failureTitle)
            recording.status = .failed
            recording.engineNote = error.localizedDescription
            recording.transcript = ""
            recording.segments = []

            let markdown = markdownWriter.render(recording: recording)
            try? markdown.write(to: recording.markdownURL, atomically: true, encoding: .utf8)
            store.update(recording)
            return recording
        }
    }

    func retry(recording: Recording, store: RecordingStore) async -> Recording? {
        isProcessing = true
        let transcribingLabel = L10n.t("detail.badge.transcribing", AppLanguage.current)
        processingMessage = transcribingLabel
        defer {
            isProcessing = false
            processingMessage = nil
        }

        var updated = recording
        updated.title = transcribingLabel
        updated.status = .processing
        updated.transcript = L10n.t("processor.transcribingPlaceholder", AppLanguage.current)
        updated.segments = []
        updated.engineNote = L10n.t("processor.transcribingNote", AppLanguage.current)
        store.update(updated)

        let audio = RecordedAudio(
            url: recording.audioURL,
            startedAt: recording.createdAt,
            duration: recording.duration
        )

        do {
            let transcript = try await transcriptionEngine.transcribe(audio: audio)
            let title = titleExtractor.title(from: transcript.text, fallbackDate: audio.startedAt)
            let markdownURL = store.uniqueMarkdownURL(for: audio.startedAt, title: title)

            updated.title = title
            updated.markdownURL = markdownURL
            updated.transcript = transcript.text
            updated.segments = transcript.segments
            updated.engineNote = transcript.engineNote

            let markdown = markdownWriter.render(recording: updated)
            try markdown.write(to: markdownURL, atomically: true, encoding: .utf8)
            updated.status = .ready
            store.update(updated)
            return updated
        } catch {
            let failureTitle = String(format: L10n.t("processor.failureTitlePrefix", AppLanguage.current), AppFormatters.fileDate.string(from: audio.startedAt))
            updated.title = failureTitle
            updated.markdownURL = store.uniqueMarkdownURL(for: audio.startedAt, title: failureTitle)
            updated.status = .failed
            updated.engineNote = error.localizedDescription
            updated.transcript = ""
            updated.segments = []

            let markdown = markdownWriter.render(recording: updated)
            try? markdown.write(to: updated.markdownURL, atomically: true, encoding: .utf8)
            store.update(updated)
            return updated
        }
    }
}

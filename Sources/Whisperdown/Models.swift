import Foundation

enum RecordingStatus: String, Codable, Hashable {
    case ready
    case processing
    case failed
}

struct RecordedAudio: Hashable {
    let url: URL
    let startedAt: Date
    let duration: TimeInterval
    let liveTranscript: TranscriptResult?

    init(
        url: URL,
        startedAt: Date,
        duration: TimeInterval,
        liveTranscript: TranscriptResult? = nil
    ) {
        self.url = url
        self.startedAt = startedAt
        self.duration = duration
        self.liveTranscript = liveTranscript
    }
}

struct SpeakerSegment: Identifiable, Codable, Hashable {
    var id = UUID()
    var speaker: String
    var startTime: TimeInterval
    var endTime: TimeInterval
    var text: String
}

struct Recording: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    var createdAt: Date
    var duration: TimeInterval
    var markdownURL: URL
    var audioURL: URL
    var status: RecordingStatus
    var transcript: String
    var segments: [SpeakerSegment]
    var engineNote: String
    /// AI 생성 요약 (마크다운 불릿). optional + 기본값 — 기존 index.json 디코드가 깨지면
    /// load()의 catch가 라이브러리 전체를 비우므로 반드시 하위 호환이어야 한다.
    var summary: String? = nil
}

struct TranscriptResult: Hashable {
    var text: String
    var segments: [SpeakerSegment]
    var engineNote: String
}

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
}

struct TranscriptResult: Hashable {
    var text: String
    var segments: [SpeakerSegment]
    var engineNote: String
}

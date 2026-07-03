import Foundation

struct MarkdownWriter {
    func render(recording: Recording) -> String {
        let audioRelativePath = "Recordings/\(recording.audioURL.lastPathComponent)"
        let transcriptBody: String
        if recording.status == .failed {
            transcriptBody = "> 전사 실패: \(recording.engineNote)"
        } else {
            transcriptBody = recording.segments
                .map(renderSegment)
                .joined(separator: "\n\n")
        }

        return """
        # \(recording.title)

        - 날짜: \(AppFormatters.displayDate.string(from: recording.createdAt))
        - 길이: \(AppFormatters.duration(recording.duration))
        - 원본 오디오: `\(audioRelativePath)`
        - 전사 엔진: \(recording.engineNote)

        ## 요약

        - 자동 요약은 다음 단계에서 연결됩니다.

        ## 전사

        \(transcriptBody)
        """
    }

    private func renderSegment(_ segment: SpeakerSegment) -> String {
        """
        ### \(segment.speaker) [\(AppFormatters.timestamp(segment.startTime)) - \(AppFormatters.timestamp(segment.endTime))]

        \(segment.text)
        """
    }
}

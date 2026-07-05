import Foundation

struct MarkdownWriter {
    func render(recording: Recording) -> String {
        frontMatter(recording: recording) + "\n" + body(recording: recording)
    }

    /// YAML front matter — 다른 에이전트가 파싱하는 기계용 메타데이터 레이어.
    /// `whisperdown: 1`은 스키마 버전이자 기존 파일 마이그레이션 마커.
    func frontMatter(recording: Recording) -> String {
        let audioRelativePath = "Recordings/\(recording.audioURL.lastPathComponent)"
        let speakerCount = Set(recording.segments.map(\.speaker)).count
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"

        return """
        ---
        whisperdown: 1
        title: \(yamlQuoted(recording.title))
        created: \(AppFormatters.iso8601.string(from: recording.createdAt))
        duration: \(Int(recording.duration.rounded()))
        audio: \(yamlQuoted(audioRelativePath))
        engine: \(yamlQuoted(recording.engineNote))
        speakers: \(speakerCount)
        status: \(recording.status.rawValue)
        generator: \(yamlQuoted("Whisperdown \(version)"))
        ---

        """
    }

    private func body(recording: Recording) -> String {
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

    private func yamlQuoted(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
        return "\"\(escaped)\""
    }
}

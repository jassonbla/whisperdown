import Foundation

struct TitleExtractor {
    func title(from transcript: String, fallbackDate: Date) -> String {
        let candidates = transcript
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { line in
                line.count >= 4
                    && !line.hasPrefix("전사 대기")
                    && !line.hasPrefix("로컬 전사 엔진")
                    && !line.hasPrefix("원본 오디오 파일")
            }

        if let first = candidates.first {
            return compactTitle(first)
        }

        return "새 녹음 \(AppFormatters.fileDate.string(from: fallbackDate))"
    }

    private func compactTitle(_ text: String) -> String {
        let normalized = text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalized.isEmpty else {
            return "새 녹음"
        }

        return String(normalized.prefix(28))
    }
}

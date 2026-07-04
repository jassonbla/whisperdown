import Foundation

/// whisper JSON 토큰 하나의 타이밍 (offsets는 밀리초).
struct WhisperTokenTiming: Equatable, Sendable {
    let text: String
    let fromMs: Int
    let toMs: Int
}

/// 화자 턴(누가 언제)과 whisper 토큰(무엇을)을 시간축에서 병합해 화자별 세그먼트를 만든다.
/// 순수 함수 — 실패/무의미한 입력이면 nil을 반환하고 호출측이 단일 화자 폴백을 유지한다.
enum SpeakerTurnMerger {
    static func merge(turns: [SpeakerTurn], tokens: [WhisperTokenTiming]) -> [SpeakerSegment]? {
        let sortedTurns = turns.sorted { $0.start < $1.start }
        let usableTokens = tokens
            .filter { !$0.text.isEmpty && !isSpecialToken($0.text) }
            .sorted { $0.fromMs < $1.fromMs }

        guard !sortedTurns.isEmpty, !usableTokens.isEmpty else {
            return nil
        }

        // 토큰마다 반드시 하나의 턴에 배정한다:
        // midpoint를 포함하는 턴 → 다수면 겹침 최대(동률 = 이른 start) → 없으면 최근접 턴.
        let assignments = usableTokens.map { token -> (token: WhisperTokenTiming, turnIndex: Int) in
            let fromSec = Double(token.fromMs) / 1000
            let toSec = Double(token.toMs) / 1000
            let mid = (fromSec + toSec) / 2

            let containing = sortedTurns.indices.filter { sortedTurns[$0].start <= mid && mid < sortedTurns[$0].end }

            if containing.count == 1 {
                return (token, containing[0])
            }

            if containing.count > 1 {
                let best = containing.max { a, b in
                    let overlapA = min(sortedTurns[a].end, toSec) - max(sortedTurns[a].start, fromSec)
                    let overlapB = min(sortedTurns[b].end, toSec) - max(sortedTurns[b].start, fromSec)
                    if overlapA != overlapB { return overlapA < overlapB }
                    return sortedTurns[a].start > sortedTurns[b].start
                }!
                return (token, best)
            }

            // 어떤 턴에도 없음 (whisper가 무음 구간으로 판정된 곳에서 텍스트를 내는 경우 등)
            let nearest = sortedTurns.indices.min { a, b in
                distance(from: mid, to: sortedTurns[a]) < distance(from: mid, to: sortedTurns[b])
            }!
            return (token, nearest)
        }

        // 같은 턴에 배정된 연속 토큰 run = 세그먼트 1개.
        // 같은 화자라도 턴이 다르면 분리 — 단일 화자 녹음도 문단화 효과를 얻는다.
        var groups: [(turnIndex: Int, tokens: [WhisperTokenTiming])] = []
        for (token, turnIndex) in assignments {
            if groups.last?.turnIndex == turnIndex {
                groups[groups.count - 1].tokens.append(token)
            } else {
                groups.append((turnIndex, [token]))
            }
        }

        // 화자명은 등장 순서 1-based ("Speaker 1", "Speaker 2", ...) —
        // sherpa 번호가 시간순이 아닐 수 있으므로 재매핑한다.
        var speakerNames: [Int: String] = [:]
        var segments: [SpeakerSegment] = []

        for group in groups {
            let text = group.tokens.map(\.text).joined().trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, let first = group.tokens.first, let last = group.tokens.last else {
                continue
            }

            let speakerIndex = sortedTurns[group.turnIndex].speakerIndex
            if speakerNames[speakerIndex] == nil {
                speakerNames[speakerIndex] = "Speaker \(speakerNames.count + 1)"
            }

            segments.append(
                SpeakerSegment(
                    speaker: speakerNames[speakerIndex]!,
                    startTime: Double(first.fromMs) / 1000,
                    endTime: Double(last.toMs) / 1000,
                    text: text
                )
            )
        }

        guard !segments.isEmpty else {
            return nil
        }

        return segments
    }

    /// "[_BEG_]", "[_TT_500]", "[_EOT_]" 등 whisper 스페셜 토큰
    private static func isSpecialToken(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("[_") && trimmed.hasSuffix("]")
    }

    private static func distance(from point: TimeInterval, to turn: SpeakerTurn) -> TimeInterval {
        max(turn.start - point, point - turn.end, 0)
    }
}

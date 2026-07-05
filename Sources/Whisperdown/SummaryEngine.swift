import Foundation

/// 요약 백엔드 가용성. FoundationModels 타입이 이 파일로 새지 않도록 자체 enum으로 표현한다.
enum SummaryAvailability: Equatable {
    case available
    case unsupportedOS
    case modelUnavailable(String)

    var isAvailable: Bool { self == .available }
}

/// 단발성 LLM 호출. 세션 히스토리를 재사용하지 않는다 — 호출마다 새 세션/프로세스.
protocol SummaryBackend: Sendable {
    func respond(instructions: String, prompt: String) async throws -> String
    /// 이 백엔드가 한 번에 받을 수 있는 전사본 예산(자). 크면 청커가 1청크를 만들어
    /// 기존 단일 패스 분기가 자동 작동한다 — map-reduce 코드는 그대로.
    var contextCharBudget: Int { get }
    var glossaryCharBudget: Int { get }
}

extension SummaryBackend {
    var contextCharBudget: Int { SummaryEngine.chunkCharBudget }
    var glossaryCharBudget: Int { SummaryEngine.glossaryCharBudget }
}

/// 요약 엔진 선택 (Settings). 비-View 레이어는 `current`로 읽는다 (AppLanguage.current 패턴).
enum SummaryBackendKind: String {
    case apple
    case local

    static var current: SummaryBackendKind {
        SummaryBackendKind(rawValue: UserDefaults.standard.string(forKey: "summaryBackend") ?? "apple") ?? .apple
    }

    static var selectedModelFileName: String? {
        UserDefaults.standard.string(forKey: "summaryModelFileName")
    }
}

enum SummaryEngineError: LocalizedError {
    case unavailable
    case emptyTranscript
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return L10n.t("summary.error.unavailable", AppLanguage.current)
        case .emptyTranscript, .emptyResponse:
            return L10n.t("summary.failed", AppLanguage.current)
        }
    }
}

/// 요약 파사드 — 용어집 주입 + 청크 분할 map-reduce.
/// v2에서 llama.cpp 사이드카가 makeBackend()에 슬롯인될 수 있는 구조.
struct SummaryEngine: Sendable {
    /// 토큰 예산 (4,096 윈도우, 한국어 1자 ≈ 1토큰 보수 추정):
    /// 출력 예약 ~500 + 고정 instructions ~300 + 용어집 캡 1,200 → 청크 ~2,000자.
    static let glossaryCharBudget = 1_200
    static let chunkCharBudget = 2_000

    /// Apple 온디바이스 모델 가용성 (엔진 선택 UI의 Apple 행 배지용).
    static func appleAvailability() -> SummaryAvailability {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            return FoundationModelsSummaryBackend.availability()
        }
        #endif
        return .unsupportedOS
    }

    /// 선택된 엔진 기준의 실효 가용성. 로컬 선택인데 준비 안 됐으면 Apple로 강등 —
    /// makeBackend()의 조용한 폴백과 동일한 순서.
    static func effectiveAvailability() -> SummaryAvailability {
        if SummaryBackendKind.current == .local,
           LlamaSummaryEngine.availability(modelFileName: SummaryBackendKind.selectedModelFileName).isAvailable {
            return .available
        }
        return appleAvailability()
    }

    private static func makeBackend() -> (any SummaryBackend)? {
        if SummaryBackendKind.current == .local,
           let fileName = SummaryBackendKind.selectedModelFileName,
           let cliURL = LlamaSummaryEngine.cliURL,
           let modelURL = LlamaSummaryEngine.modelURL(fileName: fileName) {
            return LlamaCppSummaryBackend(cliURL: cliURL, modelURL: modelURL)
        }

        #if canImport(FoundationModels)
        if #available(macOS 26.0, *), FoundationModelsSummaryBackend.availability().isAvailable {
            return FoundationModelsSummaryBackend()
        }
        #endif
        return nil
    }

    /// 전사본을 요약해 마크다운 불릿 목록(헤딩 없음)을 반환한다.
    func summarize(segments: [SpeakerSegment], transcript: String, glossary: String?) async throws -> String {
        guard let backend = Self.makeBackend() else {
            throw SummaryEngineError.unavailable
        }

        let instructions = SummaryPromptBuilder.instructions(glossary: glossary, limit: backend.glossaryCharBudget)
        let chunks = TranscriptChunker.chunks(segments: segments, transcript: transcript, budget: backend.contextCharBudget)
        guard !chunks.isEmpty else {
            throw SummaryEngineError.emptyTranscript
        }

        if chunks.count == 1 {
            guard let summary = try await mapChunk(
                backend: backend,
                instructions: instructions,
                prompt: SummaryPromptBuilder.singlePassPrompt(transcript: chunks[0]),
                chunk: chunks[0]
            ) else {
                throw SummaryEngineError.emptyResponse
            }
            return try validated(summary)
        }

        // MAP — 청크별 부분 요약 (호출마다 fresh 세션). 청크 하나가 실패해도(언어 감지 오판 등)
        // 전체 요약을 죽이지 않도록 nil은 건너뛴다 — 부분 요약이 없는 것보다 낫다.
        var partials: [String] = []
        for (index, chunk) in chunks.enumerated() {
            try Task.checkCancellation()
            if let partial = try await mapChunk(
                backend: backend,
                instructions: instructions,
                prompt: SummaryPromptBuilder.mapPrompt(chunk: chunk, index: index + 1, total: chunks.count),
                chunk: chunk
            ) {
                partials.append(partial)
            }
        }
        guard !partials.isEmpty else {
            throw SummaryEngineError.emptyResponse
        }

        // REDUCE — 부분 요약이 다시 예산을 넘으면 5개 그룹으로 1단계 선축약
        var joined = partials.joined(separator: "\n")
        while joined.count > backend.contextCharBudget, partials.count > 1 {
            try Task.checkCancellation()
            var condensed: [String] = []
            for group in stride(from: 0, to: partials.count, by: 5).map({ Array(partials[$0..<min($0 + 5, partials.count)]) }) {
                if let reduced = try await mapChunk(
                    backend: backend,
                    instructions: instructions,
                    prompt: SummaryPromptBuilder.reducePrompt(partials: group.joined(separator: "\n")),
                    chunk: group.joined(separator: "\n")
                ) {
                    condensed.append(reduced)
                }
            }
            partials = condensed.isEmpty ? partials : condensed
            joined = partials.joined(separator: "\n")
        }

        try Task.checkCancellation()
        guard let summary = try await mapChunk(
            backend: backend,
            instructions: instructions,
            prompt: SummaryPromptBuilder.reducePrompt(partials: joined),
            chunk: joined
        ) else {
            throw SummaryEngineError.emptyResponse
        }
        return try validated(summary)
    }

    /// 청크 1개 요약 — 회복력 있는 단발 호출.
    /// FM 언어 감지기가 짧은 발화 + 반복 화자 라벨을 "지원 안 하는 언어"로 오판하는 경우가 있어,
    /// 실패 시 라벨을 벗기고 1회 재시도한다. 그래도 실패하면 nil(이 청크만 건너뜀).
    /// 취소만 상위로 전파한다.
    private func mapChunk(
        backend: any SummaryBackend,
        instructions: String,
        prompt: String,
        chunk: String
    ) async throws -> String? {
        do {
            return try await backend.respond(instructions: instructions, prompt: prompt)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            let cleaned = Self.stripSpeakerLabels(chunk)
            guard cleaned != chunk, !cleaned.isEmpty else {
                return nil
            }
            do {
                return try await backend.respond(
                    instructions: instructions,
                    prompt: SummaryPromptBuilder.singlePassPrompt(transcript: cleaned)
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                return nil
            }
        }
    }

    /// "Speaker N: 텍스트" 라인들에서 라벨을 제거하고 텍스트만 이어붙인다.
    static func stripSpeakerLabels(_ text: String) -> String {
        text.components(separatedBy: "\n")
            .map { line -> String in
                guard let colon = line.firstIndex(of: ":"),
                      line[..<colon].hasPrefix("Speaker ") else {
                    return line
                }
                return String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func validated(_ summary: String) throws -> String {
        let trimmed = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw SummaryEngineError.emptyResponse
        }
        return Self.normalizedBullets(trimmed)
    }

    /// 모델이 "- " 대신 "* "/"• " 불릿을 쓰는 경우가 있어 마크다운 표준 "- "로 통일한다.
    static func normalizedBullets(_ text: String) -> String {
        text.components(separatedBy: "\n")
            .map { line in
                let stripped = line.trimmingCharacters(in: .whitespaces)
                if stripped.hasPrefix("* ") {
                    return "- " + stripped.dropFirst(2).trimmingCharacters(in: .whitespaces)
                }
                if stripped.hasPrefix("• ") {
                    return "- " + stripped.dropFirst(2).trimmingCharacters(in: .whitespaces)
                }
                return line
            }
            .joined(separator: "\n")
    }
}

/// 전사본을 토큰 예산에 맞는 청크로 나눈다. 세그먼트("화자: 텍스트") 단위 누적이 기본,
/// 한 세그먼트가 예산을 넘으면 문장 경계로 분할하고 최후에는 하드 슬라이스한다.
enum TranscriptChunker {
    static func chunks(segments: [SpeakerSegment], transcript: String, budget: Int) -> [String] {
        let units: [String]
        if segments.isEmpty {
            units = [transcript.trimmingCharacters(in: .whitespacesAndNewlines)]
        } else {
            // 화자가 1명뿐이면 "Speaker 1:" 라벨은 순수 노이즈다 — 짧은 발화가 많은 구간에서
            // 라벨이 실제 언어 내용을 희석해 FM 언어 감지기를 오판시킨다. 다화자일 때만 라벨을 붙인다.
            let multiSpeaker = Set(segments.map(\.speaker)).count > 1
            units = segments.map { multiSpeaker ? "\($0.speaker): \($0.text)" : $0.text }
        }

        var result: [String] = []
        var current = ""

        func flush() {
            let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                result.append(trimmed)
            }
            current = ""
        }

        for unit in units {
            if unit.count > budget {
                flush()
                result.append(contentsOf: splitBySentence(unit, budget: budget))
            } else if current.count + unit.count + 1 > budget {
                flush()
                current = unit
            } else {
                current = current.isEmpty ? unit : current + "\n" + unit
            }
        }
        flush()

        return result.filter { !$0.isEmpty }
    }

    private static func splitBySentence(_ text: String, budget: Int) -> [String] {
        var sentences: [String] = []
        var current = ""
        for character in text {
            current.append(character)
            if character == "." || character == "?" || character == "!" || character == "\n" {
                sentences.append(current)
                current = ""
            }
        }
        if !current.isEmpty {
            sentences.append(current)
        }

        var result: [String] = []
        var chunk = ""
        for sentence in sentences {
            if sentence.count > budget {
                if !chunk.isEmpty {
                    result.append(chunk)
                    chunk = ""
                }
                // 문장 하나가 예산 초과 — 하드 슬라이스 폴백
                var remainder = Substring(sentence)
                while remainder.count > budget {
                    result.append(String(remainder.prefix(budget)))
                    remainder = remainder.dropFirst(budget)
                }
                chunk = String(remainder)
            } else if chunk.count + sentence.count > budget {
                result.append(chunk)
                chunk = sentence
            } else {
                chunk += sentence
            }
        }
        if !chunk.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            result.append(chunk)
        }

        return result.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }
}

enum SummaryPromptBuilder {
    static func instructions(glossary: String?, limit: Int = SummaryEngine.glossaryCharBudget) -> String {
        let glossaryBlock: String
        if let glossary, !glossary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            glossaryBlock = truncatedAtLineBoundary(glossary, limit: limit)
        } else {
            glossaryBlock = "(없음)"
        }

        return """
        당신은 음성 녹음 전사문을 요약하는 도우미입니다.

        규칙:
        - 한국어 마크다운 불릿 목록으로만 출력합니다. 각 줄은 "- "로 시작하고, 제목이나 서론을 붙이지 않습니다.
        - 전사(음성 인식) 오류로 보이는 단어는 아래 용어집을 참고해 올바른 용어로 바로잡아 이해하고 요약에 반영합니다.
        - 전사문에 없는 내용을 지어내지 않습니다.

        용어집:
        \(glossaryBlock)
        """
    }

    static func singlePassPrompt(transcript: String) -> String {
        "다음 전사문의 핵심 내용을 3~7개의 불릿으로 요약하세요:\n\n\(transcript)"
    }

    static func mapPrompt(chunk: String, index: Int, total: Int) -> String {
        "다음은 한 녹음 전사문의 \(index)/\(total) 부분입니다. 이 부분의 핵심 내용을 3~5개의 불릿으로 요약하세요:\n\n\(chunk)"
    }

    static func reducePrompt(partials: String) -> String {
        "다음은 한 녹음의 부분 요약들입니다. 전체를 아우르는 최종 요약을 3~7개의 불릿으로 작성하세요:\n\n\(partials)"
    }

    private static func truncatedAtLineBoundary(_ text: String, limit: Int) -> String {
        guard text.count > limit else {
            return text
        }

        let head = String(text.prefix(limit))
        if let lastNewline = head.lastIndex(of: "\n") {
            return String(head[..<lastNewline])
        }
        return head
    }
}

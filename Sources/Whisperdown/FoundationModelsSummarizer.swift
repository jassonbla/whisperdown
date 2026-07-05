#if canImport(FoundationModels)
import Foundation
import FoundationModels

/// Apple 온디바이스 LLM 백엔드. FoundationModels 타입은 이 파일 밖으로 절대 새지 않는다 —
/// macOS 14 배포 타깃에서 weak-link + @available 게이트로만 접근한다.
@available(macOS 26.0, *)
struct FoundationModelsSummaryBackend: SummaryBackend {
    static func availability() -> SummaryAvailability {
        switch SystemLanguageModel.default.availability {
        case .available:
            return .available
        case .unavailable(let reason):
            return .modelUnavailable(String(describing: reason))
        }
    }

    func respond(instructions: String, prompt: String) async throws -> String {
        // 4k 윈도우 — 히스토리 누적을 피하려고 호출마다 새 세션을 만든다.
        let session = LanguageModelSession(instructions: instructions)
        let response = try await session.respond(to: prompt)
        return response.content
    }
}
#endif

import Foundation

/// 로컬 요약용 GGUF 모델 항목. WhisperModel과 같은 데이터 주도 카탈로그 —
/// RAM 요구량(minRAM/recommendedRAM)이 하드웨어 맞춤 배지의 근거.
struct SummaryModel: Identifiable, Sendable, Equatable {
    let fileName: String            // downloadURL.lastPathComponent와 반드시 일치 (다운로드 delegate 키)
    let displayName: String
    let repo: String                // HuggingFace repo 슬러그
    let approximateBytes: Int64     // HEAD 실측값 — 98% 크기 플로어 검증에 쓰이므로 정확해야 함
    let detailKey: String
    let contextTokens: Int
    let minRAMBytes: UInt64
    let recommendedRAMBytes: UInt64

    var id: String { fileName }

    var downloadURL: URL {
        URL(string: "https://huggingface.co/\(repo)/resolve/main/\(fileName)")!
    }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: approximateBytes, countStyle: .file)
    }

    var formattedContext: String {
        "\(contextTokens / 1024)K"
    }

    var formattedRecommendedRAM: String {
        ByteCountFormatter.string(fromByteCount: Int64(recommendedRAMBytes), countStyle: .memory)
    }
}

/// 이 Mac의 통합 메모리 대비 모델 적합도 (LM Studio 스타일 배지).
enum SummaryModelFit {
    case recommended
    case maySlow
    case insufficient

    static func fit(for model: SummaryModel) -> SummaryModelFit {
        let physical = ProcessInfo.processInfo.physicalMemory
        if physical >= model.recommendedRAMBytes {
            return .recommended
        }
        if physical >= model.minRAMBytes {
            return .maySlow
        }
        return .insufficient
    }
}

enum SummaryModelCatalog {
    private static let gib: UInt64 = 1_073_741_824

    /// llama.cpp 릴리스 핀. 다운로드 자산은 macOS arm64 tar.gz (llama-cli + dylib 형제 단일 디렉토리).
    static let runtimeVersion = "b9873"

    static let runtime = DownloadableItem(
        kind: .summaryRuntime,
        fileName: "llama-\(runtimeVersion)-bin-macos-arm64.tar.gz",
        downloadURL: URL(string: "https://github.com/ggml-org/llama.cpp/releases/download/\(runtimeVersion)/llama-\(runtimeVersion)-bin-macos-arm64.tar.gz")!,
        approximateBytes: 11_142_048,
        installedProbeURL: LlamaSummaryEngine.runtimeDirectory.appendingPathComponent("bin/llama-completion")
    )

    static let e4b = SummaryModel(
        fileName: "gemma-4-E4B-it-Q4_K_M.gguf",
        displayName: "Gemma 4 E4B",
        repo: "unsloth/gemma-4-E4B-it-GGUF",
        approximateBytes: 4_977_169_568,
        detailKey: "summary.model.detail.e4b",
        contextTokens: 131_072,
        minRAMBytes: 8 * gib,
        recommendedRAMBytes: 16 * gib
    )

    static let twelveB = SummaryModel(
        fileName: "gemma-4-12b-it-Q4_K_M.gguf",
        displayName: "Gemma 4 12B",
        repo: "unsloth/gemma-4-12b-it-GGUF",
        approximateBytes: 7_121_860_000,
        detailKey: "summary.model.detail.12b",
        contextTokens: 262_144,
        minRAMBytes: 16 * gib,
        recommendedRAMBytes: 24 * gib
    )

    static let moe26B = SummaryModel(
        fileName: "gemma-4-26B-A4B-it-UD-Q4_K_M.gguf",
        displayName: "Gemma 4 26B (MoE)",
        repo: "unsloth/gemma-4-26B-A4B-it-GGUF",
        approximateBytes: 16_947_539_744,
        detailKey: "summary.model.detail.26b",
        contextTokens: 262_144,
        minRAMBytes: 32 * gib,
        recommendedRAMBytes: 48 * gib
    )

    static let all: [SummaryModel] = [e4b, twelveB, moe26B]

    static var allDownloadItems: [DownloadableItem] {
        [runtime] + all.map(\.downloadItem)
    }
}

extension SummaryModel {
    var downloadItem: DownloadableItem {
        DownloadableItem(
            kind: .summaryModel,
            fileName: fileName,
            downloadURL: downloadURL,
            approximateBytes: approximateBytes,
            installedProbeURL: LlamaSummaryEngine.modelsDirectory.appendingPathComponent(fileName)
        )
    }
}

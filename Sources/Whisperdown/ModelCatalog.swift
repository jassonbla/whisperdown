import Foundation

/// 다운로드 가능한 whisper.cpp ggml 모델.
/// `fileName`은 WhisperCppTranscriptionEngine.preferredNames와 정확히 일치해야
/// 다운로드 완료 즉시 엔진이 자동 인식한다.
struct WhisperModel: Identifiable, Sendable, Equatable {
    let fileName: String
    let displayName: String
    let approximateBytes: Int64
    let detail: String
    let isRecommended: Bool

    var id: String { fileName }

    var downloadURL: URL {
        URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\(fileName)")!
    }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: approximateBytes, countStyle: .file)
    }
}

enum ModelCatalog {
    static let all: [WhisperModel] = [
        WhisperModel(
            fileName: "ggml-large-v3-turbo.bin",
            displayName: "Large v3 Turbo",
            approximateBytes: 1_624_555_275,
            detail: "정확도·속도 균형 최상",
            isRecommended: true
        ),
        WhisperModel(
            fileName: "ggml-large-v3.bin",
            displayName: "Large v3",
            approximateBytes: 3_095_033_483,
            detail: "최고 정확도 · 가장 느림",
            isRecommended: false
        ),
        WhisperModel(
            fileName: "ggml-medium.bin",
            displayName: "Medium",
            approximateBytes: 1_533_763_059,
            detail: "중간 정확도",
            isRecommended: false
        ),
        WhisperModel(
            fileName: "ggml-small.bin",
            displayName: "Small",
            approximateBytes: 487_601_967,
            detail: "빠름 · 저용량",
            isRecommended: false
        ),
        WhisperModel(
            fileName: "ggml-base.bin",
            displayName: "Base",
            approximateBytes: 147_951_465,
            detail: "테스트용 최소 모델",
            isRecommended: false
        )
    ]

    static var recommended: WhisperModel {
        all.first(where: \.isRecommended) ?? all[0]
    }
}

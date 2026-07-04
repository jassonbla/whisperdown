import Foundation

/// 다운로드 가능한 설치 항목의 공통 표현. whisper 모델과 화자 분리 자산을 하나의
/// 다운로드 매니저로 처리하기 위한 최소 일반화.
struct DownloadableItem: Identifiable, Sendable, Equatable {
    enum Kind: Sendable {
        case whisperModel                  // ≥98% 크기 + ggml 매직 → Models/
        case diarizationRuntime            // BZh 매직 → tar 추출 → bin/ + lib/ 이동
        case diarizationSegmentationModel  // BZh 매직 → tar 추출 → model.onnx 평탄화 이동
        case diarizationEmbeddingModel     // ≥98% 크기 → .onnx 그대로 이동
    }

    let kind: Kind
    /// 다운로드 URL의 lastPathComponent와 반드시 일치 — delegate 콜백의 식별 키.
    let fileName: String
    let downloadURL: URL
    let approximateBytes: Int64
    /// 이 파일이 존재하면 설치된 것으로 판정한다.
    let installedProbeURL: URL

    var id: String { fileName }
}

/// sherpa-onnx 화자 분리 사이드카 구성 자산 3종.
enum DiarizationCatalog {
    /// 릴리스 버전 고정 — 런타임 아카이브의 최상위 디렉토리명 추출에도 사용된다.
    static let runtimeVersion = "1.13.3"
    static let runtimeArchiveRoot = "sherpa-onnx-v\(runtimeVersion)-osx-arm64-shared"

    static let runtime = DownloadableItem(
        kind: .diarizationRuntime,
        fileName: "\(runtimeArchiveRoot).tar.bz2",
        downloadURL: URL(string: "https://github.com/k2-fsa/sherpa-onnx/releases/download/v\(runtimeVersion)/\(runtimeArchiveRoot).tar.bz2")!,
        approximateBytes: 26_159_941,
        installedProbeURL: SpeakerDiarizationEngine.runtimeDirectory
            .appendingPathComponent("bin/sherpa-onnx-offline-speaker-diarization")
    )

    static let segmentation = DownloadableItem(
        kind: .diarizationSegmentationModel,
        fileName: "sherpa-onnx-pyannote-segmentation-3-0.tar.bz2",
        downloadURL: URL(string: "https://github.com/k2-fsa/sherpa-onnx/releases/download/speaker-segmentation-models/sherpa-onnx-pyannote-segmentation-3-0.tar.bz2")!,
        approximateBytes: 6_958_444,
        installedProbeURL: SpeakerDiarizationEngine.modelsDirectory
            .appendingPathComponent("pyannote-segmentation-3-0.onnx")
    )

    static let embedding = DownloadableItem(
        kind: .diarizationEmbeddingModel,
        // 릴리스 태그의 "recongition" 오타는 실제 URL 그대로다 — 고치면 404.
        fileName: "nemo_en_titanet_small.onnx",
        downloadURL: URL(string: "https://github.com/k2-fsa/sherpa-onnx/releases/download/speaker-recongition-models/nemo_en_titanet_small.onnx")!,
        approximateBytes: 40_257_283,
        installedProbeURL: SpeakerDiarizationEngine.modelsDirectory
            .appendingPathComponent("nemo_en_titanet_small.onnx")
    )

    static let all: [DownloadableItem] = [runtime, segmentation, embedding]

    static var totalBytes: Int64 {
        all.reduce(0) { $0 + $1.approximateBytes }
    }
}

extension WhisperModel {
    var downloadItem: DownloadableItem {
        DownloadableItem(
            kind: .whisperModel,
            fileName: fileName,
            downloadURL: downloadURL,
            approximateBytes: approximateBytes,
            installedProbeURL: WhisperCppTranscriptionEngine.modelDirectory.appendingPathComponent(fileName)
        )
    }
}

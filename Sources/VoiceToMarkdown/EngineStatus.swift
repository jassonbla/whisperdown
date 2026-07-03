import Foundation

/// whisper.cpp 전사 파이프라인의 구성 요소별 상태.
/// UI(온보딩/설정/배지)가 "무엇이 없는지"를 개별 표시할 수 있게 한다.
struct EngineStatus: Equatable, Sendable {
    enum Item: Equatable, Sendable {
        case found(URL)
        case missing

        var isFound: Bool {
            if case .found = self {
                return true
            }

            return false
        }

        var url: URL? {
            if case .found(let url) = self {
                return url
            }

            return nil
        }
    }

    var whisperCLI: Item
    var ffmpeg: Item
    var model: Item

    var isFullyConfigured: Bool {
        whisperCLI.isFound && ffmpeg.isFound && model.isFound
    }

    /// 설치된 모델 파일명 (예: "ggml-large-v3-turbo.bin")
    var modelFileName: String? {
        model.url?.lastPathComponent
    }
}

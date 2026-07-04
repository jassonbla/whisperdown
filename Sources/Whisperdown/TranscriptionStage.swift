import Foundation

/// 화면 표시용 임시 상태. 디스크에 저장되지 않으며 RecordingStatus/Codable과 무관.
enum TranscriptionStage: Int, CaseIterable, Sendable {
    case converting
    case transcribing
    case finalizing
}

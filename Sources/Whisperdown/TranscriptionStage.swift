import Foundation

/// 화면 표시용 임시 상태. 디스크에 저장되지 않으며 RecordingStatus/Codable과 무관.
enum TranscriptionStage: Int, CaseIterable, Sendable {
    case converting
    case transcribing
    case finalizing
}

/// transcribing 스테이지 내부의 신호 없는 초반 구간 세분화용. 디스크 저장 없음.
/// rawValue 순서로 완료/진행중/대기 판정 (TranscriptionStage와 동일한 관례).
enum TranscriptionActivity: Int, CaseIterable, Sendable {
    case loadingModel   // whisper-cli 프로세스 시작 직후
    case analyzing      // stderr "main: processing" 라인 관측 시
}

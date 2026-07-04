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

/// 화자 분석(diarization) 스텝의 임시 상태. nil = 스텝 미표시. 디스크 저장 없음.
/// whisper와 병렬 실행되므로 스테퍼의 선형 인덱스가 아닌 자체 상태로 표시된다.
enum DiarizationStepState: Equatable, Sendable {
    case running
    case done(speakerCount: Int)
    case skipped        // 실패/타임아웃/빈 결과 — 조용한 폴백

    var isTerminal: Bool {
        self != .running
    }
}

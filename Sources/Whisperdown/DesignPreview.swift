import Foundation
import SwiftUI

enum DesignPreviewScenario: String {
    case ready
    case processing
    case diarizing   // processing + 화자 분석 스텝 (6행 스테퍼)
    case recording
    case failed
    case empty
}

struct DesignPreviewRootView: View {
    let scenario: DesignPreviewScenario

    @State private var selectedRecordingID: Recording.ID?
    @State private var searchText = ""

    init(scenario: DesignPreviewScenario = .ready) {
        self.scenario = scenario
        _selectedRecordingID = State(initialValue: scenario.initialSelectedRecordingID)
    }

    private var recordings: [Recording] {
        scenario.recordings.filter { recording in
            guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return true
            }

            return recording.title.localizedCaseInsensitiveContains(searchText)
                || recording.transcript.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var selectedRecording: Recording? {
        guard let selectedRecordingID else {
            return recordings.first
        }

        return scenario.recordings.first { $0.id == selectedRecordingID }
            ?? recordings.first
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0x2A / 255, green: 0x28 / 255, blue: 0x25 / 255),
                    Color(red: 0x1A / 255, green: 0x19 / 255, blue: 0x17 / 255)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            appContent
                .appWindowShell()
        }
    }

    private var appContent: some View {
        ZStack {
            AppBackdrop()
            SidebarChrome()

            HStack(spacing: 0) {
                SidebarView(
                    recordings: recordings,
                    selectedRecordingID: $selectedRecordingID,
                    searchText: $searchText,
                    isRecording: scenario.isRecording,
                    isProcessing: scenario.isProcessing,
                    onRecordTapped: {},
                    displayCount: 16
                )
                .frame(width: AppLayout.sidebarWidth)
                .frame(maxHeight: .infinity)

                DetailView(
                    recording: selectedRecording,
                    isRecording: scenario.isRecording,
                    isProcessing: scenario.isProcessing,
                    processingStage: scenario.isProcessing ? .transcribing : nil,
                    transcriptionProgress: scenario.isProcessing ? 0.42 : nil,
                    transcriptionStartedAt: scenario.isProcessing ? Date().addingTimeInterval(-95) : nil,
                    transcriptionActivity: nil,
                    partialTranscript: scenario.isProcessing
                        ? "안녕하세요. 오늘 회의에서는 다음 분기 로드맵과 담당자 배정을 이야기했습니다. 첫 번째 안건은 신규 온보딩 흐름 개선이었고, 두 번째 안건은 모델 다운로드 UX였습니다."
                        : nil,
                    diarizationState: scenario.showsDiarizationStep ? .running : nil,
                    showsDiarizationStep: scenario.showsDiarizationStep,
                    isWhisperReady: true,
                    elapsed: scenario.elapsed,
                    level: scenario.level,
                    levelHistory: (0..<AudioRecorder.levelHistoryCapacity).map {
                        0.15 + abs(sin(Double($0) * 0.35)) * scenario.level
                    },
                    liveTranscript: scenario.liveTranscript,
                    playbackElapsed: selectedRecording?.duration ?? 0,
                    isPlaybackPlaying: false,
                    onRecordTapped: {},
                    onPlayPauseTapped: {},
                    onSeekBackward: {},
                    onSeekForward: {},
                    onRetryTranscription: { _ in },
                    onOpenFolder: {},
                    onChooseFolder: {}
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            if scenario.isRecording {
                VStack {
                    HStack {
                        Spacer()
                        LiveRecordingWidget(
                            level: scenario.level,
                            elapsed: scenario.elapsed,
                            onStop: {}
                        )
                        .padding(.top, 14)
                        .padding(.trailing, 14)
                    }
                    Spacer()
                }
                .allowsHitTesting(false)
            }

            PreviewTrafficLights()
                .padding(.top, AppLayout.trafficLightTop)
                .padding(.leading, AppLayout.trafficLightLeading)
        }
        .background(Color.appCanvas)
    }
}

private extension DesignPreviewScenario {
    var recordings: [Recording] {
        switch self {
        case .empty:
            return []
        case .ready, .processing, .diarizing, .recording, .failed:
            return DesignPreviewData.recordings
        }
    }

    var isRecording: Bool {
        self == .recording
    }

    var isProcessing: Bool {
        self == .processing || self == .diarizing
    }

    var showsDiarizationStep: Bool {
        self == .diarizing
    }

    var elapsed: TimeInterval {
        isRecording ? 82 : 0
    }

    var level: Double {
        isRecording ? 0.72 : 0.34
    }

    var liveTranscript: String {
        isRecording ? "안녕하세요. 지금 실시간 전사가 들어오고 있습니다." : ""
    }

    var initialSelectedRecordingID: Recording.ID? {
        switch self {
        case .ready, .recording:
            return DesignPreviewData.readyRecordingID
        case .processing, .diarizing:
            return DesignPreviewData.processingRecordingID
        case .failed:
            return DesignPreviewData.failedRecordingID
        case .empty:
            return nil
        }
    }
}

private struct PreviewTrafficLights: View {
    var body: some View {
        HStack(spacing: 8) {
            trafficLight(color: Color(red: 0xED / 255, green: 0x6A / 255, blue: 0x5E / 255))
            trafficLight(color: Color(red: 0xF4 / 255, green: 0xBF / 255, blue: 0x4F / 255))
            trafficLight(color: Color(red: 0x61 / 255, green: 0xC5 / 255, blue: 0x54 / 255))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(false)
    }

    private func trafficLight(color: Color) -> some View {
        Circle()
            .fill(color)
            .frame(width: 12, height: 12)
            .overlay {
                Circle()
                    .strokeBorder(Palette.label.opacity(0.08), lineWidth: 0.5)
            }
    }
}

private enum DesignPreviewData {
    static let readyRecordingID = UUID(uuidString: "529B7147-654F-4C82-B4F1-03D67592F101") ?? UUID()
    static let processingRecordingID = UUID(uuidString: "C1BB221F-929B-4F4D-8A1C-4E9183798B21") ?? UUID()
    static let failedRecordingID = UUID(uuidString: "A0D1722A-72C4-4F2B-8FE2-DA8B7FCB8E2F") ?? UUID()

    static let recordings: [Recording] = [
        recording(
            id: readyRecordingID,
            title: "분기 로드맵 회의",
            createdAt: date(hour: 10, minute: 11),
            duration: 46,
            status: .ready,
            transcript: """
            오늘 회의에서는 다음 분기 로드맵을 논의했습니다. 온보딩 개선 건은 시안이 완료되었고 다음 주 배포 예정입니다.
            """,
            segments: [
                segment(
                    speaker: "Speaker 1",
                    startTime: 0,
                    endTime: 11,
                    text: "오늘 회의에서는 다음 분기 로드맵을 논의하겠습니다. 온보딩 개선 건부터 진행 상황을 공유해 주시죠."
                ),
                segment(
                    speaker: "Speaker 2",
                    startTime: 12,
                    endTime: 24,
                    text: "네, 온보딩 화면 시안은 지난 금요일에 완료했고 개발 리뷰를 거쳐 다음 주 초 배포 가능할 것으로 보입니다."
                ),
                segment(
                    speaker: "Speaker 1",
                    startTime: 25,
                    endTime: 34,
                    text: "좋습니다. 모델 다운로드 UX 건은 어떻게 되고 있나요?"
                ),
                segment(
                    speaker: "Speaker 2",
                    startTime: 35,
                    endTime: 46,
                    text: "그 부분은 아직 설계 단계입니다. 진행률 표시와 백그라운드 다운로드를 함께 검토 중입니다."
                )
            ]
        ),
        recording(
            id: processingRecordingID,
            title: "전사 중",
            createdAt: date(hour: 9, minute: 57),
            duration: 3,
            status: .processing,
            transcript: "",
            segments: []
        ),
        recording(
            id: failedRecordingID,
            title: "전사 실패 2026-07-03",
            createdAt: date(hour: 9, minute: 42),
            duration: 7,
            status: .failed,
            transcript: "",
            segments: []
        ),
        recording(
            id: UUID(uuidString: "7D6D419B-7E3F-4C0B-B84B-E58B2D118E95") ?? UUID(),
            title: "안녕하세요. 첫 녹음 테스트입니다",
            createdAt: date(hour: 1, minute: 7),
            duration: 9,
            status: .ready,
            transcript: "안녕하세요. 첫 녹음 테스트입니다.",
            segments: [
                segment(
                    speaker: "Speaker 1",
                    startTime: 0,
                    endTime: 9,
                    text: "안녕하세요. 첫 녹음 테스트입니다."
                )
            ]
        )
    ]

    private static let extraRecordings: [Recording] = [
        recording(
            id: UUID(uuidString: "1C266CB8-E118-43AF-ACB7-14983F00E004") ?? UUID(),
            title: "회의 메모",
            createdAt: date(hour: 9, minute: 41),
            duration: 41,
            status: .ready,
            transcript: "회의 메모",
            segments: []
        ),
        recording(
            id: UUID(uuidString: "5F3062B0-128B-4092-A40B-0E1979D4EC76") ?? UUID(),
            title: "아이디어 스케치",
            createdAt: date(hour: 9, minute: 28),
            duration: 18,
            status: .ready,
            transcript: "아이디어 스케치",
            segments: []
        ),
        recording(
            id: UUID(uuidString: "88A2DB40-703C-4D82-8713-F0D328967186") ?? UUID(),
            title: "짧은 통화",
            createdAt: date(hour: 9, minute: 16),
            duration: 27,
            status: .ready,
            transcript: "짧은 통화",
            segments: []
        ),
        recording(
            id: UUID(uuidString: "8805D5D9-D4F4-4648-96E0-1BB062FB8D50") ?? UUID(),
            title: "작업 로그",
            createdAt: date(hour: 9, minute: 3),
            duration: 54,
            status: .ready,
            transcript: "작업 로그",
            segments: []
        ),
        recording(
            id: UUID(uuidString: "B4074E1D-86E6-4F69-B86B-C420E30414C4") ?? UUID(),
            title: "음성 노트",
            createdAt: date(hour: 8, minute: 48),
            duration: 8,
            status: .ready,
            transcript: "음성 노트",
            segments: []
        ),
        recording(
            id: UUID(uuidString: "950E7C0C-3D33-455D-B071-5929D8104C13") ?? UUID(),
            title: "아침 기록",
            createdAt: date(hour: 8, minute: 35),
            duration: 72,
            status: .ready,
            transcript: "아침 기록",
            segments: []
        ),
        recording(
            id: UUID(uuidString: "17D75227-E986-4BB3-A1DA-A6D20E0DF682") ?? UUID(),
            title: "요약 후보",
            createdAt: date(hour: 8, minute: 21),
            duration: 19,
            status: .ready,
            transcript: "요약 후보",
            segments: []
        ),
        recording(
            id: UUID(uuidString: "D35474C9-B98C-4BC6-9A1C-AB7680067480") ?? UUID(),
            title: "새 녹음 8",
            createdAt: date(hour: 8, minute: 3),
            duration: 22,
            status: .ready,
            transcript: "새 녹음 8",
            segments: []
        ),
        recording(
            id: UUID(uuidString: "34041519-776B-4AB0-8383-13630C610586") ?? UUID(),
            title: "새 녹음 9",
            createdAt: date(hour: 7, minute: 52),
            duration: 17,
            status: .ready,
            transcript: "새 녹음 9",
            segments: []
        ),
        recording(
            id: UUID(uuidString: "177F0835-571D-4442-9F67-865D5E0433BE") ?? UUID(),
            title: "새 녹음 10",
            createdAt: date(hour: 7, minute: 40),
            duration: 25,
            status: .ready,
            transcript: "새 녹음 10",
            segments: []
        ),
        recording(
            id: UUID(uuidString: "26D9F6F1-B03A-477A-A9FB-F5DD0238C2BA") ?? UUID(),
            title: "새 녹음 11",
            createdAt: date(hour: 7, minute: 25),
            duration: 39,
            status: .ready,
            transcript: "새 녹음 11",
            segments: []
        )
    ]

    private static func recording(
        id: UUID,
        title: String,
        createdAt: Date,
        duration: TimeInterval,
        status: RecordingStatus,
        transcript: String,
        segments: [SpeakerSegment]
    ) -> Recording {
        Recording(
            id: id,
            title: title,
            createdAt: createdAt,
            duration: duration,
            markdownURL: URL(fileURLWithPath: "/tmp/\(title.markdownFilenameSafe).md"),
            audioURL: URL(fileURLWithPath: "/tmp/\(title.markdownFilenameSafe).m4a"),
            status: status,
            transcript: transcript,
            segments: segments,
            engineNote: status == .failed
                ? "낮은 신뢰도의 whisper.cpp 환각 문구로 판단되어 완료 처리하지 않았습니다."
                : "whisper.cpp ggml-large-v3-turbo.bin CPU safe mode"
        )
    }

    private static func segment(
        speaker: String,
        startTime: TimeInterval,
        endTime: TimeInterval,
        text: String
    ) -> SpeakerSegment {
        SpeakerSegment(
            speaker: speaker,
            startTime: startTime,
            endTime: endTime,
            text: text
        )
    }

    private static func date(hour: Int, minute: Int) -> Date {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(identifier: "Asia/Seoul")
        components.year = 2026
        components.month = 7
        components.day = 3
        components.hour = hour
        components.minute = minute
        return components.date ?? Date()
    }
}

import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case en, ko

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .en: return "English"
        case .ko: return "한국어"
        }
    }

    /// Non-View layers (RecordingProcessor, RecordingStore, TitleExtractor, engine/download
    /// error messages) read the language directly from UserDefaults at string-generation time.
    static var current: AppLanguage {
        AppLanguage(rawValue: UserDefaults.standard.string(forKey: "appLanguage") ?? "en") ?? .en
    }
}

private struct AppLanguageKey: EnvironmentKey {
    static let defaultValue: AppLanguage = .en
}

extension EnvironmentValues {
    var appLanguage: AppLanguage {
        get { self[AppLanguageKey.self] }
        set { self[AppLanguageKey.self] = newValue }
    }
}

enum L10n {
    static func t(_ key: String, _ language: AppLanguage) -> String {
        table[key]?[language] ?? table[key]?[.en] ?? key
    }

    private static let table: [String: [AppLanguage: String]] = [
        // MARK: Menu (WhisperdownApp)
        "menu.newRecording": [.en: "New Recording / Stop Recording", .ko: "새 녹음 / 녹음 정지"],
        "menu.search": [.en: "Search", .ko: "검색"],
        "menu.openMarkdownFolder": [.en: "Open Markdown Folder", .ko: "Markdown 폴더 열기"],

        // MARK: Alerts (RootView)
        "alert.deleteRecording.title": [.en: "Delete Recording", .ko: "녹음 삭제"],
        "alert.deleteRecording.message": [
            .en: "\"%@\" recording and its Markdown file will move to Trash.",
            .ko: "\"%@\" 녹음과 Markdown이 휴지통으로 이동합니다."
        ],
        "alert.recordingError.title": [.en: "Recording Error", .ko: "녹음 오류"],
        "alert.playbackError.title": [.en: "Playback Error", .ko: "재생 오류"],
        "action.delete": [.en: "Delete", .ko: "삭제"],
        "action.cancel": [.en: "Cancel", .ko: "취소"],
        "action.ok": [.en: "OK", .ko: "확인"],

        // MARK: Settings
        "settings.tab.general": [.en: "General", .ko: "일반"],
        "settings.tab.engine": [.en: "Transcription Engine", .ko: "전사 엔진"],
        "settings.language": [.en: "Language", .ko: "언어"],
        "settings.markdownFolder.label": [.en: "Markdown Save Folder", .ko: "Markdown 저장 폴더"],
        "settings.markdownFolder.change": [.en: "Change…", .ko: "변경…"],
        "settings.markdownFolder.hint": [
            .en: "Recorded audio and transcribed Markdown are saved to this folder.",
            .ko: "녹음 오디오와 전사 Markdown이 이 폴더에 저장됩니다."
        ],
        "settings.markdownFolder.pickerTitle": [.en: "Markdown Save Folder", .ko: "Markdown 저장 폴더"],
        "settings.engine.transcriptionModel": [.en: "Transcription Model", .ko: "전사 모델"],

        // MARK: Onboarding
        "onboarding.welcome.subtitle": [
            .en: "From recording to transcript, everything happens locally on this Mac.",
            .ko: "녹음부터 전사까지, 모든 처리는 이 Mac 안에서만 이루어집니다."
        ],
        "onboarding.welcome.start": [.en: "Get Started", .ko: "시작하기"],
        "onboarding.diagnostics.title": [.en: "Check Transcription Engine", .ko: "전사 엔진 확인"],
        "onboarding.diagnostics.subtitle": [
            .en: "Check the components needed for high-quality local transcription (whisper.cpp).",
            .ko: "고품질 로컬 전사(whisper.cpp)에 필요한 구성 요소를 확인합니다."
        ],
        "onboarding.diagnostics.appleSpeechNote": [
            .en: "You can use Apple Speech for temporary transcription before installing.",
            .ko: "설치 전에도 Apple Speech로 임시 전사를 사용할 수 있습니다."
        ],
        "onboarding.diagnostics.skip": [.en: "Skip", .ko: "건너뛰기"],
        "onboarding.diagnostics.next": [.en: "Next: Choose Model", .ko: "다음: 모델 선택"],
        "onboarding.modelPicker.title": [.en: "Download Transcription Model", .ko: "전사 모델 다운로드"],
        "onboarding.modelPicker.subtitle": [
            .en: "Models are stored on this Mac and work offline. You can change this later in Settings (⌘,).",
            .ko: "모델은 이 Mac에 저장되며 오프라인으로 동작합니다. 나중에 설정(⌘,)에서 변경할 수 있습니다."
        ],
        "onboarding.modelPicker.back": [.en: "Back", .ko: "이전"],
        "onboarding.modelPicker.continueBackground": [.en: "Continue in Background", .ko: "백그라운드에서 계속"],
        "onboarding.modelPicker.done": [.en: "Done", .ko: "완료"],

        // MARK: Engine diagnostics / model list (shared by onboarding + Settings)
        "engine.diagnostics.notInstalled": [.en: "Not installed", .ko: "설치되지 않음"],
        "engine.diagnostics.model": [.en: "Transcription Model", .ko: "전사 모델"],
        "engine.diagnostics.needsDownload": [.en: "Download needed", .ko: "다운로드 필요"],
        "engine.diagnostics.installHint": [
            .en: "Install the required tools via Homebrew:",
            .ko: "Homebrew로 필요한 도구를 설치하세요:"
        ],
        "engine.diagnostics.copy": [.en: "Copy", .ko: "복사"],
        "engine.diagnostics.copied": [.en: "Copied", .ko: "복사됨"],
        "engine.diagnostics.recheck": [.en: "Check Again", .ko: "다시 확인"],
        "model.recommended": [.en: "Recommended", .ko: "추천"],
        "model.download.help": [.en: "Download", .ko: "다운로드"],
        "model.retry": [.en: "Retry", .ko: "재시도"],
        "model.installed": [.en: "Installed", .ko: "설치됨"],

        // MARK: Model catalog details
        "model.detail.largeV3Turbo": [.en: "Best balance of accuracy and speed", .ko: "정확도·속도 균형 최상"],
        "model.detail.largeV3": [.en: "Highest accuracy · Slowest", .ko: "최고 정확도 · 가장 느림"],
        "model.detail.medium": [.en: "Medium accuracy", .ko: "중간 정확도"],
        "model.detail.small": [.en: "Fast · Small size", .ko: "빠름 · 저용량"],
        "model.detail.base": [.en: "Minimal model for testing", .ko: "테스트용 최소 모델"],

        // MARK: Model download errors
        "error.download.cancelled": [.en: "Download was cancelled.", .ko: "다운로드가 취소되었습니다."],
        "error.download.network": [.en: "Network error: %@", .ko: "네트워크 오류: %@"],
        "error.download.tooSmall": [
            .en: "Downloaded file is incomplete (expected %@, got %@).",
            .ko: "다운로드된 파일이 불완전합니다 (예상 %@, 실제 %@)."
        ],
        "error.download.invalidFormat": [
            .en: "The model file format is invalid (ggml magic mismatch).",
            .ko: "모델 파일 형식이 올바르지 않습니다 (ggml 매직 불일치)."
        ],
        "error.download.fileSystem": [.en: "Failed to save file: %@", .ko: "파일 저장 실패: %@"],

        // MARK: DetailView
        "detail.help.engineSettings": [.en: "Transcription Engine Settings", .ko: "전사 엔진 설정"],
        "detail.help.openMarkdownFolder": [.en: "Open Markdown Folder", .ko: "Markdown 폴더 열기"],
        "detail.help.chooseFolder": [.en: "Choose Save Folder", .ko: "저장 폴더 선택"],
        "detail.badge.recording": [.en: "Recording", .ko: "녹음 중"],
        "detail.badge.appleSpeechTemp": [.en: "Apple Speech (Temporary)", .ko: "Apple Speech (임시)"],
        "detail.badge.whisperLocal": [.en: "Whisper Local", .ko: "Whisper 로컬"],
        "detail.badge.transcribed": [.en: "Transcribed", .ko: "전사 완료"],
        "detail.badge.transcribing": [.en: "Transcribing", .ko: "전사 중"],
        "detail.badge.retryNeeded": [.en: "Retry Needed", .ko: "재시도 필요"],
        "detail.badge.reviewNeeded": [.en: "Review Needed", .ko: "검토 필요"],
        "detail.live.waitingLabel": [.en: "Waiting for live transcript", .ko: "실시간 전사 대기"],
        "detail.live.label": [.en: "Live Transcript", .ko: "실시간 전사"],
        "detail.live.placeholder": [
            .en: "Live transcript will appear here once you start speaking. The final Markdown re-transcribes the full audio after recording ends.",
            .ko: "말을 시작하면 이 영역에 임시 전사가 표시됩니다. 최종 Markdown은 녹음 종료 후 전체 오디오로 다시 전사합니다."
        ],
        "detail.status.interrupted.title": [.en: "Transcription Interrupted", .ko: "전사 중단됨"],
        "detail.status.interrupted.message": [
            .en: "The transcription task is no longer running. The original audio is preserved so you can retry.",
            .ko: "전사 작업이 더 이상 실행 중이지 않습니다. 원본 오디오는 보관되어 있으니 다시 시도할 수 있습니다."
        ],
        "detail.status.reviewNeeded.title": [.en: "Review Needed", .ko: "전사 확인 필요"],
        "detail.status.noRecording.title": [.en: "No Recording", .ko: "녹음 없음"],
        "detail.status.noRecording.message": [
            .en: "Press ⌘N or the New Recording button in the sidebar to get started.",
            .ko: "⌘N 또는 사이드바의 새 녹음 버튼으로 시작하세요."
        ],
        "detail.retryTranscription": [.en: "Retry Transcription", .ko: "전사 재시도"],
        "detail.transport.help.seekBackward": [.en: "Back 10 seconds", .ko: "10초 뒤로"],
        "detail.transport.help.seekForward": [.en: "Forward 10 seconds", .ko: "10초 앞으로"],
        "detail.transport.help.stopRecording": [.en: "Stop Recording", .ko: "녹음 정지"],
        "detail.transport.help.pause": [.en: "Pause", .ko: "일시정지"],
        "detail.transport.help.play": [.en: "Play", .ko: "재생"],
        "detail.transcribing.message": [
            .en: "The local model is organizing the audio into Markdown.",
            .ko: "로컬 모델이 오디오를 Markdown으로 정리하고 있습니다."
        ],

        // MARK: SidebarView
        "sidebar.recentItems": [.en: "Recent", .ko: "최근 항목"],
        "sidebar.allRecordings": [.en: "All Recordings", .ko: "모든 녹음 항목"],
        "sidebar.countSuffix": [.en: "%d items", .ko: "%d개"],
        "sidebar.searching": [.en: "Search Results", .ko: "검색 결과"],
        "sidebar.library": [.en: "Library", .ko: "라이브러리"],
        "sidebar.search.placeholder": [.en: "Search", .ko: "검색"],
        "sidebar.newRecording": [.en: "New Recording", .ko: "새 녹음"],
        "sidebar.bottomStatus.recording": [.en: "Recording", .ko: "기록 중"],
        "sidebar.bottomStatus.transcribing": [.en: "Transcribing", .ko: "전사 처리 중"],
        "sidebar.bottomStatus.ready": [.en: "Ready", .ko: "준비됨"],
        "sidebar.modelDownloadProgress": [.en: "Downloading model %d%%", .ko: "모델 다운로드 중 %d%%"],
        "sidebar.row.reviewNeeded": [.en: "Review Needed", .ko: "확인 필요"],
        "sidebar.empty.noResults": [.en: "No Results", .ko: "검색 결과 없음"],
        "sidebar.empty.noRecordings": [.en: "No Recordings", .ko: "녹음 없음"],
        "sidebar.empty.startHint": [.en: "to start your first recording", .ko: "으로 첫 녹음을 시작하세요"],

        // MARK: Controls
        "controls.recordButton.stop": [.en: "Stop Recording", .ko: "녹음 종료"],
        "controls.recordButton.start": [.en: "Start Recording", .ko: "녹음 시작"],
        "controls.search.placeholder": [.en: "Title, transcript", .ko: "제목, 전사문"],

        // MARK: RecordingProcessor
        "processor.preparing": [.en: "Preparing Transcription", .ko: "전사 준비 중"],
        "processor.transcribingPlaceholder": [.en: "Preparing to transcribe.", .ko: "전사를 준비하고 있습니다."],
        "processor.transcribingNote": [.en: "Transcription in progress", .ko: "전사 처리 중"],
        "processor.failureTitlePrefix": [.en: "Transcription Failed %@", .ko: "전사 실패 %@"],

        // MARK: RecordingStore migration notes
        "store.migration.interrupted": [
            .en: "The transcription task did not complete because the app or local engine was interrupted. The original audio is preserved — please retry transcription.",
            .ko: "전사 작업이 앱 또는 로컬 엔진 중단으로 완료되지 않았습니다. 원본 오디오는 보관되어 있으니 전사 재시도를 실행해 주세요."
        ],
        "store.migration.liveDraftBug": [
            .en: "This needs to be re-transcribed due to a previous bug where the live transcript draft was saved as final. The original audio is preserved.",
            .ko: "실시간 전사 draft가 최종 전사본으로 저장된 이전 버그의 영향으로 재전사가 필요합니다. 원본 오디오는 보관되어 있습니다."
        ],
        "store.migration.legacyPlaceholder": [
            .en: "This item was created before the transcription engine was connected, so it has no real transcript. Re-record in the new version to attempt transcription.",
            .ko: "이 항목은 전사 엔진 연결 전 생성되어 실제 전사문이 없습니다. 새 버전에서 다시 녹음하면 전사를 시도합니다."
        ],
        "store.migration.hallucination": [
            .en: "This was judged to be a low-confidence whisper.cpp hallucination and was not marked complete. The original audio is preserved.",
            .ko: "낮은 신뢰도의 whisper.cpp 환각 문구로 판단되어 완료 처리하지 않았습니다. 원본 오디오는 보관되어 있습니다."
        ],

        // MARK: TitleExtractor
        "titleExtractor.newRecordingPrefix": [.en: "New Recording %@", .ko: "새 녹음 %@"],
        "titleExtractor.newRecording": [.en: "New Recording", .ko: "새 녹음"],

        // MARK: WhisperCppTranscriptionEngine errors
        "error.engine.executableMissing": [
            .en: "Could not find the whisper.cpp executable whisper-cli. Install whisper-cpp via Homebrew or set WHISPERDOWN_WHISPER_CLI.",
            .ko: "whisper.cpp 실행 파일 whisper-cli를 찾지 못했습니다. Homebrew whisper-cpp를 설치하거나 WHISPERDOWN_WHISPER_CLI를 설정해 주세요."
        ],
        "error.engine.modelMissing": [
            .en: "Could not find a whisper.cpp model file. Place a ggml model in %@ or set WHISPERDOWN_WHISPER_MODEL.",
            .ko: "whisper.cpp 모델 파일을 찾지 못했습니다. ggml 모델을 %@에 넣거나 WHISPERDOWN_WHISPER_MODEL을 설정해 주세요."
        ],
        "error.engine.ffmpegMissing": [
            .en: "Could not find ffmpeg, which is required for audio conversion.",
            .ko: "오디오 변환에 필요한 ffmpeg를 찾지 못했습니다."
        ],
        "error.engine.emptyTranscript": [
            .en: "The whisper.cpp transcription result was empty.",
            .ko: "whisper.cpp 전사 결과가 비어 있습니다."
        ],
        "error.engine.lowConfidence": [
            .en: "Transcription confidence was too low to mark complete. Detected phrase: %@",
            .ko: "전사 결과 신뢰도가 낮아 완료 처리하지 않았습니다. 감지된 문구: %@"
        ],
        "error.engine.processLaunchFailed": [
            .en: "Failed to launch %@: %@",
            .ko: "%@ 실행에 실패했습니다: %@"
        ],
        "error.engine.processFailed": [
            .en: "An error occurred while running %@: %@",
            .ko: "%@ 실행 중 오류가 발생했습니다: %@"
        ],

        // MARK: Audio recording / playback errors
        "error.mic.permissionRequired": [.en: "Microphone access is required.", .ko: "마이크 접근 권한이 필요합니다."],
        "error.playback.failed": [.en: "Failed to play audio: %@", .ko: "오디오를 재생하지 못했습니다: %@"],
        "error.playback.startFailed": [.en: "Failed to start audio playback.", .ko: "오디오 재생을 시작하지 못했습니다."]
    ]
}

import Foundation

extension Notification.Name {
    static let openMarkdownFolderRequested = Notification.Name("openMarkdownFolderRequested")
    /// 엔진 설정(진단/모델 다운로드) 화면 열기 요청 — DetailView 배지·Settings에서 발신, RootView가 수신.
    static let openEngineSetupRequested = Notification.Name("openEngineSetupRequested")
    /// Settings에서 저장 폴더가 바뀜 — RecordingStore가 수신해 UserDefaults 재로드.
    static let markdownDirectoryChanged = Notification.Name("markdownDirectoryChanged")
    /// ⌘N — 녹음 시작/정지 토글.
    static let toggleRecordingRequested = Notification.Name("toggleRecordingRequested")
    /// ⌘F — 사이드바 검색 필드 포커스.
    static let focusSearchRequested = Notification.Name("focusSearchRequested")
    /// Settings/온보딩의 "용어집 편집" — RootView가 수신해 인앱 용어집 패널을 연다.
    static let openGlossaryRequested = Notification.Name("openGlossaryRequested")
    /// 상세 topBar의 책 아이콘 — RootView가 수신해 용어집 패널을 토글한다.
    static let toggleGlossaryPanelRequested = Notification.Name("toggleGlossaryPanelRequested")
    /// Settings에서 요약 엔진/모델 선택 변경 — RootView가 수신해 가용성 재계산.
    static let summaryBackendChanged = Notification.Name("summaryBackendChanged")
}

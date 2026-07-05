import SwiftUI

struct RootView: View {
    @StateObject private var store = RecordingStore()
    @StateObject private var recorder = AudioRecorder()
    @StateObject private var processor = RecordingProcessor()
    @StateObject private var playback = AudioPlaybackController()
    @StateObject private var summaryCoordinator = SummaryCoordinator()
    @ObservedObject private var modelManager = ModelDownloadManager.shared

    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("appLanguage") private var appLanguageRaw = AppLanguage.en.rawValue
    @AppStorage("isGlossaryPanelOpen") private var isGlossaryPanelOpen = false

    private var language: AppLanguage {
        AppLanguage(rawValue: appLanguageRaw) ?? .en
    }

    @State private var selectedRecordingID: Recording.ID?
    @State private var searchText = ""
    @State private var onboardingStep: OnboardingSheet.Step?
    @State private var isWhisperReady = WhisperCppTranscriptionEngine().status().isFullyConfigured
    @State private var isDiarizationReady = SpeakerDiarizationEngine().isConfigured
    @State private var summaryAvailability = SummaryEngine.availability()
    @State private var pendingDeletion: Recording?

    private var filteredRecordings: [Recording] {
        let recordings = store.recordings
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return recordings
        }

        return recordings.filter {
            $0.title.localizedCaseInsensitiveContains(searchText)
                || $0.transcript.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var selectedRecording: Recording? {
        guard let selectedRecordingID else {
            return filteredRecordings.first
        }

        return store.recordings.first { $0.id == selectedRecordingID }
            ?? filteredRecordings.first
    }

    var body: some View {
        layout
            .environment(\.appLanguage, language)
            .appWindowShell()
            .ignoresSafeArea()
            .background(Color.clear)
            .background(WindowChromeConfigurator())
            .background(floatingRecorderPresenter)
            .background(deleteShortcutButton)
            .alert(
                L10n.t("alert.deleteRecording.title", language),
                isPresented: deletionAlertBinding,
                presenting: pendingDeletion
            ) { recording in
                Button(L10n.t("action.delete", language), role: .destructive) {
                    confirmDeletion(recording)
                }
                Button(L10n.t("action.cancel", language), role: .cancel) {}
            } message: { recording in
                Text(String(format: L10n.t("alert.deleteRecording.message", language), recording.title))
            }
            .alert(L10n.t("alert.recordingError.title", language), isPresented: errorAlertBinding) {
                Button(L10n.t("action.ok", language)) {
                    recorder.errorMessage = nil
                }
            } message: {
                Text(recorder.errorMessage ?? "")
            }
            .alert(L10n.t("alert.playbackError.title", language), isPresented: playbackErrorAlertBinding) {
                Button(L10n.t("action.ok", language)) {
                    playback.errorMessage = nil
                }
            } message: {
                Text(playback.errorMessage ?? "")
            }
            .onChange(of: store.recordings) {
                if selectedRecordingID == nil {
                    selectedRecordingID = store.recordings.first?.id
                }
            }
            .onChange(of: selectedRecordingID) {
                playback.stop()
            }
            .onChange(of: modelManager.states) {
                isWhisperReady = WhisperCppTranscriptionEngine().status().isFullyConfigured
                isDiarizationReady = SpeakerDiarizationEngine().isConfigured
            }
            .onReceive(NotificationCenter.default.publisher(for: .openEngineSetupRequested)) { _ in
                onboardingStep = .diagnostics
            }
            .onReceive(NotificationCenter.default.publisher(for: .toggleRecordingRequested)) { _ in
                toggleRecording()
            }
            .onReceive(NotificationCenter.default.publisher(for: .openGlossaryRequested)) { _ in
                isGlossaryPanelOpen = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .toggleGlossaryPanelRequested)) { _ in
                isGlossaryPanelOpen.toggle()
            }
            .animation(MotionToken.quick, value: selectedRecordingID)
            .onAppear {
                isWhisperReady = WhisperCppTranscriptionEngine().status().isFullyConfigured
                isDiarizationReady = SpeakerDiarizationEngine().isConfigured
                summaryAvailability = SummaryEngine.availability()
                if !hasCompletedOnboarding {
                    onboardingStep = .welcome
                }

                applyDeveloperHooks()
            }
            .sheet(item: $onboardingStep) { step in
                OnboardingSheet(manager: modelManager, initialStep: step) {
                    // 닫힘 = 온보딩 완료로 간주 (배지/설정에서 언제든 재진입 가능)
                    hasCompletedOnboarding = true
                    onboardingStep = nil
                    isWhisperReady = WhisperCppTranscriptionEngine().status().isFullyConfigured
                    isDiarizationReady = SpeakerDiarizationEngine().isConfigured
                }
            }
    }

    private var layout: some View {
        ZStack {
            AppBackdrop()
            SidebarChrome()

            HStack(spacing: 0) {
                sidebar
                detail
                if isGlossaryPanelOpen {
                    GlossaryPanel(store: store, isOpen: $isGlossaryPanelOpen)
                        .transition(.move(edge: .trailing))
                }
            }
        }
        .animation(MotionToken.quick, value: isGlossaryPanelOpen)
    }

    private var sidebar: some View {
        SidebarView(
            recordings: filteredRecordings,
            selectedRecordingID: $selectedRecordingID,
            searchText: $searchText,
            isRecording: recorder.isRecording,
            isProcessing: processor.isProcessing,
            onRecordTapped: toggleRecording,
            modelDownloadFraction: modelManager.activeDownloadFraction,
            onDeleteRequested: { pendingDeletion = $0 }
        )
        .frame(width: AppLayout.sidebarWidth)
        .frame(maxHeight: .infinity)
    }

    private var detail: some View {
        DetailView(
            recording: selectedRecording,
            isRecording: recorder.isRecording,
            isProcessing: processor.isProcessing,
            processingStage: processor.processingStage,
            transcriptionProgress: processor.transcriptionProgress,
            transcriptionStartedAt: processor.transcriptionStartedAt,
            transcriptionActivity: processor.transcriptionActivity,
            partialTranscript: processor.partialTranscript,
            diarizationState: processor.diarizationState,
            showsDiarizationStep: isWhisperReady && isDiarizationReady,
            isWhisperReady: isWhisperReady,
            elapsed: recorder.elapsed,
            level: recorder.level,
            levelHistory: recorder.levelHistory,
            liveTranscript: recorder.liveTranscript,
            playbackElapsed: playback.currentURL == selectedRecording?.audioURL ? playback.currentTime : selectedRecording?.duration ?? 0,
            isPlaybackPlaying: playback.currentURL == selectedRecording?.audioURL && playback.isPlaying,
            onRecordTapped: toggleRecording,
            onPlayPauseTapped: togglePlayback,
            onSeekBackward: { playback.seek(by: -10) },
            onSeekForward: { playback.seek(by: 10) },
            onRetryTranscription: retryTranscription,
            onOpenFolder: store.openMarkdownFolder,
            onChooseFolder: store.chooseMarkdownDirectory,
            summaryPhase: summaryCoordinator.phase(for: selectedRecording?.id),
            canGenerateSummary: summaryAvailability.isAvailable,
            onGenerateSummary: { summaryCoordinator.summarize(recording: $0, store: store) },
            isGlossaryPanelOpen: isGlossaryPanelOpen
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var floatingRecorderPresenter: some View {
        FloatingRecorderPanelPresenter(
            isPresented: recorder.isRecording,
            level: recorder.level,
            elapsed: recorder.elapsed,
            onStop: toggleRecording,
            language: language
        )
    }

    /// ⌘⌫ — 선택된 녹음 삭제 (확인 alert 경유)
    private var deleteShortcutButton: some View {
        Button("") {
            if !recorder.isRecording, let recording = selectedRecording {
                pendingDeletion = recording
            }
        }
        .keyboardShortcut(.delete, modifiers: [.command])
        .hidden()
    }

    private var deletionAlertBinding: Binding<Bool> {
        Binding(
            get: { pendingDeletion != nil },
            set: { if !$0 { pendingDeletion = nil } }
        )
    }

    private func confirmDeletion(_ recording: Recording) {
        summaryCoordinator.cancel(recording.id)
        if selectedRecordingID == recording.id {
            playback.stop()
            selectedRecordingID = nil
        }
        store.remove(recording)
        pendingDeletion = nil
    }

    private var errorAlertBinding: Binding<Bool> {
        Binding(
            get: { recorder.errorMessage != nil },
            set: { newValue in
                if !newValue {
                    recorder.errorMessage = nil
                }
            }
        )
    }

    private var playbackErrorAlertBinding: Binding<Bool> {
        Binding(
            get: { playback.errorMessage != nil },
            set: { newValue in
                if !newValue {
                    playback.errorMessage = nil
                }
            }
        )
    }

    /// 개발/검증용 훅. 화면 포커스 없이 특정 상태를 재현한다.
    /// - WHISPERDOWN_ONBOARDING_STEP=welcome|diagnostics|modelPicker : 온보딩 특정 스텝 강제
    /// - WHISPERDOWN_AUTODOWNLOAD=<fileName> : 해당 모델 자동 다운로드 시작
    private func applyDeveloperHooks() {
        let environment = ProcessInfo.processInfo.environment

        if let raw = environment["WHISPERDOWN_ONBOARDING_STEP"],
           let step = OnboardingSheet.Step(rawValue: raw) {
            onboardingStep = step
        }

        if let fileName = environment["WHISPERDOWN_AUTODOWNLOAD"],
           let model = ModelCatalog.all.first(where: { $0.fileName == fileName }) {
            modelManager.startDownload(model)
        }
    }

    private func toggleRecording() {
        if recorder.isRecording {
            guard let audio = recorder.stop() else {
                return
            }

            Task {
                let recording = await processor.process(audio: audio, store: store) { pending in
                    selectedRecordingID = pending.id
                }
                selectedRecordingID = recording?.id
                if let recording, recording.status == .ready {
                    summaryCoordinator.summarize(recording: recording, store: store)
                }
            }
        } else {
            playback.stop()
            let outputURL = store.uniqueAudioURL(for: Date())
            Task {
                await recorder.start(outputURL: outputURL)
            }
        }
    }

    private func togglePlayback() {
        guard !recorder.isRecording,
              !processor.isProcessing,
              let recording = selectedRecording else {
            return
        }

        playback.toggle(url: recording.audioURL)
    }

    private func retryTranscription(_ recording: Recording) {
        guard !recorder.isRecording, !processor.isProcessing else {
            return
        }

        // 재전사 시 이전 스냅샷 기반 요약은 무효 — 취소 후 새 결과로 다시 요약한다.
        summaryCoordinator.cancel(recording.id)
        selectedRecordingID = recording.id
        Task {
            let updated = await processor.retry(recording: recording, store: store)
            selectedRecordingID = updated?.id
            if let updated, updated.status == .ready {
                summaryCoordinator.summarize(recording: updated, store: store)
            }
        }
    }
}

struct SidebarChrome: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 0) {
            SidebarSurface()
                .frame(width: AppLayout.sidebarWidth)
                .overlay(alignment: .trailing) {
                    Rectangle()
                        .fill(Color.hairline.opacity(colorScheme == .dark ? 0.78 : 0.92))
                        .frame(width: 1)
                        .allowsHitTesting(false)
                }

            Spacer(minLength: 0)
        }
        .ignoresSafeArea(.container, edges: [.top, .bottom])
    }
}

struct AppBackdrop: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Color.appCanvas
            .overlay(alignment: .top) {
                LinearGradient(
                    colors: [
                        colorScheme == .dark ? Color.white.opacity(0.02) : Palette.surface.opacity(0.060),
                        .clear
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 96)
                .allowsHitTesting(false)
            }
        .ignoresSafeArea()
    }
}

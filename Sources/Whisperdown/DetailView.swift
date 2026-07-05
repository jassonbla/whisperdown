import AppKit
import SwiftUI

struct DetailView: View {
    @Environment(\.appLanguage) private var language

    let recording: Recording?
    let isRecording: Bool
    let isProcessing: Bool
    let processingStage: TranscriptionStage?
    let transcriptionProgress: Double?
    let transcriptionStartedAt: Date?
    let transcriptionActivity: TranscriptionActivity?
    let partialTranscript: String?
    let diarizationState: DiarizationStepState?
    let showsDiarizationStep: Bool
    let isWhisperReady: Bool
    let elapsed: TimeInterval
    let level: Double
    let levelHistory: [Double]
    let liveTranscript: String
    let playbackElapsed: TimeInterval
    let isPlaybackPlaying: Bool
    let onRecordTapped: () -> Void
    let onPlayPauseTapped: () -> Void
    let onSeekBackward: () -> Void
    let onSeekForward: () -> Void
    let onRetryTranscription: (Recording) -> Void
    let onOpenFolder: () -> Void
    let onChooseFolder: () -> Void
    /// 스냅샷 시나리오용 초기값 — 런타임 토글은 rawMarkdownOverride가 담당.
    var initialShowsRawMarkdown: Bool = false
    var summaryPhase: SummaryPhase? = nil
    var canGenerateSummary: Bool = false
    var onGenerateSummary: (Recording) -> Void = { _ in }
    var isGlossaryPanelOpen: Bool = false

    @State private var rawMarkdownOverride: Bool?
    @State private var didCopyMarkdown = false

    private var showsRawMarkdown: Bool {
        rawMarkdownOverride ?? initialShowsRawMarkdown
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar

            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    titleBlock
                    transcriptBlock
                }
                .animation(MotionToken.quick, value: isRecording)
                .frame(maxWidth: AppMetric.transcriptMaxWidth, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.horizontal, AppLayout.detailHorizontalPadding)
                .padding(.top, 26)
                .padding(.bottom, Spacing.xl)
                .background(OverlayScrollerConfigurator())
            }
            .scrollIndicators(.hidden)

            transport
        }
        .background(Color.appSurface)
        .onChange(of: recording?.id) {
            rawMarkdownOverride = nil
            didCopyMarkdown = false
        }
    }

    private var topBar: some View {
        HStack(spacing: Spacing.sm) {
            Button {
                NotificationCenter.default.post(name: .openEngineSetupRequested, object: nil)
            } label: {
                ModeBadge(title: modeBadgeTitle, systemName: modeBadgeIcon)
            }
            .buttonStyle(.plain)
            .help(L10n.t("detail.help.engineSettings", language))

            Spacer()

            HStack(spacing: Spacing.xs) {
                if let recording, recording.status == .ready, !isRecording, !isProcessing {
                    if canGenerateSummary, recording.summary == nil, summaryPhase != .running {
                        IconButton(systemName: "sparkles") {
                            onGenerateSummary(recording)
                        }
                        .help(L10n.t("detail.help.generateSummary", language))
                    }

                    IconButton(
                        systemName: showsRawMarkdown ? "text.bubble" : "doc.plaintext",
                        isActive: showsRawMarkdown
                    ) {
                        rawMarkdownOverride = !showsRawMarkdown
                    }
                    .help(L10n.t(showsRawMarkdown ? "detail.help.showSegments" : "detail.help.showRawMarkdown", language))

                    IconButton(systemName: didCopyMarkdown ? "checkmark" : "doc.on.doc") {
                        copyMarkdown(for: recording)
                    }
                    .help(L10n.t(didCopyMarkdown ? "detail.help.copied" : "detail.help.copyMarkdown", language))

                    IconButton(systemName: "arrow.up.right.square") {
                        revealInFinder(for: recording)
                    }
                    .help(L10n.t("detail.help.revealInFinder", language))

                    IconButton(systemName: "arrow.clockwise") {
                        onRetryTranscription(recording)
                    }
                    .help(L10n.t("detail.help.retryTranscription", language))
                }
                IconButton(systemName: "character.book.closed", isActive: isGlossaryPanelOpen) {
                    NotificationCenter.default.post(name: .toggleGlossaryPanelRequested, object: nil)
                }
                .help(L10n.t("detail.help.toggleGlossary", language))
                IconButton(systemName: "folder", action: onOpenFolder)
                    .help(L10n.t("detail.help.openMarkdownFolder", language))
                IconButton(systemName: "gearshape", action: onChooseFolder)
                    .help(L10n.t("detail.help.chooseFolder", language))
            }
        }
        .padding(.horizontal, Spacing.lg)
        .frame(height: AppLayout.titleBarHeight)
        .background(Color.appSurface)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.hairline)
                .frame(height: 1)
                .allowsHitTesting(false)
        }
    }

    private var modeBadgeTitle: String {
        if isRecording {
            return L10n.t("detail.badge.recording", language)
        }

        if !isWhisperReady {
            return L10n.t("detail.badge.appleSpeechTemp", language)
        }

        guard let recording else {
            return "Voice"
        }

        switch recording.status {
        case .ready:
            return recording.engineNote.contains("whisper.cpp") ? L10n.t("detail.badge.whisperLocal", language) : L10n.t("detail.badge.transcribed", language)
        case .processing:
            return isProcessing ? L10n.t("detail.badge.transcribing", language) : L10n.t("detail.badge.retryNeeded", language)
        case .failed:
            return L10n.t("detail.badge.reviewNeeded", language)
        }
    }

    private var modeBadgeIcon: String {
        if isRecording {
            return "record.circle"
        }

        if !isWhisperReady {
            return "exclamationmark.circle"
        }

        guard let recording else {
            return "waveform"
        }

        switch recording.status {
        case .ready:
            return "checkmark.circle"
        case .processing:
            return isProcessing ? "waveform" : "exclamationmark.circle"
        case .failed:
            return "exclamationmark.circle"
        }
    }

    @ViewBuilder
    private var titleBlock: some View {
        if isRecording {
            RecordingTitle(title: L10n.t("detail.badge.recording", language), subtitle: AppFormatters.duration(elapsed))
        } else if let recording {
            recordingTitle(for: recording)
        } else {
            RecordingTitle(title: "Whisperdown", subtitle: "00:00")
        }
    }

    /// 제목 영역이 md 파일의 드래그 소스 — 파일이 실제로 존재할 때만 활성화된다
    /// (DesignPreview의 가짜 경로는 자연 비활성).
    @ViewBuilder
    private func recordingTitle(for recording: Recording) -> some View {
        let title = RecordingTitle(
            title: recording.title,
            subtitle: "\(AppFormatters.displayDate.string(from: recording.createdAt))  \(AppFormatters.duration(recording.duration))"
        )

        if recording.status == .ready, FileManager.default.fileExists(atPath: recording.markdownURL.path) {
            title
                .onDrag { NSItemProvider(contentsOf: recording.markdownURL) ?? NSItemProvider() }
                .help(L10n.t("detail.help.dragMarkdown", language))
        } else {
            title
        }
    }

    @ViewBuilder
    private var transcriptBlock: some View {
        if isRecording {
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack(spacing: Spacing.sm) {
                    Circle()
                        .fill(Palette.destructive)
                        .frame(width: 8, height: 8)
                        .recPulse()

                    Text(liveTranscriptText.isEmpty ? L10n.t("detail.live.waitingLabel", language) : L10n.t("detail.live.label", language))
                        .font(Typography.body)
                        .foregroundStyle(Palette.destructive)
                }

                if liveTranscriptText.isEmpty {
                    Text(L10n.t("detail.live.placeholder", language))
                        .font(Typography.body)
                        .foregroundStyle(Palette.secondaryLabel)
                        .lineSpacing(4)
                } else {
                    Text(liveTranscriptText)
                        .font(AppTypography.transcript)
                        .lineSpacing(5.5)
                        .foregroundStyle(Palette.body)
                        .textSelection(.enabled)
                }
            }
            .padding(.top, Spacing.xs)
            .frame(maxWidth: .infinity, minHeight: 180, alignment: .topLeading)
        } else if let recording {
            switch recording.status {
            case .processing:
                if isProcessing {
                    processingView
                } else {
                    VStack(spacing: Spacing.md) {
                        CenterStatusView(
                            systemName: "exclamationmark.triangle.fill",
                            title: L10n.t("detail.status.interrupted.title", language),
                            message: L10n.t("detail.status.interrupted.message", language),
                            tint: Palette.warning
                        )

                        retryButton(for: recording)
                    }
                    .frame(maxWidth: .infinity, minHeight: 280)
                }

            case .failed:
                VStack(spacing: Spacing.md) {
                    CenterStatusView(
                        systemName: "exclamationmark.triangle.fill",
                        title: L10n.t("detail.status.reviewNeeded.title", language),
                        message: recording.engineNote,
                        tint: Palette.warning
                    )

                    retryButton(for: recording)
                }
                .frame(maxWidth: .infinity, minHeight: 280)

            case .ready:
                VStack(alignment: .leading, spacing: Spacing.md) {
                    summaryStatusRow

                    if showsRawMarkdown {
                        MarkdownPreview(content: markdownContent(for: recording))
                            .textSelection(.enabled)
                    } else {
                        VStack(alignment: .leading, spacing: Spacing.lg) {
                            ForEach(recording.segments) { segment in
                                TranscriptSegmentView(segment: segment)
                            }
                        }
                    }
                }
                .frame(maxWidth: AppMetric.transcriptMaxWidth, alignment: .leading)
                .padding(.top, Spacing.xs)
                .animation(MotionToken.quick, value: summaryPhase)
            }
        } else if isProcessing {
            processingView
        } else {
            CenterStatusView(
                systemName: "waveform.circle",
                title: L10n.t("detail.status.noRecording.title", language),
                message: L10n.t("detail.status.noRecording.message", language),
                tint: Palette.secondaryLabel
            )
        }
    }

    private var liveTranscriptText: String {
        liveTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 전사 결과가 나타날 자리(좌상단)에 스테퍼를 배치해 진행 → 결과의 공간적 연속성을 유지한다.
    private var processingView: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            TranscriptionStageListView(
                currentStage: processingStage,
                transcriptionProgress: transcriptionProgress,
                transcriptionStartedAt: transcriptionStartedAt,
                transcriptionActivity: transcriptionActivity,
                diarizationState: diarizationState,
                showsActivitySteps: isWhisperReady,
                showsDiarizationStep: showsDiarizationStep
            )

            if let partialTranscript,
               !partialTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                PartialTranscriptPreview(text: partialTranscript)
            }
        }
        .padding(.top, Spacing.xs)
        .frame(maxWidth: .infinity, minHeight: 240, alignment: .topLeading)
    }

    /// 백그라운드 요약 진행/실패의 조용한 인라인 표시. 완료 시엔 행이 그냥 사라진다 —
    /// 요약 자체는 md 파일/미리보기가 보여주는 것이 제품 표면.
    @ViewBuilder
    private var summaryStatusRow: some View {
        if summaryPhase == .running {
            HStack(spacing: Spacing.sm) {
                ProgressView()
                    .controlSize(.small)
                Text(L10n.t("summary.generating", language))
                    .font(Typography.caption)
                    .foregroundStyle(Palette.secondaryLabel)
            }
        } else if case .failed = summaryPhase {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "exclamationmark.circle")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.warning)
                Text(L10n.t("summary.failed", language))
                    .font(Typography.caption)
                    .foregroundStyle(Palette.secondaryLabel)
            }
        }
    }

    /// 원본 보기/복사의 소스는 디스크의 실제 파일 — 사용자의 수동 편집이 그대로 반영된다.
    /// 파일이 없을 때만(프리뷰 가짜 경로, 외부 삭제) 렌더링으로 폴백.
    private func markdownContent(for recording: Recording) -> String {
        (try? String(contentsOf: recording.markdownURL, encoding: .utf8))
            ?? MarkdownWriter().render(recording: recording)
    }

    private func copyMarkdown(for recording: Recording) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(markdownContent(for: recording), forType: .string)

        withAnimation(MotionToken.quick) {
            didCopyMarkdown = true
        }
        Task {
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            withAnimation(MotionToken.quick) {
                didCopyMarkdown = false
            }
        }
    }

    private func revealInFinder(for recording: Recording) {
        if FileManager.default.fileExists(atPath: recording.markdownURL.path) {
            NSWorkspace.shared.activateFileViewerSelecting([recording.markdownURL])
        } else {
            NSWorkspace.shared.open(recording.markdownURL.deletingLastPathComponent())
        }
    }

    private func retryButton(for recording: Recording) -> some View {
        Button {
            onRetryTranscription(recording)
        } label: {
            Label(L10n.t("detail.retryTranscription", language), systemImage: "arrow.clockwise")
                .font(Typography.emphasis)
                .foregroundStyle(Palette.label.opacity(0.84))
                .padding(.horizontal, Spacing.md)
                .frame(height: 32)
                .glassCapsule()
        }
        .buttonStyle(.plain)
        .disabled(isProcessing)
        .opacity(isProcessing ? 0.45 : 1)
    }

    @ViewBuilder
    private var transport: some View {
        if isRecording {
            TransportDeck(
                level: level,
                levelHistory: levelHistory,
                elapsed: elapsed,
                duration: 0,
                isRecording: isRecording,
                isProcessing: isProcessing,
                canUsePlayback: false,
                isTransportAvailable: true,
                isPlaybackPlaying: false,
                onPlayPauseTapped: onRecordTapped,
                onSeekBackward: onSeekBackward,
                onSeekForward: onSeekForward
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, AppLayout.detailHorizontalPadding)
            .padding(.vertical, Spacing.sm)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Color.hairline)
                    .frame(height: 1)
                    .allowsHitTesting(false)
            }
        } else {
            let hasRecording = recording != nil
            let canUsePlayback = hasRecording && !isProcessing
            let isTransportAvailable = canUsePlayback

            TransportDeck(
                level: level,
                levelHistory: [],
                elapsed: playbackElapsed,
                duration: recording?.duration ?? 0,
                isRecording: isRecording,
                isProcessing: isProcessing,
                canUsePlayback: canUsePlayback,
                isTransportAvailable: isTransportAvailable,
                isPlaybackPlaying: isPlaybackPlaying,
                onPlayPauseTapped: onPlayPauseTapped,
                onSeekBackward: onSeekBackward,
                onSeekForward: onSeekForward
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, AppLayout.detailHorizontalPadding)
            .padding(.vertical, Spacing.sm)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Color.hairline)
                    .frame(height: 1)
                    .allowsHitTesting(false)
            }
        }
    }
}

private struct ModeBadge: View {
    let title: String
    let systemName: String

    private var badgeIconColor: Color {
        switch systemName {
        case "checkmark.circle":
            return Palette.success
        case "exclamationmark.circle":
            return Palette.warning
        default:
            return Palette.secondaryLabel
        }
    }

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: systemName)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(badgeIconColor)
                .frame(width: 14, height: 14)

            Text(title)
                .font(Typography.caption)
                .foregroundStyle(Palette.label.opacity(0.82))
                .lineLimit(1)

            Image(systemName: "chevron.down")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(Palette.tertiaryLabel)
        }
        .padding(.leading, Spacing.sm)
        .padding(.trailing, 11)
        .frame(height: AppMetric.searchHeight)
        .background(Color.appSurface, in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                .strokeBorder(Color.hairline, lineWidth: 1)
        }
    }
}

private struct RecordingTitle: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(title)
                .font(Typography.title)
                .foregroundStyle(Palette.label.opacity(0.94))
                .multilineTextAlignment(.leading)
                .lineLimit(2)

            Text(subtitle)
                .font(AppTypography.meta)
                .foregroundStyle(Palette.secondaryLabel)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct TransportDeck: View {
    let level: Double
    let levelHistory: [Double]
    let elapsed: TimeInterval
    let duration: TimeInterval
    let isRecording: Bool
    let isProcessing: Bool
    let canUsePlayback: Bool
    let isTransportAvailable: Bool
    let isPlaybackPlaying: Bool
    let onPlayPauseTapped: () -> Void
    let onSeekBackward: () -> Void
    let onSeekForward: () -> Void

    var body: some View {
        HStack(spacing: Spacing.lg) {
            Text(AppFormatters.duration(elapsed))
                .font(AppTypography.timer)
                .monospacedDigit()
                .foregroundStyle(timeColor)
                .frame(width: AppMetric.transportTimeWidth, alignment: .leading)

            WaveformView(
                level: level,
                isRecording: isRecording,
                isPlaying: isPlaybackPlaying,
                progress: duration > 0 ? min(1, elapsed / duration) : 0,
                history: levelHistory,
                showsTrack: false
            )
            .frame(height: AppMetric.waveformHeight)
            .frame(maxWidth: .infinity)
            .opacity(isTransportAvailable ? 1 : 0.36)

            TransportIsland(
                isRecording: isRecording,
                isProcessing: isProcessing,
                canUsePlayback: canUsePlayback,
                isPlaybackPlaying: isPlaybackPlaying,
                onPlayPauseTapped: onPlayPauseTapped,
                onSeekBackward: onSeekBackward,
                onSeekForward: onSeekForward
            )
            .opacity(isTransportAvailable ? 1 : 0.54)
        }
        .frame(maxWidth: .infinity)
        .frame(height: AppMetric.transportCardHeight)
    }

    private var timeColor: Color {
        if isRecording {
            return Palette.destructive
        }

        return Palette.label.opacity(isTransportAvailable ? 0.92 : 0.36)
    }
}

private struct TransportIsland: View {
    @Environment(\.appLanguage) private var language

    let isRecording: Bool
    let isProcessing: Bool
    let canUsePlayback: Bool
    let isPlaybackPlaying: Bool
    let onPlayPauseTapped: () -> Void
    let onSeekBackward: () -> Void
    let onSeekForward: () -> Void

    private var isPrimaryDisabled: Bool {
        isProcessing || (!canUsePlayback && !isRecording)
    }

    var body: some View {
        HStack(spacing: 8) {
            TransportIconButton(systemName: "gobackward.10", isDisabled: !canUsePlayback, action: onSeekBackward)
                .help(L10n.t("detail.transport.help.seekBackward", language))

            Button(action: onPlayPauseTapped) {
                ZStack {
                    Circle()
                        .fill(isRecording ? Palette.destructive : Palette.primary)
                        .frame(width: 40, height: 40)

                    Image(systemName: primaryIconName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Palette.primaryForeground)
                        .offset(x: (!isRecording && !isPlaybackPlaying) ? 1.5 : 0)
                }
                .frame(width: 40, height: 40)
            }
            .buttonStyle(QuietButtonStyle())
            .disabled(isPrimaryDisabled)
            .help(primaryHelpText)
            // Space = 재생/일시정지 (텍스트필드 포커스 시엔 시스템이 필드 입력 우선)
            .keyboardShortcut(.space, modifiers: [])

            TransportIconButton(systemName: "goforward.10", isDisabled: !canUsePlayback, action: onSeekForward)
                .help(L10n.t("detail.transport.help.seekForward", language))
        }
    }

    private var primaryIconName: String {
        if isRecording {
            return "stop.fill"
        }

        return isPlaybackPlaying ? "pause.fill" : "play.fill"
    }

    private var primaryHelpText: String {
        if isRecording {
            return L10n.t("detail.transport.help.stopRecording", language)
        }

        return canUsePlayback ? (isPlaybackPlaying ? L10n.t("detail.transport.help.pause", language) : L10n.t("detail.transport.help.play", language)) : L10n.t("sidebar.empty.noRecordings", language)
    }
}

private struct TransportIconButton: View {
    let systemName: String
    var isDisabled = false
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Palette.secondaryLabel)
                .frame(width: 36, height: 36)
                .background(
                    isHovering && !isDisabled ? Color.controlSurface.opacity(0.56) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
                .animation(MotionToken.quick, value: isHovering)
        }
        .buttonStyle(QuietButtonStyle())
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.45 : 1)
        .contentShape(Circle())
        .onHover { isHovering = $0 }
    }
}

private struct TranscriptionStageListView: View {
    @Environment(\.appLanguage) private var language
    let currentStage: TranscriptionStage?
    let transcriptionProgress: Double?
    let transcriptionStartedAt: Date?
    let transcriptionActivity: TranscriptionActivity?
    let diarizationState: DiarizationStepState?
    let showsActivitySteps: Bool
    let showsDiarizationStep: Bool

    private enum RowStatus {
        case done, active, pending
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(steps, id: \.self) { step in
                stepRow(for: step)
            }
        }
        .frame(maxWidth: 280, alignment: .leading)
    }

    /// 파이프라인은 순차 실행이므로 계층 없이 1-depth 평면 리스트로 보여준다.
    /// whisper 경로는 준비 단계 2개를 포함한 5행, Apple Speech는 신호가 없어 3행.
    private enum FlatStep: Hashable {
        case stage(TranscriptionStage)
        case activity(TranscriptionActivity)
        case diarizing
    }

    private var steps: [FlatStep] {
        if showsActivitySteps {
            var flat: [FlatStep] = [
                .stage(.converting),
                .activity(.loadingModel),
                .activity(.analyzing),
                .stage(.transcribing),
                .stage(.finalizing)
            ]
            if showsDiarizationStep {
                // whisper와 병렬 실행되는 스텝 — 인식 직전 슬롯에 배치
                flat.insert(.diarizing, at: 3)
            }
            return flat
        }
        return TranscriptionStage.allCases.map { FlatStep.stage($0) }
    }

    private var currentStepIndex: Int {
        guard let currentStage else { return -1 }

        let currentStep: FlatStep
        switch currentStage {
        case .converting:
            currentStep = .stage(.converting)
        case .transcribing:
            if !showsActivitySteps || transcriptionProgress != nil {
                currentStep = .stage(.transcribing)
            } else {
                currentStep = .activity(transcriptionActivity ?? .loadingModel)
            }
        case .finalizing:
            currentStep = .stage(.finalizing)
        }

        return steps.firstIndex(of: currentStep) ?? -1
    }

    private func status(for step: FlatStep) -> RowStatus {
        // 화자 분석은 whisper와 병렬 실행되므로 선형 인덱스를 무시하는 유일한 오버라이드.
        // 엔진이 .finalizing 발화 전에 터미널 상태를 해소하므로
        // active finalizing 위에 active/pending 행이 남는 상황은 구조적으로 불가능하다.
        if step == .diarizing {
            switch diarizationState {
            case nil: return .pending
            case .running: return .active
            case .done, .skipped: return .done
            }
        }

        guard let index = steps.firstIndex(of: step) else { return .pending }
        let current = currentStepIndex
        if index < current { return .done }
        if index == current { return .active }
        return .pending
    }

    private func key(for step: FlatStep) -> String {
        switch step {
        case .stage(.converting): return "stage.converting"
        case .stage(.transcribing): return "stage.transcribing"
        case .stage(.finalizing): return "stage.finalizing"
        case .activity(.loadingModel): return "stage.transcribing.loadingModel"
        case .activity(.analyzing): return "stage.transcribing.analyzing"
        case .diarizing: return "stage.diarizing"
        }
    }

    private func activeLabel(for step: FlatStep) -> String {
        switch step {
        case .stage: return L10n.t("\(key(for: step)).active", language)
        case .activity: return L10n.t(key(for: step), language)
        case .diarizing: return L10n.t("stage.diarizing.active", language)
        }
    }

    private func doneLabel(for step: FlatStep) -> String {
        if step == .diarizing {
            switch diarizationState {
            case .done(let speakerCount):
                return String(format: L10n.t("stage.diarizing.done", language), speakerCount)
            case .skipped:
                return L10n.t("stage.diarizing.skipped", language)
            case .running, nil:
                return L10n.t("stage.diarizing.active", language)
            }
        }
        return L10n.t("\(key(for: step)).done", language)
    }

    private func isLastStep(_ step: FlatStep) -> Bool {
        steps.last == step
    }

    /// 스텝 아이콘. 총 단계 수는 pending 숫자 원이 구조로 보여준다 —
    /// 카운터 텍스트를 반복하는 대신 배송 추적/설치 마법사 계열의 스테퍼 관용구를 따른다.
    @ViewBuilder
    private func stepIcon(for step: FlatStep, status rowStatus: RowStatus) -> some View {
        switch rowStatus {
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Palette.success)
        case .active:
            // 진행률을 알면 indeterminate 스피너 대신 determinate 링으로 채운다.
            if step == .stage(.transcribing), let transcriptionProgress {
                DeterminateProgressRing(fraction: transcriptionProgress)
            } else {
                CircularProcessingIndicator()
            }
        case .pending:
            ZStack {
                Circle()
                    .stroke(Palette.tertiaryLabel.opacity(0.55), lineWidth: 1)
                Text("\((steps.firstIndex(of: step) ?? 0) + 1)")
                    .font(.system(size: 9, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(Palette.tertiaryLabel)
            }
        }
    }

    @ViewBuilder
    private func stepRow(for step: FlatStep) -> some View {
        let rowStatus = status(for: step)
        let isLast = isLastStep(step)

        HStack(alignment: .top, spacing: Spacing.sm) {
            VStack(spacing: 3) {
                stepIcon(for: step, status: rowStatus)
                    .frame(width: 16, height: 16)

                if !isLast {
                    // 지나온 구간의 레일은 은은하게 물들여 "하나의 프로세스"로 읽히게 한다.
                    Rectangle()
                        .fill(rowStatus == .done ? Palette.success.opacity(0.30) : Color.hairline)
                        .frame(width: 1)
                        .frame(maxHeight: .infinity)
                        .padding(.bottom, 3)
                }
            }
            .frame(width: 16)

            Group {
                switch rowStatus {
                case .done:
                    Text(doneLabel(for: step))
                        .font(Typography.body)
                        .foregroundStyle(Palette.secondaryLabel)
                case .active:
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 0) {
                            Text(activeLabel(for: step))
                            AnimatedDots()
                        }
                        .font(Typography.emphasis)
                        .foregroundStyle(Palette.label.opacity(0.9))

                        if step == .stage(.transcribing), let transcriptionProgress {
                            TranscriptionProgressCaption(
                                progress: transcriptionProgress,
                                startedAt: transcriptionStartedAt
                            )
                        }
                    }
                case .pending:
                    Text(activeLabel(for: step))
                        .font(Typography.body)
                        .foregroundStyle(Palette.tertiaryLabel)
                }
            }
            .padding(.bottom, isLast ? 0 : Spacing.md)
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct PartialTranscriptPreview: View {
    @Environment(\.appLanguage) private var language
    let text: String

    /// 마지막 문장 몇 개 분량만 보여준다 (최신 내용 항상 표시 + 높이 제한).
    private static let tailCap = 220

    private var displayText: String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > Self.tailCap else { return trimmed }
        return "…" + trimmed.suffix(Self.tailCap)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "text.quote")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Palette.tertiaryLabel)
                Text(L10n.t("detail.partialTranscript.title", language))
                    .font(Typography.caption)
                    .foregroundStyle(Palette.tertiaryLabel)
            }

            Text(displayText)
                .font(Typography.body)
                .foregroundStyle(Palette.secondaryLabel)
                .lineSpacing(4)
                .lineLimit(4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(MotionToken.quick, value: displayText)
        }
        .padding(Spacing.md)
        .background(Color.appMuted, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.hairline, lineWidth: 1)
        }
        .frame(maxWidth: 280, alignment: .leading)
    }
}

/// 진행률을 아는 활성 스텝용 determinate 링. 채워지는 색이 완료 체크마크(success)를 예고한다.
private struct DeterminateProgressRing: View {
    let fraction: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(Palette.tertiaryLabel.opacity(0.35), lineWidth: 1.4)
            Circle()
                .trim(from: 0, to: max(0, min(1, fraction)))
                .stroke(Palette.success, style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(MotionToken.quick, value: fraction)
        }
    }
}

private struct AnimatedDots: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.45)) { timeline in
            let phase = Int(timeline.date.timeIntervalSinceReferenceDate / 0.45) % 3

            Text(String(repeating: ".", count: phase + 1))
                .frame(width: 18, alignment: .leading)
        }
    }
}

private struct TranscriptionProgressCaption: View {
    @Environment(\.appLanguage) private var language
    let progress: Double        // 0...1
    let startedAt: Date?

    /// 이 진행률 미만에서는 ETA가 널뛰므로 %만 표시한다.
    private static let etaThreshold = 0.05

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            Text(caption(now: timeline.date))
                .font(Typography.caption)
                .monospacedDigit()
                .foregroundStyle(Palette.tertiaryLabel)
        }
    }

    private func caption(now: Date) -> String {
        let percentText = String(
            format: L10n.t("stage.transcribing.percent", language),
            Int((progress * 100).rounded())
        )

        guard progress >= Self.etaThreshold,
              progress < 1,
              let startedAt else {
            return percentText
        }

        let elapsed = now.timeIntervalSince(startedAt)
        guard elapsed > 1 else {
            return percentText
        }

        let remaining = elapsed * (1 - progress) / progress
        return percentText + " · " + String(
            format: L10n.t("stage.transcribing.eta", language),
            AppFormatters.duration(remaining)
        )
    }
}

private struct TranscriptSegmentView: View {
    let segment: SpeakerSegment

    private var speakerTint: Color {
        let normalized = segment.speaker.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        let palette: [Color] = [.teal, .indigo, Palette.warning, .pink, .mint]
        let scalarTotal = normalized.unicodeScalars.reduce(0) { partial, scalar in
            partial + Int(scalar.value)
        }

        return palette[abs(scalarTotal) % palette.count]
    }

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            VStack(spacing: Spacing.sm) {
                Circle()
                    .fill(speakerTint.opacity(0.64))
                    .frame(width: 6, height: 6)
                    .shadow(color: speakerTint.opacity(0.10), radius: 4, x: 0, y: 1)

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                speakerTint.opacity(0.12),
                                speakerTint.opacity(0.026),
                                .clear
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 2, height: 44)
            }
            .frame(width: Spacing.lg)
            .padding(.top, Spacing.sm)

            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(spacing: Spacing.sm) {
                    Text(segment.speaker)
                        .font(Typography.emphasis)
                        .foregroundStyle(Palette.label)

                    Text("\(AppFormatters.timestamp(segment.startTime)) - \(AppFormatters.timestamp(segment.endTime))")
                        .font(AppTypography.meta)
                        .foregroundStyle(Palette.tertiaryLabel)
                }

                Text(segment.text)
                    .font(AppTypography.transcript)
                    .lineSpacing(5.5)
                    .foregroundStyle(Palette.body)
                    .textSelection(.enabled)
            }
            .padding(.bottom, Spacing.xs)
        }
        .padding(.vertical, Spacing.xs / 2)
    }
}

private struct CenterStatusView: View {
    let systemName: String
    let title: String
    let message: String
    let tint: Color

    var body: some View {
        VStack(spacing: Spacing.sm) {
            Image(systemName: systemName)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(tint.opacity(0.85))

            Text(title)
                .font(Typography.headline)
                .foregroundStyle(Palette.label.opacity(0.84))

            Text(message)
                .font(Typography.body)
                .foregroundStyle(Palette.secondaryLabel)
                .multilineTextAlignment(.center)
                .lineSpacing(Spacing.xs)
                .frame(maxWidth: 460)
        }
        .frame(maxWidth: .infinity, minHeight: 240)
    }
}

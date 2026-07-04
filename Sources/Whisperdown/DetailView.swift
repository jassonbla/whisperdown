import SwiftUI

struct DetailView: View {
    @Environment(\.appLanguage) private var language

    let recording: Recording?
    let isRecording: Bool
    let isProcessing: Bool
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
            RecordingTitle(
                title: recording.title,
                subtitle: "\(AppFormatters.displayDate.string(from: recording.createdAt))  \(AppFormatters.duration(recording.duration))"
            )
        } else {
            RecordingTitle(title: "Whisperdown", subtitle: "00:00")
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
                    TranscriptionStatusView()
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
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    ForEach(recording.segments) { segment in
                        TranscriptSegmentView(segment: segment)
                    }
                }
                .frame(maxWidth: AppMetric.transcriptMaxWidth, alignment: .leading)
                .padding(.top, Spacing.xs)
            }
        } else if isProcessing {
            TranscriptionStatusView()
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
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.lg)
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
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.lg)
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
        .padding(.horizontal, Spacing.lg)
        .frame(maxWidth: .infinity)
        .frame(height: AppMetric.transportCardHeight)
        .background(Color.appMuted, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.hairline, lineWidth: 1)
        }
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
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Palette.secondaryLabel)
                .frame(width: 32, height: 32)
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

private struct TranscriptionStatusView: View {
    @Environment(\.appLanguage) private var language

    var body: some View {
        VStack(spacing: Spacing.md) {
            VStack(spacing: Spacing.xs) {
                AnimatedEllipsisText(baseText: L10n.t("sidebar.bottomStatus.transcribing", language))

                Text(L10n.t("detail.transcribing.message", language))
                    .font(Typography.body)
                    .foregroundStyle(Palette.secondaryLabel)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 240)
    }
}

private struct AnimatedEllipsisText: View {
    let baseText: String

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.45)) { timeline in
            let phase = Int(timeline.date.timeIntervalSinceReferenceDate / 0.45) % 3

            HStack(spacing: 0) {
                Text(baseText)
                Text(String(repeating: ".", count: phase + 1))
                    .frame(width: 18, alignment: .leading)
            }
                .font(Typography.headline)
                .foregroundStyle(Palette.label.opacity(0.86))
                .frame(width: 86, alignment: .center)
        }
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

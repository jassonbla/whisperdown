import SwiftUI

struct SidebarView: View {
    @Environment(\.appLanguage) private var language

    let recordings: [Recording]
    @Binding var selectedRecordingID: Recording.ID?
    @Binding var searchText: String
    let isRecording: Bool
    let isProcessing: Bool
    let onRecordTapped: () -> Void
    var displayCount: Int? = nil
    /// 진행 중인 모델 다운로드 진행률 (0...1). nil이면 미표시.
    var modelDownloadFraction: Double? = nil
    /// 행 컨텍스트 메뉴 "삭제" — 확인 후 실제 삭제는 상위(RootView)가 수행.
    var onDeleteRequested: (Recording) -> Void = { _ in }

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var recordingCount: Int {
        displayCount ?? recordings.count
    }

    @FocusState private var isListFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            sidebarHeader

            if recordings.isEmpty {
                EmptyRecordingsView(isSearching: isSearching)
                    .frame(maxHeight: .infinity)
            } else {
                recordingList
            }

            bottomRecorder
        }
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color.hairline)
                .frame(width: 1)
                .allowsHitTesting(false)
        }
    }

    /// 목록 전체가 Tab 정지점 하나다. 포커스가 들어오면 ↑/↓가 선택을 옮긴다 —
    /// 행마다 Tab을 누르지 않는다(로빙 포커스).
    private var recordingList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    SidebarSectionHeader(title: L10n.t(isSearching ? "sidebar.searching" : "sidebar.recentItems", language))

                    ForEach(recordings) { recording in
                        RecordingRow(
                            recording: recording,
                            isSelected: selectedRecordingID == recording.id,
                            isActivelyProcessing: isProcessing && recording.status == .processing,
                            isListFocused: isListFocused
                        ) {
                            selectedRecordingID = recording.id
                            isListFocused = true
                        }
                        .contextMenu {
                            Button(L10n.t("action.delete", language), role: .destructive) {
                                onDeleteRequested(recording)
                            }
                        }
                    }
                }
                .padding(.bottom, Spacing.sm)
                .background(OverlayScrollerConfigurator())
            }
            .scrollIndicators(.hidden)
            .focusable(true, interactions: .edit)
            .focusEffectDisabled()
            .focused($isListFocused)
            .onMoveCommand { direction in
                moveSelection(direction, proxy: proxy)
            }
            .accessibilityLabel(L10n.t("sidebar.allRecordings", language))
        }
    }

    private func moveSelection(_ direction: MoveCommandDirection, proxy: ScrollViewProxy) {
        guard !recordings.isEmpty else { return }

        // 선택이 없거나 필터로 사라졌으면 상세 화면이 보여주는 첫 행을 기준으로 삼는다.
        let current = recordings.firstIndex { $0.id == selectedRecordingID } ?? 0
        let next: Int
        switch direction {
        case .up:
            next = max(0, current - 1)
        case .down:
            next = min(recordings.count - 1, current + 1)
        default:
            return
        }

        let id = recordings[next].id
        selectedRecordingID = id
        proxy.scrollTo(id)
    }

    private var sidebarHeader: some View {
        VStack(spacing: 0) {
            sidebarTitleBar

            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                    Text(L10n.t("sidebar.allRecordings", language))
                        .font(Typography.headline)
                        .foregroundStyle(Palette.label)

                    Spacer(minLength: Spacing.sm)

                    Text(String(format: L10n.t("sidebar.countSuffix", language), recordingCount))
                        .font(AppTypography.meta)
                        .foregroundStyle(Palette.tertiaryLabel)
                }

                SidebarSearchField(text: $searchText) {
                    isListFocused = true
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.top, AppLayout.sidebarContentTopInset)
            .padding(.bottom, Spacing.sm)
        }
    }

    private var sidebarTitleBar: some View {
        HStack(spacing: 0) {}
        .padding(.horizontal, Spacing.md)
        .frame(maxWidth: .infinity)
        .frame(height: AppLayout.titleBarHeight)
        .background(Palette.background)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.hairline)
                .frame(height: 1)
                .allowsHitTesting(false)
        }
    }

    private var bottomRecorder: some View {
        VStack(spacing: 0) {
            if let fraction = modelDownloadFraction {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Palette.secondaryLabel)

                    Text(String(format: L10n.t("sidebar.modelDownloadProgress", language), Int(fraction * 100)))
                        .font(Typography.caption)
                        .monospacedDigit()
                        .foregroundStyle(Palette.secondaryLabel)

                    Spacer(minLength: Spacing.sm)

                    LinearProgressBar(value: fraction)
                        .frame(width: 56)
                }
                .padding(.horizontal, Spacing.md)
                .frame(height: 26)
                .background(Palette.bg2)
            }

            HStack(spacing: Spacing.sm) {
                RecordButton(
                    isRecording: isRecording,
                    isProcessing: isProcessing,
                    size: AppMetric.primaryActionSize,
                    action: onRecordTapped
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(isRecording ? L10n.t("sidebar.bottomStatus.recording", language) : L10n.t("sidebar.newRecording", language))
                        .font(Typography.emphasis)
                        .foregroundStyle(Palette.label)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    Text(bottomStatusText)
                        .font(AppTypography.meta)
                        .foregroundStyle(Palette.secondaryLabel)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
                .layoutPriority(1)

                Spacer()

                if isProcessing {
                    CircularProcessingIndicator()
                        .frame(width: 14, height: 14)
                }
            }
            .padding(.horizontal, Spacing.md)
            .frame(height: AppMetric.bottomBarHeight)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Color.hairline)
                    .frame(height: 1)
                    .allowsHitTesting(false)
            }
        }
    }

    private var bottomStatusText: String {
        if isRecording {
            return L10n.t("sidebar.bottomStatus.recording", language)
        }

        if isProcessing {
            return L10n.t("sidebar.bottomStatus.transcribing", language)
        }

        return L10n.t("sidebar.bottomStatus.ready", language)
    }
}

struct SidebarSurface: View {
    var body: some View {
        Rectangle()
            .fill(Palette.background)
    }
}

private struct SidebarSectionHeader: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(Typography.overline)
            .tracking(0.6)
            .foregroundStyle(Palette.tertiaryLabel)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.md)
            .padding(.top, Spacing.md)
            .padding(.bottom, Spacing.sm)
            .accessibilityAddTraits(.isHeader)
    }
}

private struct SidebarSearchField: View {
    @Environment(\.appLanguage) private var language
    @Binding var text: String
    /// ↓ — 검색 필드에서 결과 목록으로 내려간다.
    let onMoveDown: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(Typography.caption)
                .foregroundStyle(Palette.tertiaryLabel)
                .accessibilityHidden(true)

            TextField(L10n.t("sidebar.search.placeholder", language), text: $text)
                .textFieldStyle(.plain)
                .font(Typography.body)
                .foregroundStyle(Palette.label)
                .focused($isFocused)
                .onKeyPress(.downArrow) {
                    onMoveDown()
                    return .handled
                }
                .onReceive(NotificationCenter.default.publisher(for: .focusSearchRequested)) { _ in
                    isFocused = true
                }

            if !text.isEmpty {
                IconButton(
                    systemName: "xmark",
                    label: L10n.t("sidebar.search.clear", language),
                    size: 20,
                    iconSize: 9
                ) {
                    text = ""
                }
            }
        }
        .padding(.leading, Spacing.sm)
        .padding(.trailing, text.isEmpty ? Spacing.sm : Spacing.xs)
        .frame(height: AppMetric.controlHeight)
        .background(Color.searchBackground, in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                .strokeBorder(isFocused ? Palette.label : Color.controlBorder, lineWidth: 1)
        }
    }
}

/// 목록 행. 버튼이 아니라 목록(`recordingList`)의 선택 항목이다 — 키보드 포커스는 목록이 갖는다.
private struct RecordingRow: View {
    @Environment(\.appLanguage) private var language

    let recording: Recording
    let isSelected: Bool
    let isActivelyProcessing: Bool
    let isListFocused: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: Spacing.sm) {
            statusIcon

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Spacing.sm) {
                    Text(recording.title)
                        .font(isSelected ? Typography.emphasis : Typography.body)
                        .foregroundStyle(titleColor)
                        .lineLimit(1)

                    Spacer(minLength: 6)

                    HStack(spacing: 6) {
                        if isActivelyProcessing {
                            CircularProcessingIndicator()
                                .frame(width: 12, height: 12)
                        }

                        durationLabel
                    }
                }

                HStack(spacing: Spacing.xs) {
                    subtitle

                    Spacer(minLength: 6)
                }
                .font(Typography.caption)
            }
        }
        .padding(.vertical, Spacing.xs)
        .padding(.horizontal, Spacing.md)
        .frame(minHeight: AppMetric.rowMinHeight)
        .background(rowBackground)
        // 선택 표시는 배경색만으로 전달하지 않는다 — 선두 막대가 비색상 단서.
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(isSelected ? (isListFocused ? Palette.label : Palette.input) : Color.clear)
                .frame(width: 2)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
        .onHover { isHovering = $0 }
        .animation(MotionToken.quick, value: isHovering)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction(.default, action)
    }

    private var durationLabel: some View {
        Text(AppFormatters.duration(recording.duration))
            .font(AppTypography.duration)
            .monospacedDigit()
            .foregroundStyle(Palette.tertiaryLabel)
            .frame(height: 18)
    }

    @ViewBuilder
    private var subtitle: some View {
        switch recording.status {
        case .processing:
            if isActivelyProcessing {
                Text(L10n.t("sidebar.bottomStatus.transcribing", language))
                    .foregroundStyle(Palette.secondaryLabel)
            } else {
                Text(L10n.t("detail.badge.retryNeeded", language))
                    .foregroundStyle(Palette.warning)
            }
        case .failed:
            Text(L10n.t("sidebar.row.reviewNeeded", language))
                .foregroundStyle(Palette.warning)
        case .ready:
            Text(AppFormatters.listTime.string(from: recording.createdAt))
                .font(AppTypography.listMeta)
                .foregroundStyle(Palette.secondaryLabel)
        }
    }

    private var statusIcon: some View {
        Image(systemName: needsAttention ? "exclamationmark.triangle" : "waveform")
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(iconForeground)
            // 글리프를 헤더·검색 필드와 같은 선두 선(12pt)에 붙인다.
            .frame(width: 16, height: 16, alignment: .leading)
            .accessibilityHidden(true)
    }

    private var rowBackground: Color {
        if isSelected || isHovering {
            return Palette.bg2
        }

        return Color.clear
    }

    private var needsAttention: Bool {
        recording.status == .failed || (recording.status == .processing && !isActivelyProcessing)
    }

    private var iconForeground: Color {
        if needsAttention {
            return Palette.warning
        }

        return isSelected ? Palette.label : Palette.tertiaryLabel
    }

    private var titleColor: Color {
        needsAttention ? Palette.destructive : Palette.label
    }
}

private struct EmptyRecordingsView: View {
    @Environment(\.appLanguage) private var language

    let isSearching: Bool

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "waveform")
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(Palette.tertiaryLabel)
                .accessibilityHidden(true)

            Text(isSearching ? L10n.t("sidebar.empty.noResults", language) : L10n.t("sidebar.empty.noRecordings", language))
                .font(Typography.emphasis)
                .foregroundStyle(Palette.secondaryLabel)

            if !isSearching {
                HStack(spacing: 4) {
                    Text("⌘N")
                        .font(AppTypography.duration)
                        .foregroundStyle(Palette.secondaryLabel)
                        .padding(.horizontal, 5)
                        .frame(height: 18)
                        .overlay {
                            RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                                .strokeBorder(Color.controlBorder, lineWidth: 1)
                        }

                    Text(L10n.t("sidebar.empty.startHint", language))
                        .font(Typography.caption)
                        .foregroundStyle(Palette.tertiaryLabel)
                }
            }
        }
    }
}

struct CircularProcessingIndicator: View {
    @State private var rotation: Double = 0

    var body: some View {
        Circle()
            .trim(from: 0.16, to: 0.82)
            .stroke(
                Palette.secondaryLabel,
                style: StrokeStyle(lineWidth: 1.4, lineCap: .round)
            )
            .rotationEffect(.degrees(rotation))
            .onAppear {
                rotation = 0
                withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) {
                    rotation = 360
                }
            }
    }
}

import SwiftUI

struct SidebarView: View {
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

    var body: some View {
        VStack(spacing: 0) {
            sidebarHeader

            if recordings.isEmpty {
                EmptyRecordingsView(isSearching: isSearching)
                    .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: Spacing.xs / 2) {
                        SidebarSectionHeader(title: "최근 항목")

                        ForEach(recordings) { recording in
                            RecordingRow(
                                recording: recording,
                                isSelected: selectedRecordingID == recording.id,
                                isActivelyProcessing: isProcessing && recording.status == .processing
                            ) {
                                selectedRecordingID = recording.id
                            }
                            .contextMenu {
                                Button("삭제", role: .destructive) {
                                    onDeleteRequested(recording)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, Spacing.sm)
                    .padding(.top, 0)
                    .padding(.bottom, Spacing.sm)
                    .background(OverlayScrollerConfigurator())
                }
                .scrollIndicators(.hidden)
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

    private var sidebarHeader: some View {
        VStack(spacing: 0) {
            sidebarTitleBar

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("모든 녹음 항목")
                            .font(Typography.headline)
                            .foregroundStyle(Palette.label.opacity(0.92))
                        HStack(spacing: 0) {
                            Text("Voice to Markdown · ")
                                .font(AppTypography.meta)
                            Text("\(recordingCount)개")
                                .font(AppTypography.meta)
                        }
                        .foregroundStyle(Palette.secondaryLabel)
                    }

                    Spacer()
                }
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.top, AppLayout.sidebarContentTopInset)
            .padding(.bottom, 10)

            VStack(spacing: Spacing.sm) {
                SidebarLibraryRow(count: recordingCount, isSearching: isSearching)
                SidebarSearchField(text: $searchText)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.top, 2)
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

                    Text("모델 다운로드 중 \(Int(fraction * 100))%")
                        .font(Typography.caption)
                        .monospacedDigit()
                        .foregroundStyle(Palette.secondaryLabel)

                    Spacer(minLength: Spacing.sm)

                    ProgressView(value: fraction)
                        .progressViewStyle(.linear)
                        .frame(width: 56)
                }
                .padding(.horizontal, Spacing.md)
                .frame(height: 26)
                .background(Palette.bg2.opacity(0.6))
            }

            HStack(spacing: Spacing.sm) {
                RecordButton(
                    isRecording: isRecording,
                    isProcessing: isProcessing,
                    size: 28,
                    action: onRecordTapped
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(isRecording ? "녹음 중" : "새 녹음")
                        .font(Typography.emphasis)
                        .foregroundStyle(Palette.label)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    Text(bottomStatusText)
                        .font(Typography.caption)
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
            .padding(.top, Spacing.sm)
            .padding(.bottom, Spacing.sm)
            .background(alignment: .top) {
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Palette.primary.opacity(0.018),
                                Palette.primary.opacity(0.006),
                                .clear
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(height: Spacing.lg)
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Palette.separator.opacity(0.48))
                    .frame(height: 1)
                    .allowsHitTesting(false)
            }
        }
    }

    private var bottomStatusText: String {
        if isRecording {
            return "기록 중"
        }

        if isProcessing {
            return "전사 처리 중"
        }

        return "준비됨"
    }
}

struct SidebarSurface: View {
    var body: some View {
        Rectangle()
            .fill(Palette.background)
    }
}

private struct SidebarLibraryRow: View {
    let count: Int
    let isSearching: Bool

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: isSearching ? "magnifyingglass" : "mic")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Palette.primary.opacity(0.78))
                .frame(width: 20, height: 20)

            Text(isSearching ? "검색 결과" : "라이브러리")
                .font(Typography.emphasis)
                .foregroundStyle(Palette.label.opacity(0.86))

            Spacer(minLength: 6)

            Text("\(count)")
                .font(AppTypography.meta)
                .monospacedDigit()
                .foregroundStyle(Palette.secondaryLabel)
        }
        .padding(.horizontal, Spacing.sm)
        .frame(height: 36)
        .background(Color.appSurface, in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                .strokeBorder(Color.hairline, lineWidth: 1)
        }
    }
}

private struct SidebarSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(Typography.caption)
            .foregroundStyle(Palette.tertiaryLabel)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.lg)
            .padding(.top, 14)
            .padding(.bottom, Spacing.sm)
    }
}

private struct SidebarSearchField: View {
    @Binding var text: String

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(Typography.caption)
                .foregroundStyle(Palette.tertiaryLabel)

            TextField("검색", text: $text)
                .textFieldStyle(.plain)
                .font(Typography.body)
                .foregroundStyle(Palette.label)
                .focused($isFocused)
                .onReceive(NotificationCenter.default.publisher(for: .focusSearchRequested)) { _ in
                    isFocused = true
                }

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.tertiaryLabel)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Spacing.sm)
        .frame(height: 32)
        .background(Color.searchBackground, in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                .strokeBorder(Color.hairline, lineWidth: 1)
        }
    }
}

private struct RecordingRow: View {
    let recording: Recording
    let isSelected: Bool
    let isActivelyProcessing: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
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
                .frame(minHeight: AppMetric.rowMinHeight)
            }
            .background {
                RoundedRectangle(cornerRadius: AppRadius.row, style: .continuous)
                    .fill(rowBackground)
            }
            .shadow(color: rowShadowColor, radius: isSelected ? 3 : 0, x: 0, y: isSelected ? 1 : 0)
            .overlay {
                RoundedRectangle(cornerRadius: AppRadius.row, style: .continuous)
                    .strokeBorder(isSelected ? Color.rowSelectionStroke : Color.clear, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: AppRadius.row, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }

    private var durationLabel: some View {
        Text(AppFormatters.duration(recording.duration))
            .font(AppTypography.duration)
            .monospacedDigit()
            .foregroundStyle(Palette.secondaryLabel.opacity(isSelected ? 0.88 : 0.76))
            .frame(height: 18)
    }

    @ViewBuilder
    private var subtitle: some View {
        switch recording.status {
        case .processing:
            if isActivelyProcessing {
                Text("전사 중")
                    .foregroundStyle(Palette.secondaryLabel)
            } else {
                HStack(spacing: 3) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 9, weight: .semibold))
                    Text("재시도 필요")
                }
                .foregroundStyle(Palette.warning.opacity(0.82))
            }
        case .failed:
            HStack(spacing: 3) {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 9, weight: .semibold))
                Text("확인 필요")
            }
            .foregroundStyle(Palette.warning.opacity(0.82))
        case .ready:
            Text(AppFormatters.listTime.string(from: recording.createdAt))
                .font(AppTypography.listMeta)
                .foregroundStyle(Palette.secondaryLabel)
        }
    }

    private var statusIcon: some View {
        Group {
            if recording.status == .failed || isStalledProcessing {
                ZStack {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(iconBackground)
                        .frame(width: 18, height: 18)

                    Image(systemName: iconName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(iconForeground)
                }
            } else {
                Image(systemName: iconName)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(iconForeground)
                    .frame(width: 18, height: 18)
            }
        }
        .frame(width: 20, height: 20)
    }

    private var rowBackground: some ShapeStyle {
        if isSelected {
            return AnyShapeStyle(Color.rowSelectionBackground)
        }

        if isHovering {
            return AnyShapeStyle(Color.controlSurface.opacity(0.44))
        }

        return AnyShapeStyle(Color.clear)
    }

    private var rowShadowColor: Color {
        .clear
    }

    private var iconBackground: Color {
        switch recording.status {
        case .processing:
            return isActivelyProcessing ? Palette.primary.opacity(0.08) : Palette.dangerBackground
        case .failed:
            return Palette.dangerBackground
        case .ready:
            return Color.clear
        }
    }

    private var iconName: String {
        switch recording.status {
        case .processing:
            return isActivelyProcessing ? "waveform" : "exclamationmark"
        case .failed:
            return "exclamationmark"
        case .ready:
            return "waveform"
        }
    }

    private var iconForeground: Color {
        switch recording.status {
        case .processing:
            return isActivelyProcessing ? Palette.primary.opacity(0.78) : Palette.warning.opacity(0.92)
        case .failed:
            return Palette.warning.opacity(0.92)
        case .ready:
            return isSelected ? Palette.primary.opacity(0.76) : Palette.secondaryLabel.opacity(0.72)
        }
    }

    private var titleColor: Color {
        switch recording.status {
        case .failed:
            return Palette.destructive
        case .processing:
            return isActivelyProcessing ? Palette.label.opacity(isSelected ? 0.96 : 0.84) : Palette.destructive
        case .ready:
            return Palette.label.opacity(isSelected ? 0.96 : 0.84)
        }
    }

    private var isStalledProcessing: Bool {
        recording.status == .processing && !isActivelyProcessing
    }
}

private struct EmptyRecordingsView: View {
    let isSearching: Bool

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "waveform.circle")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(Palette.tertiaryLabel)

            Text(isSearching ? "검색 결과 없음" : "녹음 없음")
                .font(Typography.emphasis)
                .foregroundStyle(Palette.secondaryLabel)

            if !isSearching {
                HStack(spacing: 4) {
                    Text("⌘N")
                        .font(AppTypography.duration)
                        .foregroundStyle(Palette.secondaryLabel)
                        .padding(.horizontal, 5)
                        .frame(height: 18)
                        .background(Palette.bg2, in: RoundedRectangle(cornerRadius: 4, style: .continuous))

                    Text("으로 첫 녹음을 시작하세요")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.tertiaryLabel)
                }
            }
        }
    }
}

private struct CircularProcessingIndicator: View {
    @State private var rotation: Double = 0

    var body: some View {
        Circle()
            .trim(from: 0.16, to: 0.82)
            .stroke(
                Palette.secondaryLabel.opacity(0.64),
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

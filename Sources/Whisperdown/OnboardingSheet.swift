import AppKit
import SwiftUI

/// 첫 실행/엔진 설정 온보딩. 환영 → 진단 → 모델 선택 3스텝.
/// Settings의 "전사 엔진" 탭이 진단·모델 뷰(EngineDiagnosticsView/ModelListView)를 공용한다.
struct OnboardingSheet: View {
    enum Step: String, Identifiable {
        case welcome
        case diagnostics
        case modelPicker

        var id: String { rawValue }
    }

    @ObservedObject var manager: ModelDownloadManager
    let initialStep: Step
    let onClose: () -> Void

    @State private var step: Step
    @State private var engineStatus: EngineStatus

    init(manager: ModelDownloadManager, initialStep: Step = .welcome, onClose: @escaping () -> Void) {
        self.manager = manager
        self.initialStep = initialStep
        self.onClose = onClose
        _step = State(initialValue: initialStep)
        _engineStatus = State(initialValue: WhisperCppTranscriptionEngine().status())
    }

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .frame(width: 480)
        .background(Palette.bg1)
        .onChange(of: manager.states) {
            engineStatus = WhisperCppTranscriptionEngine().status()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .welcome:
            welcome
        case .diagnostics:
            diagnostics
        case .modelPicker:
            modelPicker
        }
    }

    // MARK: - Step 1: 환영

    private var welcome: some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 44, weight: .regular))
                .foregroundStyle(Palette.label.opacity(0.9))
                .padding(.top, Spacing.xxl)

            VStack(spacing: Spacing.sm) {
                Text("Whisperdown")
                    .font(Typography.largeTitle)
                    .foregroundStyle(Palette.label)

                Text("녹음부터 전사까지, 모든 처리는 이 Mac 안에서만 이루어집니다.")
                    .font(Typography.body)
                    .foregroundStyle(Palette.secondaryLabel)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, Spacing.xxl)

            Button {
                step = .diagnostics
            } label: {
                Text("시작하기")
                    .font(Typography.emphasis)
                    .foregroundStyle(Palette.primaryForeground)
                    .padding(.horizontal, Spacing.xl)
                    .frame(height: 34)
                    .background(Palette.primary, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, Spacing.sm)
            .padding(.bottom, Spacing.xxl)
        }
    }

    // MARK: - Step 2: 진단

    private var diagnostics: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            sheetHeader(
                title: "전사 엔진 확인",
                subtitle: "고품질 로컬 전사(whisper.cpp)에 필요한 구성 요소를 확인합니다."
            )

            EngineDiagnosticsView(status: engineStatus) {
                engineStatus = WhisperCppTranscriptionEngine().status()
            }
            .padding(.horizontal, Spacing.xl)

            if !(engineStatus.whisperCLI.isFound && engineStatus.ffmpeg.isFound) {
                Text("설치 전에도 Apple Speech로 임시 전사를 사용할 수 있습니다.")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.tertiaryLabel)
                    .padding(.horizontal, Spacing.xl)
            }

            sheetFooter {
                if initialStep == .welcome {
                    Button("건너뛰기") { finish() }
                        .buttonStyle(.plain)
                        .font(Typography.body)
                        .foregroundStyle(Palette.secondaryLabel)
                }

                Spacer()

                Button {
                    step = .modelPicker
                } label: {
                    Text("다음: 모델 선택")
                        .font(Typography.emphasis)
                        .foregroundStyle(Palette.primaryForeground)
                        .padding(.horizontal, Spacing.lg)
                        .frame(height: 30)
                        .background(Palette.primary, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, Spacing.xl)
    }

    // MARK: - Step 3: 모델 선택

    private var modelPicker: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            sheetHeader(
                title: "전사 모델 다운로드",
                subtitle: "모델은 이 Mac에 저장되며 오프라인으로 동작합니다. 나중에 설정(⌘,)에서 변경할 수 있습니다."
            )

            ModelListView(manager: manager)
                .padding(.horizontal, Spacing.xl)

            sheetFooter {
                Button("이전") { step = .diagnostics }
                    .buttonStyle(.plain)
                    .font(Typography.body)
                    .foregroundStyle(Palette.secondaryLabel)

                Spacer()

                Button {
                    finish()
                } label: {
                    Text(manager.isAnyDownloadActive ? "백그라운드에서 계속" : "완료")
                        .font(Typography.emphasis)
                        .foregroundStyle(Palette.primaryForeground)
                        .padding(.horizontal, Spacing.lg)
                        .frame(height: 30)
                        .background(Palette.primary, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, Spacing.xl)
    }

    // MARK: - 공통

    private func sheetHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(title)
                .font(Typography.title)
                .foregroundStyle(Palette.label)

            Text(subtitle)
                .font(Typography.body)
                .foregroundStyle(Palette.secondaryLabel)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, Spacing.xl)
    }

    private func sheetFooter<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: Spacing.md) {
            content()
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.top, Spacing.sm)
    }

    private func finish() {
        onClose()
    }
}

// MARK: - 진단 뷰 (온보딩·Settings 공용)

struct EngineDiagnosticsView: View {
    let status: EngineStatus
    let onRefresh: () -> Void

    @State private var didCopyCommand = false

    private var needsBinaries: Bool {
        !(status.whisperCLI.isFound && status.ffmpeg.isFound)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            VStack(spacing: 0) {
                diagnosticRow(
                    title: "whisper-cli",
                    detail: status.whisperCLI.url?.path ?? "설치되지 않음",
                    isFound: status.whisperCLI.isFound
                )
                Divider().overlay(Color.hairline)
                diagnosticRow(
                    title: "ffmpeg",
                    detail: status.ffmpeg.url?.path ?? "설치되지 않음",
                    isFound: status.ffmpeg.isFound
                )
                Divider().overlay(Color.hairline)
                diagnosticRow(
                    title: "전사 모델",
                    detail: status.modelFileName ?? "다운로드 필요",
                    isFound: status.model.isFound
                )
            }
            .background(Palette.bg1Muted, in: RoundedRectangle(cornerRadius: AppRadius.panel, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppRadius.panel, style: .continuous)
                    .strokeBorder(Color.hairline, lineWidth: 1)
            }

            if needsBinaries {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("Homebrew로 필요한 도구를 설치하세요:")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.secondaryLabel)

                    HStack(spacing: Spacing.sm) {
                        Text("brew install whisper-cpp ffmpeg")
                            .font(Typography.mono)
                            .foregroundStyle(Palette.label)
                            .padding(.horizontal, Spacing.md)
                            .frame(height: 30)
                            .background(Palette.bg2, in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))

                        Button {
                            let pasteboard = NSPasteboard.general
                            pasteboard.clearContents()
                            pasteboard.setString("brew install whisper-cpp ffmpeg", forType: .string)
                            didCopyCommand = true
                            Task {
                                try? await Task.sleep(for: .seconds(1.6))
                                didCopyCommand = false
                            }
                        } label: {
                            Label(didCopyCommand ? "복사됨" : "복사", systemImage: didCopyCommand ? "checkmark" : "doc.on.doc")
                                .font(Typography.caption)
                                .foregroundStyle(didCopyCommand ? Palette.success : Palette.secondaryLabel)
                        }
                        .buttonStyle(.plain)

                        Button {
                            onRefresh()
                        } label: {
                            Label("다시 확인", systemImage: "arrow.clockwise")
                                .font(Typography.caption)
                                .foregroundStyle(Palette.secondaryLabel)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func diagnosticRow(title: String, detail: String, isFound: Bool) -> some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: isFound ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isFound ? Palette.success : Palette.warning)

            Text(title)
                .font(Typography.emphasis)
                .foregroundStyle(Palette.label)

            Spacer(minLength: Spacing.md)

            Text(detail)
                .font(Typography.caption)
                .foregroundStyle(Palette.tertiaryLabel)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, Spacing.md)
        .frame(height: 40)
    }
}

// MARK: - 모델 리스트 (온보딩·Settings 공용)

struct ModelListView: View {
    @ObservedObject var manager: ModelDownloadManager

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(ModelCatalog.all.enumerated()), id: \.element.id) { index, model in
                if index > 0 {
                    Divider().overlay(Color.hairline)
                }

                ModelRow(model: model, state: manager.state(for: model)) { action in
                    switch action {
                    case .download:
                        manager.startDownload(model)
                    case .cancel:
                        manager.cancelDownload(model)
                    }
                }
            }
        }
        .background(Palette.bg1Muted, in: RoundedRectangle(cornerRadius: AppRadius.panel, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppRadius.panel, style: .continuous)
                .strokeBorder(Color.hairline, lineWidth: 1)
        }
        .onAppear {
            manager.refreshInstalled()
        }
    }
}

private struct ModelRow: View {
    enum Action {
        case download
        case cancel
    }

    let model: WhisperModel
    let state: ModelDownloadManager.DownloadState
    let onAction: (Action) -> Void

    var body: some View {
        HStack(spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Spacing.sm) {
                    Text(model.displayName)
                        .font(Typography.emphasis)
                        .foregroundStyle(Palette.label)

                    if model.isRecommended {
                        Text("추천")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Palette.success)
                            .padding(.horizontal, 6)
                            .frame(height: 16)
                            .background(Palette.success.opacity(0.12), in: Capsule())
                    }
                }

                Text("\(model.formattedSize) · \(model.detail)")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.secondaryLabel)
            }

            Spacer(minLength: Spacing.md)

            trailing
        }
        .padding(.horizontal, Spacing.md)
        .frame(height: 52)
    }

    @ViewBuilder
    private var trailing: some View {
        switch state {
        case .idle:
            Button {
                onAction(.download)
            } label: {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(Palette.secondaryLabel)
            }
            .buttonStyle(.plain)
            .help("다운로드")

        case .downloading(let fraction, _, _):
            HStack(spacing: Spacing.sm) {
                Text("\(Int(fraction * 100))%")
                    .font(AppTypography.duration)
                    .monospacedDigit()
                    .foregroundStyle(Palette.secondaryLabel)

                ProgressView(value: fraction)
                    .progressViewStyle(.linear)
                    .frame(width: 90)

                Button {
                    onAction(.cancel)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.tertiaryLabel)
                }
                .buttonStyle(.plain)
                .help("취소")
            }

        case .failed(let message):
            HStack(spacing: Spacing.sm) {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.warning)
                    .help(message)

                Button("재시도") {
                    onAction(.download)
                }
                .buttonStyle(.plain)
                .font(Typography.caption)
                .foregroundStyle(Palette.secondaryLabel)
            }

        case .installed:
            Label("설치됨", systemImage: "checkmark.circle.fill")
                .font(Typography.caption)
                .foregroundStyle(Palette.success)
        }
    }
}

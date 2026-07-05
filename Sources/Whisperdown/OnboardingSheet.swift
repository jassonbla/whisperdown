import AppKit
import SwiftUI

/// 첫 실행/엔진 설정 온보딩. 환영 → 진단 → 모델 선택 3스텝.
/// Settings의 "전사 엔진" 탭이 진단·모델 뷰(EngineDiagnosticsView/ModelListView)를 공용한다.
struct OnboardingSheet: View {
    @Environment(\.appLanguage) private var language

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
        .frame(maxHeight: 680)
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

                Text(L10n.t("onboarding.welcome.subtitle", language))
                    .font(Typography.body)
                    .foregroundStyle(Palette.secondaryLabel)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, Spacing.xxl)

            Button {
                step = .diagnostics
            } label: {
                Text(L10n.t("onboarding.welcome.start", language))
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
        VStack(alignment: .leading, spacing: 0) {
            sheetHeader(
                title: L10n.t("onboarding.diagnostics.title", language),
                subtitle: L10n.t("onboarding.diagnostics.subtitle", language)
            )
            .padding(.bottom, Spacing.lg)

            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    EngineDiagnosticsView(status: engineStatus) {
                        engineStatus = WhisperCppTranscriptionEngine().status()
                    }

                    if !(engineStatus.whisperCLI.isFound && engineStatus.ffmpeg.isFound) {
                        Text(L10n.t("onboarding.diagnostics.appleSpeechNote", language))
                            .font(Typography.caption)
                            .foregroundStyle(Palette.tertiaryLabel)
                    }
                }
                .padding(.horizontal, Spacing.xl)
            }

            sheetFooter {
                if initialStep == .welcome {
                    // 최초 실행 온보딩: welcome → diagnostics → modelPicker 선형 흐름 유지
                    Button(L10n.t("onboarding.diagnostics.skip", language)) { finish() }
                        .buttonStyle(.plain)
                        .font(Typography.body)
                        .foregroundStyle(Palette.secondaryLabel)

                    Spacer()

                    Button {
                        step = .modelPicker
                    } label: {
                        Text(L10n.t("onboarding.diagnostics.next", language))
                            .font(Typography.emphasis)
                            .foregroundStyle(Palette.primaryForeground)
                            .padding(.horizontal, Spacing.lg)
                            .frame(height: 30)
                            .background(Palette.primary, in: Capsule())
                    }
                    .buttonStyle(.plain)
                } else {
                    // Settings에서 상태 확인 목적으로 직접 진입한 경우: 확인만 하고 닫을 수 있어야 한다 —
                    // 모델 변경은 원할 때만 별도 버튼으로 분리.
                    Button(L10n.t("onboarding.diagnostics.close", language)) { finish() }
                        .buttonStyle(.plain)
                        .font(Typography.body)
                        .foregroundStyle(Palette.secondaryLabel)

                    Spacer()

                    Button {
                        step = .modelPicker
                    } label: {
                        Text(L10n.t("onboarding.diagnostics.changeModel", language))
                            .font(Typography.emphasis)
                            .foregroundStyle(Palette.primaryForeground)
                            .padding(.horizontal, Spacing.lg)
                            .frame(height: 30)
                            .background(Palette.primary, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, Spacing.xl)
    }

    // MARK: - Step 3: 모델 선택

    private var modelPicker: some View {
        VStack(alignment: .leading, spacing: 0) {
            sheetHeader(
                title: L10n.t("onboarding.modelPicker.title", language),
                subtitle: L10n.t("onboarding.modelPicker.subtitle", language)
            )
            .padding(.bottom, Spacing.lg)

            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    ModelListView(manager: manager)

                    DiarizationSetupView(manager: manager)

                    SummarySetupView(manager: manager)
                }
                .padding(.horizontal, Spacing.xl)
            }

            sheetFooter {
                Button(L10n.t("onboarding.modelPicker.back", language)) { step = .diagnostics }
                    .buttonStyle(.plain)
                    .font(Typography.body)
                    .foregroundStyle(Palette.secondaryLabel)

                Spacer()

                Button {
                    finish()
                } label: {
                    Text(manager.isAnyDownloadActive ? L10n.t("onboarding.modelPicker.continueBackground", language) : L10n.t("onboarding.modelPicker.done", language))
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
    @Environment(\.appLanguage) private var language

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
                    detail: status.whisperCLI.url?.path ?? L10n.t("engine.diagnostics.notInstalled", language),
                    isFound: status.whisperCLI.isFound
                )
                Divider().overlay(Color.hairline)
                diagnosticRow(
                    title: "ffmpeg",
                    detail: status.ffmpeg.url?.path ?? L10n.t("engine.diagnostics.notInstalled", language),
                    isFound: status.ffmpeg.isFound
                )
                Divider().overlay(Color.hairline)
                diagnosticRow(
                    title: L10n.t("engine.diagnostics.model", language),
                    detail: status.modelFileName ?? L10n.t("engine.diagnostics.needsDownload", language),
                    isFound: status.model.isFound
                )
            }
            .background(Palette.bg1Muted, in: RoundedRectangle(cornerRadius: AppRadius.panel, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppRadius.panel, style: .continuous)
                    .strokeBorder(Color.hairline, lineWidth: 1)
            }

            diarizationDiagnosticsBox

            if needsBinaries {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text(L10n.t("engine.diagnostics.installHint", language))
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
                            Label(didCopyCommand ? L10n.t("engine.diagnostics.copied", language) : L10n.t("engine.diagnostics.copy", language), systemImage: didCopyCommand ? "checkmark" : "doc.on.doc")
                                .font(Typography.caption)
                                .foregroundStyle(didCopyCommand ? Palette.success : Palette.secondaryLabel)
                        }
                        .buttonStyle(.plain)

                        Button {
                            onRefresh()
                        } label: {
                            Label(L10n.t("engine.diagnostics.recheck", language), systemImage: "arrow.clockwise")
                                .font(Typography.caption)
                                .foregroundStyle(Palette.secondaryLabel)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    /// 화자 분리(선택 기능) 상태 박스. isFullyConfigured 게이트에는 참여하지 않는다.
    private var diarizationDiagnosticsBox: some View {
        let diarizationStatus = SpeakerDiarizationEngine().status()

        return VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(L10n.t("diarization.section.title", language))
                .font(Typography.caption)
                .foregroundStyle(Palette.secondaryLabel)

            VStack(spacing: 0) {
                diagnosticRow(
                    title: L10n.t("diarization.diagnostics.cli", language),
                    detail: diarizationStatus.cli.url?.path ?? L10n.t("engine.diagnostics.notInstalled", language),
                    isFound: diarizationStatus.cli.isFound,
                    isOptional: true
                )
                Divider().overlay(Color.hairline)
                diagnosticRow(
                    title: L10n.t("diarization.diagnostics.segmentation", language),
                    detail: diarizationStatus.segmentationModel.url?.lastPathComponent ?? L10n.t("engine.diagnostics.needsDownload", language),
                    isFound: diarizationStatus.segmentationModel.isFound,
                    isOptional: true
                )
                Divider().overlay(Color.hairline)
                diagnosticRow(
                    title: L10n.t("diarization.diagnostics.embedding", language),
                    detail: diarizationStatus.embeddingModel.url?.lastPathComponent ?? L10n.t("engine.diagnostics.needsDownload", language),
                    isFound: diarizationStatus.embeddingModel.isFound,
                    isOptional: true
                )
            }
            .background(Palette.bg1Muted, in: RoundedRectangle(cornerRadius: AppRadius.panel, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppRadius.panel, style: .continuous)
                    .strokeBorder(Color.hairline, lineWidth: 1)
            }
        }
    }

    private func diagnosticRow(title: String, detail: String, isFound: Bool, isOptional: Bool = false) -> some View {
        HStack(spacing: Spacing.md) {
            Group {
                if isFound {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Palette.success)
                } else if isOptional {
                    // 선택 기능의 미설치는 경고가 아니다 — 조용한 빈 원
                    Image(systemName: "circle")
                        .foregroundStyle(Palette.tertiaryLabel)
                } else {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(Palette.warning)
                }
            }
            .font(.system(size: 13, weight: .medium))

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

// MARK: - 화자 분리 설치 (온보딩·Settings 공용)

/// sherpa-onnx 사이드카(엔진 + 모델 2개)를 하나의 집계 행으로 설치/제거한다.
struct DiarizationSetupView: View {
    @Environment(\.appLanguage) private var language
    @ObservedObject var manager: ModelDownloadManager

    private enum Aggregate: Equatable {
        case idle
        case downloading(fraction: Double)
        case failed(String)
        case installed
    }

    private var aggregate: Aggregate {
        let items = DiarizationCatalog.all
        let states = items.map { manager.state(forFileName: $0.fileName) }

        let anyDownloading = states.contains { if case .downloading = $0 { return true }; return false }
        if anyDownloading {
            // bytes 가중 진행률: 설치 완료 항목은 전체 크기로, 진행 중은 수신 바이트로 집계
            var done: Double = 0
            for (item, state) in zip(items, states) {
                switch state {
                case .installed:
                    done += Double(item.approximateBytes)
                case .downloading(_, let received, _):
                    done += Double(received)
                case .idle, .failed:
                    break
                }
            }
            return .downloading(fraction: min(1, done / Double(DiarizationCatalog.totalBytes)))
        }

        if states.allSatisfy({ $0 == .installed }) {
            return .installed
        }

        for state in states {
            if case .failed(let message) = state {
                return .failed(message)
            }
        }

        return .idle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(alignment: .center, spacing: Spacing.md) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.t("diarization.section.title", language))
                        .font(Typography.emphasis)
                        .foregroundStyle(Palette.label)

                    Text(L10n.t("diarization.section.subtitle", language))
                        .font(Typography.caption)
                        .foregroundStyle(Palette.tertiaryLabel)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: Spacing.md)

                trailingControl
            }
            .padding(Spacing.md)

            if case .failed(let message) = aggregate {
                Text(message)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.warning)
                    .padding(.horizontal, Spacing.md)
                    .padding(.bottom, Spacing.md)
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

    @ViewBuilder
    private var trailingControl: some View {
        switch aggregate {
        case .idle, .failed:
            Button {
                installAll()
            } label: {
                Text(L10n.t("diarization.install", language))
                    .font(Typography.emphasis)
                    .foregroundStyle(Palette.primaryForeground)
                    .padding(.horizontal, Spacing.md)
                    .frame(height: 26)
                    .background(Palette.primary, in: Capsule())
            }
            .buttonStyle(.plain)

        case .downloading(let fraction):
            HStack(spacing: Spacing.sm) {
                Text("\(Int((fraction * 100).rounded()))%")
                    .font(Typography.caption)
                    .monospacedDigit()
                    .foregroundStyle(Palette.secondaryLabel)

                CircularProcessingIndicator()
                    .frame(width: 14, height: 14)

                Button {
                    cancelAll()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Palette.tertiaryLabel)
                }
                .buttonStyle(.plain)
            }

        case .installed:
            HStack(spacing: Spacing.sm) {
                Label(L10n.t("diarization.installed", language), systemImage: "checkmark.circle.fill")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.success)

                Button {
                    try? SpeakerDiarizationEngine.uninstall()
                    manager.refreshInstalled()
                } label: {
                    Text(L10n.t("diarization.remove", language))
                        .font(Typography.caption)
                        .foregroundStyle(Palette.secondaryLabel)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func installAll() {
        for item in DiarizationCatalog.all where manager.state(forFileName: item.fileName) != .installed {
            manager.startDownload(item)
        }
    }

    private func cancelAll() {
        for item in DiarizationCatalog.all {
            if case .downloading = manager.state(forFileName: item.fileName) {
                manager.cancelDownload(item)
            }
        }
    }
}

/// AI 요약 카드 — 엔진 선택(Apple 기본 / Gemma 로컬 모델)과 하드웨어 맞춤 배지,
/// 모델 다운로드/제거, 용어집 편집을 담는다. DiarizationSetupView와 동일한 레이아웃 언어.
struct SummarySetupView: View {
    @Environment(\.appLanguage) private var language
    @ObservedObject var manager: ModelDownloadManager

    @AppStorage("summaryBackend") private var summaryBackendRaw = SummaryBackendKind.apple.rawValue
    @AppStorage("summaryModelFileName") private var selectedModelFileName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(Spacing.md)

            Divider().overlay(Color.hairline)

            appleRow
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)

            ForEach(SummaryModelCatalog.all) { model in
                Divider()
                    .overlay(Color.hairline.opacity(0.6))
                    .padding(.leading, Spacing.md)

                SummaryModelRow(
                    model: model,
                    state: manager.state(forFileName: model.fileName),
                    isSelected: isLocalSelected(model),
                    onSelect: { select(model) },
                    onDownload: { download(model) },
                    onCancel: { manager.cancelDownload(model.downloadItem) },
                    onRemove: { remove(model) }
                )
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
            }

            Divider().overlay(Color.hairline)

            footer
                .padding(Spacing.md)
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

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(L10n.t("summary.section.title", language))
                .font(Typography.emphasis)
                .foregroundStyle(Palette.label)

            Text(L10n.t("summary.section.subtitle", language))
                .font(Typography.caption)
                .foregroundStyle(Palette.tertiaryLabel)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var appleRow: some View {
        HStack(spacing: Spacing.md) {
            radio(isOn: SummaryBackendKind(rawValue: summaryBackendRaw) == .apple, enabled: true) {
                summaryBackendRaw = SummaryBackendKind.apple.rawValue
                NotificationCenter.default.post(name: .summaryBackendChanged, object: nil)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.t("summary.engine.apple", language))
                    .font(Typography.emphasis)
                    .foregroundStyle(Palette.label)
                Text(L10n.t("summary.engine.apple.detail", language))
                    .font(Typography.caption)
                    .foregroundStyle(Palette.tertiaryLabel)
            }

            Spacer(minLength: Spacing.md)

            appleBadge
        }
    }

    @ViewBuilder
    private var appleBadge: some View {
        switch SummaryEngine.appleAvailability() {
        case .available:
            Label(L10n.t("summary.status.available", language), systemImage: "checkmark.circle.fill")
                .font(Typography.caption)
                .foregroundStyle(Palette.success)
        case .unsupportedOS:
            Text(L10n.t("summary.status.unsupportedOS", language))
                .font(Typography.caption)
                .foregroundStyle(Palette.tertiaryLabel)
        case .modelUnavailable(let reason):
            Text(String(format: L10n.t("summary.status.modelUnavailable", language), reason))
                .font(Typography.caption)
                .foregroundStyle(Palette.tertiaryLabel)
                .lineLimit(2)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.md) {
                Button {
                    NotificationCenter.default.post(name: .openGlossaryRequested, object: nil)
                } label: {
                    Text(L10n.t("summary.glossary.edit", language))
                        .font(Typography.caption)
                        .foregroundStyle(Palette.label.opacity(0.84))
                        .padding(.horizontal, Spacing.md)
                        .frame(height: 24)
                        .background(Color.controlSurface.opacity(0.7), in: Capsule())
                }
                .buttonStyle(.plain)

                Text(L10n.t("summary.glossary.hint", language))
                    .font(Typography.caption)
                    .foregroundStyle(Palette.tertiaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if manager.state(forFileName: SummaryModelCatalog.runtime.fileName) == .installed {
                HStack(spacing: Spacing.sm) {
                    Text(String(format: L10n.t("summary.runtime.installed", language), SummaryModelCatalog.runtimeVersion))
                        .font(Typography.caption)
                        .foregroundStyle(Palette.tertiaryLabel)

                    Button {
                        try? LlamaSummaryEngine.uninstall()
                        summaryBackendRaw = SummaryBackendKind.apple.rawValue
                        selectedModelFileName = ""
                        manager.refreshInstalled()
                        NotificationCenter.default.post(name: .summaryBackendChanged, object: nil)
                    } label: {
                        Text(L10n.t("summary.runtime.removeAll", language))
                            .font(Typography.caption)
                            .foregroundStyle(Palette.secondaryLabel)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func radio(isOn: Bool, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                .font(Typography.headline)
                .foregroundStyle(isOn ? Palette.success : (enabled ? Palette.secondaryLabel : Palette.tertiaryLabel))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private func isLocalSelected(_ model: SummaryModel) -> Bool {
        SummaryBackendKind(rawValue: summaryBackendRaw) == .local && selectedModelFileName == model.fileName
    }

    private func select(_ model: SummaryModel) {
        summaryBackendRaw = SummaryBackendKind.local.rawValue
        selectedModelFileName = model.fileName
        NotificationCenter.default.post(name: .summaryBackendChanged, object: nil)
    }

    private func download(_ model: SummaryModel) {
        if manager.state(forFileName: SummaryModelCatalog.runtime.fileName) != .installed {
            manager.startDownload(SummaryModelCatalog.runtime)
        }
        manager.startDownload(model.downloadItem)
    }

    private func remove(_ model: SummaryModel) {
        LlamaSummaryEngine.removeModel(fileName: model.fileName)
        if selectedModelFileName == model.fileName {
            summaryBackendRaw = SummaryBackendKind.apple.rawValue
            selectedModelFileName = ""
            NotificationCenter.default.post(name: .summaryBackendChanged, object: nil)
        }
        manager.refreshInstalled()
    }
}

/// 로컬 GGUF 모델 1행 — 라디오 + 하드웨어 맞춤 배지 + 다운로드 상태 컨트롤.
private struct SummaryModelRow: View {
    @Environment(\.appLanguage) private var language

    let model: SummaryModel
    let state: ModelDownloadManager.DownloadState
    let isSelected: Bool
    let onSelect: () -> Void
    let onDownload: () -> Void
    let onCancel: () -> Void
    let onRemove: () -> Void

    private var fit: SummaryModelFit {
        SummaryModelFit.fit(for: model)
    }

    private var isSelectable: Bool {
        state == .installed && fit != .insufficient
    }

    var body: some View {
        HStack(spacing: Spacing.md) {
            Button {
                onSelect()
            } label: {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(Typography.headline)
                    .foregroundStyle(isSelected ? Palette.success : (isSelectable ? Palette.secondaryLabel : Palette.tertiaryLabel))
            }
            .buttonStyle(.plain)
            .disabled(!isSelectable)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Spacing.sm) {
                    Text(model.displayName)
                        .font(Typography.emphasis)
                        .foregroundStyle(Palette.label)

                    fitBadge
                }

                Text("\(model.formattedSize) · \(String(format: L10n.t("summary.model.context", language), model.formattedContext)) · \(L10n.t(model.detailKey, language))")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.tertiaryLabel)

                Text(String(format: L10n.t("summary.model.ram", language), model.formattedRecommendedRAM, Self.thisMacRAM))
                    .font(AppTypography.listMeta)
                    .foregroundStyle(Palette.tertiaryLabel)
            }

            Spacer(minLength: Spacing.md)

            trailingControl
        }
        .opacity(fit == .insufficient ? 0.5 : 1)
    }

    private static let thisMacRAM = ByteCountFormatter.string(
        fromByteCount: Int64(ProcessInfo.processInfo.physicalMemory),
        countStyle: .memory
    )

    @ViewBuilder
    private var fitBadge: some View {
        switch fit {
        case .recommended:
            badge(L10n.t("summary.model.badge.recommended", language), color: Palette.success)
        case .maySlow:
            badge(L10n.t("summary.model.badge.maySlow", language), color: Palette.warning)
        case .insufficient:
            badge(L10n.t("summary.model.badge.insufficient", language), color: Palette.destructive)
        }
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(AppTypography.listMeta)
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(color.opacity(0.12), in: Capsule())
    }

    @ViewBuilder
    private var trailingControl: some View {
        switch state {
        case .idle:
            Button(action: onDownload) {
                Image(systemName: "arrow.down.circle")
                    .font(Typography.headline)
                    .foregroundStyle(fit == .insufficient ? Palette.tertiaryLabel : Palette.secondaryLabel)
            }
            .buttonStyle(.plain)
            .disabled(fit == .insufficient)

        case .downloading(let fraction, _, _):
            HStack(spacing: Spacing.sm) {
                Text("\(Int((fraction * 100).rounded()))%")
                    .font(Typography.caption)
                    .monospacedDigit()
                    .foregroundStyle(Palette.secondaryLabel)

                CircularProcessingIndicator()
                    .frame(width: 14, height: 14)

                Button(action: onCancel) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Palette.tertiaryLabel)
                }
                .buttonStyle(.plain)
            }

        case .failed:
            Button(action: onDownload) {
                Image(systemName: "exclamationmark.arrow.circlepath")
                    .font(Typography.headline)
                    .foregroundStyle(Palette.warning)
            }
            .buttonStyle(.plain)

        case .installed:
            HStack(spacing: Spacing.sm) {
                Image(systemName: "checkmark.circle.fill")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.success)

                Button(action: onRemove) {
                    Text(L10n.t("summary.model.remove", language))
                        .font(Typography.caption)
                        .foregroundStyle(Palette.secondaryLabel)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct ModelRow: View {
    @Environment(\.appLanguage) private var language

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
                        Text(L10n.t("model.recommended", language))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Palette.success)
                            .padding(.horizontal, 6)
                            .frame(height: 16)
                            .background(Palette.success.opacity(0.12), in: Capsule())
                    }
                }

                Text("\(model.formattedSize) · \(L10n.t(model.detailKey, language))")
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
            .help(L10n.t("model.download.help", language))

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
                .help(L10n.t("action.cancel", language))
            }

        case .failed(let message):
            HStack(spacing: Spacing.sm) {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.warning)
                    .help(message)

                Button(L10n.t("model.retry", language)) {
                    onAction(.download)
                }
                .buttonStyle(.plain)
                .font(Typography.caption)
                .foregroundStyle(Palette.secondaryLabel)
            }

        case .installed:
            Label(L10n.t("model.installed", language), systemImage: "checkmark.circle.fill")
                .font(Typography.caption)
                .foregroundStyle(Palette.success)
        }
    }
}

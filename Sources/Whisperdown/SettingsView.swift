import AppKit
import SwiftUI

enum SettingsTab: Hashable {
    case general
    case engine
}

/// Settings 씬은 열릴 때마다 새로 생성되므로, 특정 탭을 지정해 열기 위한 상태는
/// 씬 밖(예: DetailView의 엔진 배지)에서도 접근 가능한 공유 싱글턴에 둔다.
@MainActor
final class SettingsNavigation: ObservableObject {
    static let shared = SettingsNavigation()

    @Published var selectedTab: SettingsTab = .general

    private init() {}
}

/// 앱 설정 (⌘,). RootView가 소유한 시트로 떠서 메인 창에 종속된다(별도 NSWindow 아님) —
/// 상태는 shared 싱글턴/노티로 동기화한다.
struct SettingsView: View {
    @AppStorage("appLanguage") private var appLanguageRaw = AppLanguage.en.rawValue
    @ObservedObject private var navigation = SettingsNavigation.shared

    private var language: AppLanguage {
        AppLanguage(rawValue: appLanguageRaw) ?? .en
    }

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Spacing.md) {
                Text(L10n.t("settings.title", language))
                    .font(Typography.headline)
                    .foregroundStyle(Palette.label)
                    .accessibilityAddTraits(.isHeader)

                Spacer(minLength: Spacing.md)

                IconButton(systemName: "xmark", label: L10n.t("action.close", language), iconSize: 11) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding(.leading, Spacing.xl)
            .padding(.trailing, Spacing.lg)
            .padding(.top, Spacing.lg)
            .padding(.bottom, Spacing.sm)

            UnderlineTabs(
                items: [
                    (SettingsTab.general, L10n.t("settings.tab.general", language)),
                    (SettingsTab.engine, L10n.t("settings.tab.engine", language))
                ],
                selection: $navigation.selectedTab
            )
            .padding(.horizontal, Spacing.xl)

            Rectangle()
                .fill(Color.hairline)
                .frame(height: 1)

            Group {
                switch navigation.selectedTab {
                case .general:
                    GeneralSettingsView()
                case .engine:
                    EngineSettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .environment(\.appLanguage, language)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.bg1)
        .tooltipHost()
    }
}

/// 설정 섹션의 대문자 모노 라벨.
private struct SettingsSectionLabel: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(Typography.overline)
            .tracking(0.6)
            .foregroundStyle(Palette.secondaryLabel)
            .accessibilityAddTraits(.isHeader)
    }
}

private struct GeneralSettingsView: View {
    @Environment(\.appLanguage) private var language
    @AppStorage("appLanguage") private var appLanguageRaw = AppLanguage.en.rawValue
    @State private var markdownDirectoryPath = GeneralSettingsView.currentPath()

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                SettingsSectionLabel(text: L10n.t("settings.language", language))

                SegmentedControl(
                    items: AppLanguage.allCases.map { ($0.rawValue, $0.displayName) },
                    selection: $appLanguageRaw
                )
                .accessibilityElement(children: .contain)
                .accessibilityLabel(L10n.t("settings.language", language))
            }

            VStack(alignment: .leading, spacing: Spacing.sm) {
                SettingsSectionLabel(text: L10n.t("settings.markdownFolder.label", language))

                HStack(spacing: Spacing.sm) {
                    Text(markdownDirectoryPath)
                        .font(AppTypography.meta)
                        .foregroundStyle(Palette.secondaryLabel)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .padding(.horizontal, Spacing.md)
                        .frame(height: AppMetric.controlHeight, alignment: .leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Palette.bg1Muted, in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                                .strokeBorder(Color.hairline, lineWidth: 1)
                        }

                    Button(L10n.t("settings.markdownFolder.change", language)) {
                        chooseDirectory()
                    }
                    .buttonStyle(ControlButtonStyle())
                }

                Text(L10n.t("settings.markdownFolder.hint", language))
                    .font(Typography.caption)
                    .foregroundStyle(Palette.tertiaryLabel)
            }
        }
        .padding(Spacing.xl)
    }

    private static func currentPath() -> String {
        UserDefaults.standard.string(forKey: "markdownDirectory")
            ?? (FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
                ?? FileManager.default.homeDirectoryForCurrentUser)
                .appendingPathComponent("Whisperdown").path
    }

    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.title = L10n.t("settings.markdownFolder.pickerTitle", AppLanguage.current)
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: markdownDirectoryPath)

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        UserDefaults.standard.set(url.path, forKey: "markdownDirectory")
        markdownDirectoryPath = url.path
        NotificationCenter.default.post(name: .markdownDirectoryChanged, object: nil)
    }
}

private struct EngineSettingsView: View {
    @Environment(\.appLanguage) private var language
    @ObservedObject private var manager = ModelDownloadManager.shared
    @State private var engineStatus = WhisperCppTranscriptionEngine().status()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                EngineDiagnosticsView(status: engineStatus) {
                    engineStatus = WhisperCppTranscriptionEngine().status()
                }

                VStack(alignment: .leading, spacing: Spacing.sm) {
                    SettingsSectionLabel(text: L10n.t("engine.diagnostics.model", language))

                    ModelListView(manager: manager)
                }

                DiarizationSetupView(manager: manager)

                SummarySetupView(manager: manager)
            }
            .padding(Spacing.xl)
        }
        .onChange(of: manager.states) {
            engineStatus = WhisperCppTranscriptionEngine().status()
        }
    }
}

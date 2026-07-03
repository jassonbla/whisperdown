import AppKit
import SwiftUI

/// 앱 설정 (⌘,). Settings 씬은 별도 창이므로 상태는 shared 싱글턴/노티로 동기화한다.
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("일반", systemImage: "gearshape")
                }

            EngineSettingsView()
                .tabItem {
                    Label("전사 엔진", systemImage: "waveform")
                }
        }
        .frame(width: 520)
        .background(Palette.bg1)
    }
}

private struct GeneralSettingsView: View {
    @State private var markdownDirectoryPath = GeneralSettingsView.currentPath()

    var body: some View {
        Form {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("Markdown 저장 폴더")
                    .font(Typography.emphasis)
                    .foregroundStyle(Palette.label)

                HStack(spacing: Spacing.sm) {
                    Text(markdownDirectoryPath)
                        .font(Typography.caption)
                        .foregroundStyle(Palette.secondaryLabel)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .padding(.horizontal, Spacing.md)
                        .frame(height: 28, alignment: .leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Palette.bg1Muted, in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                                .strokeBorder(Color.hairline, lineWidth: 1)
                        }

                    Button("변경…") {
                        chooseDirectory()
                    }
                }

                Text("녹음 오디오와 전사 Markdown이 이 폴더에 저장됩니다.")
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
        panel.title = "Markdown 저장 폴더"
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
    @ObservedObject private var manager = ModelDownloadManager.shared
    @State private var engineStatus = WhisperCppTranscriptionEngine().status()

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            EngineDiagnosticsView(status: engineStatus) {
                engineStatus = WhisperCppTranscriptionEngine().status()
            }

            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("전사 모델")
                    .font(Typography.emphasis)
                    .foregroundStyle(Palette.label)

                ModelListView(manager: manager)
            }
        }
        .padding(Spacing.xl)
        .onChange(of: manager.states) {
            engineStatus = WhisperCppTranscriptionEngine().status()
        }
    }
}

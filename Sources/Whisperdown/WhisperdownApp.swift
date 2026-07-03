import SwiftUI

@main
struct WhisperdownApp: App {
    /// 개발/검증용 외형 강제: WHISPERDOWN_APPEARANCE=dark|light. 미설정 시 시스템 따름.
    private static var forcedScheme: ColorScheme? {
        switch ProcessInfo.processInfo.environment["WHISPERDOWN_APPEARANCE"]?.lowercased() {
        case "dark": return .dark
        case "light": return .light
        default: return nil
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .frame(minWidth: 1080, minHeight: 720)
                .preferredColorScheme(Self.forcedScheme)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1080, height: 720)
        .defaultPosition(.center)
        .commands {
            CommandGroup(after: .newItem) {
                Button("새 녹음 / 녹음 정지") {
                    NotificationCenter.default.post(name: .toggleRecordingRequested, object: nil)
                }
                .keyboardShortcut("n", modifiers: [.command])

                Button("검색") {
                    NotificationCenter.default.post(name: .focusSearchRequested, object: nil)
                }
                .keyboardShortcut("f", modifiers: [.command])

                Button("Open Markdown Folder") {
                    NotificationCenter.default.post(name: .openMarkdownFolderRequested, object: nil)
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            }
        }

        Settings {
            SettingsView()
                .preferredColorScheme(Self.forcedScheme)
        }
    }
}

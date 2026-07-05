import SwiftUI

@main
struct WhisperdownApp: App {
    @AppStorage("appLanguage") private var appLanguageRaw = AppLanguage.en.rawValue

    init() {
        // 아이콘 전용 버튼의 .help 툴팁이 빨리 뜨도록 macOS 기본 지연(~1.5s)을 줄인다.
        UserDefaults.standard.register(defaults: ["NSInitialToolTipDelay": 350])
    }

    private var language: AppLanguage {
        AppLanguage(rawValue: appLanguageRaw) ?? .en
    }

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
                Button(L10n.t("menu.newRecording", language)) {
                    NotificationCenter.default.post(name: .toggleRecordingRequested, object: nil)
                }
                .keyboardShortcut("n", modifiers: [.command])

                Button(L10n.t("menu.search", language)) {
                    NotificationCenter.default.post(name: .focusSearchRequested, object: nil)
                }
                .keyboardShortcut("f", modifiers: [.command])

                Button(L10n.t("menu.openMarkdownFolder", language)) {
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

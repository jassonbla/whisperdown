import AppKit
import SwiftUI

@main
struct RenderDesignSnapshot {
    @MainActor
    static func main() throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        let outputPath = arguments.first
            ?? ".build/design-snapshot.png"
        let colorScheme: ColorScheme = arguments.dropFirst().first == "dark" ? .dark : .light
        let scenario = DesignPreviewScenario(rawValue: arguments.dropFirst(2).first ?? "ready")
            ?? .ready
        let outputURL = URL(fileURLWithPath: outputPath)
        let width = CGFloat(Double(arguments.dropFirst(3).first ?? "") ?? 1280)
        let height = CGFloat(Double(arguments.dropFirst(4).first ?? "") ?? 800)
        let size = CGSize(width: width, height: height)

        // `settings-*` and `onboarding-*` render those sheets instead of the main window.
        let scenarioName = arguments.dropFirst(2).first ?? "ready"
        let content: AnyView
        if scenarioName.hasPrefix("settings-") {
            SettingsNavigation.shared.selectedTab = scenarioName == "settings-engine" ? .engine : .general
            content = AnyView(
                SettingsView()
                    .frame(width: size.width, height: size.height)
                    .environment(\.colorScheme, colorScheme)
            )
        } else if scenarioName == "tooltip" {
            // Draws the tooltip layer with forced items (no hover needed): centred, and clamped at the trailing edge.
            content = AnyView(
                HStack(spacing: Spacing.xs) {
                    IconButton(systemName: "folder", label: "Reveal in Finder") {}
                        .anchorPreference(key: TooltipPreferenceKey.self, value: .bounds) { anchor in
                            scenario == .ready ? TooltipItem(text: "Reveal in Finder", anchor: anchor) : nil
                        }
                    Spacer()
                    IconButton(systemName: "gearshape", label: "Settings") {}
                        .anchorPreference(key: TooltipPreferenceKey.self, value: .bounds) { anchor in
                            TooltipItem(text: "Transcription Engine Settings", anchor: anchor)
                        }
                }
                .padding(.horizontal, Spacing.sm)
                .frame(width: size.width, height: size.height, alignment: .top)
                .background(Palette.bg1)
                .tooltipHost()
                .environment(\.colorScheme, colorScheme)
            )
        } else if scenarioName.hasPrefix("onboarding-") {
            // `onboarding-welcome` / `onboarding-diagnostics` / `onboarding-modelPicker`
            let step = OnboardingSheet.Step(rawValue: String(scenarioName.dropFirst("onboarding-".count))) ?? .welcome
            content = AnyView(
                OnboardingSheet(manager: ModelDownloadManager.shared, initialStep: step) {}
                    .frame(width: size.width, height: size.height)
                    .environment(\.colorScheme, colorScheme)
            )
        } else {
            content = AnyView(
                DesignPreviewRootView(scenario: scenario)
                    .frame(width: size.width, height: size.height)
                    .environment(\.colorScheme, colorScheme)
            )
        }

        let hostingView = NSHostingView(rootView: content)
        hostingView.frame = CGRect(origin: .zero, size: size)
        hostingView.setFrameSize(size)
        hostingView.layoutSubtreeIfNeeded()

        guard let bitmap = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) else {
            throw SnapshotError.renderFailed
        }

        bitmap.size = size
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)

        guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
            throw SnapshotError.renderFailed
        }

        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try pngData.write(to: outputURL, options: [.atomic])
        print(outputURL.path)
    }
}

private enum SnapshotError: LocalizedError {
    case renderFailed

    var errorDescription: String? {
        "Failed to render the design snapshot."
    }
}

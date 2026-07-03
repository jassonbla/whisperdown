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

        let content = DesignPreviewRootView(scenario: scenario)
            .frame(width: size.width, height: size.height)
            .environment(\.colorScheme, colorScheme)

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

// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "VoiceToMarkdown",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "VoiceToMarkdown", targets: ["VoiceToMarkdown"])
    ],
    targets: [
        .executableTarget(
            name: "VoiceToMarkdown",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("Speech"),
                .linkedFramework("SwiftUI")
            ]
        )
    ]
)

// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Whisperdown",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Whisperdown", targets: ["Whisperdown"])
    ],
    targets: [
        .executableTarget(
            name: "Whisperdown",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("Speech"),
                .linkedFramework("SwiftUI")
            ]
        )
    ]
)

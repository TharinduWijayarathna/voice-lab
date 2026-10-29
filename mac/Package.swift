// swift-tools-version: 6.2
// VoiceLab: a native SwiftUI window (Liquid Glass, macOS 26) over the Kokoro voice engine in ../engine.
// Open this folder in Xcode 26, or build it with install.command.
import PackageDescription

let package = Package(
    name: "VoiceLab",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "VoiceLab",
            path: "Sources/VoiceLab",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)

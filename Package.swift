// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Codex-Usage",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "CodexUsage", targets: ["CodexUsage"]),
        .library(name: "CodexUsageCore", targets: ["CodexUsageCore"])
    ],
    targets: [
        .target(name: "CodexUsageCore"),
        .target(name: "CodexUsageAutomation", dependencies: ["CodexUsageCore"], resources: [.copy("Resources/apply-preset.js")]),
        .target(name: "CodexUsageWeb", resources: [.copy("Resources")]),
        .executableTarget(
            name: "CodexUsage",
            dependencies: ["CodexUsageCore", "CodexUsageAutomation", "CodexUsageWeb"]
        ),
        .executableTarget(
            name: "CodexUsageWebFixture",
            dependencies: ["CodexUsageCore", "CodexUsageWeb"],
            path: "Tests/WebDeckFixture"
        ),
        .testTarget(
            name: "CodexUsageTests",
            dependencies: ["CodexUsageCore", "CodexUsageAutomation"]
        ),
        .testTarget(
            name: "CodexUsageWebTests",
            dependencies: ["CodexUsageWeb"]
        )
    ]
)

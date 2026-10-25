// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "FXMicBridge",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "FXMicBridge", targets: ["FXMicBridge"]),
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.9.0"),
    ],
    targets: [
        // Pure logic (device protocol, gestures, state machine): no UI, fully testable.
        .target(name: "FXMicCore", swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(
            name: "FXMicBridge",
            dependencies: ["FXMicCore", .product(name: "WhisperKit", package: "WhisperKit")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(name: "FXMicCoreTests", dependencies: ["FXMicCore"], swiftSettings: [.swiftLanguageMode(.v5)]),
        // Voice-command evaluation set (TDD voice command agent §3.7): scorer and engines, plus the CLI.
        .target(name: "AgentEvalKit", dependencies: ["FXMicCore"], swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(name: "AgentEval", dependencies: ["AgentEvalKit", "FXMicCore"],
                          swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "AgentEvalTests", dependencies: ["AgentEvalKit", "FXMicCore"],
                    swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)

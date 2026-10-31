// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ClipFlowCore",
    platforms: [.macOS(.v14)],
    products: [.library(name: "ClipFlowCore", targets: ["ClipFlowCore"])],
    targets: [
        .target(name: "ClipFlowCore", linkerSettings: [.linkedLibrary("sqlite3")]),
        .testTarget(name: "ClipFlowCoreTests", dependencies: ["ClipFlowCore"]),
    ]
)

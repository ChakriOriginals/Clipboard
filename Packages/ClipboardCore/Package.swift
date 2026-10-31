// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ClipboardCore",
    platforms: [.macOS(.v14)],
    products: [.library(name: "ClipboardCore", targets: ["ClipboardCore"])],
    targets: [
        .target(name: "ClipboardCore", linkerSettings: [.linkedLibrary("sqlite3")]),
        .testTarget(name: "ClipboardCoreTests", dependencies: ["ClipboardCore"], resources: [.copy("Fixtures")]),
    ]
)

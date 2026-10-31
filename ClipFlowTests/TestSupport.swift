import AppKit
import ClipFlowCore
import XCTest

/// A private pasteboard so tests never touch the user's clipboard.
func makeTestPasteboard() -> NSPasteboard {
    NSPasteboard(name: NSPasteboard.Name("dev.clipflow.tests.\(UUID().uuidString)"))
}

func makeTestDefaults() -> (UserDefaults, String) {
    let suite = "dev.clipflow.tests.\(UUID().uuidString)"
    return (UserDefaults(suiteName: suite)!, suite)
}

let enabledCapture = CaptureSettings(isPaused: false, excludedBundleIDs: [], captureImages: true, captureFiles: true,
                                     sensitiveHandling: .maskAndExpire)

/// Minimal raw SQLite access for tests that must corrupt or version-stamp a history file.
struct SQLiteProbe {
    let path: String
    init(path: String) throws { self.path = path }
    func setUserVersion(_ version: Int) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [path, "PRAGMA user_version = \(version);"]
        try process.run()
        process.waitUntilExit()
    }
}

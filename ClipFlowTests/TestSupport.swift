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

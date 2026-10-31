import AppKit
import ClipboardCore

/// Polls `changeCount` (the pasteboard has no change notification) and reports new content.
/// Skips changes Clipboard made itself, and decides paused/concealed/excluded before reading any data.
@MainActor
final class PasteboardMonitor {
    typealias FrontmostApp = (bundleID: String?, name: String?)

    private let pasteboard: NSPasteboard
    private let interval: TimeInterval
    private let settings: () -> CaptureSettings
    private let accessState: () -> PasteAccessState
    private let frontmostApp: () -> FrontmostApp?
    private let onSnapshot: (PasteboardSnapshot) -> Void
    private let onSkip: (SkipReason) -> Void
    private var timer: Timer?
    private var lastChangeCount: Int
    private var ignoredChangeCounts: Set<Int> = []

    init(pasteboard: NSPasteboard, interval: TimeInterval = 0.5,
         settings: @escaping () -> CaptureSettings,
         accessState: @escaping () -> PasteAccessState,
         frontmostApp: @escaping () -> FrontmostApp?,
         onSnapshot: @escaping (PasteboardSnapshot) -> Void,
         onSkip: @escaping (SkipReason) -> Void) {
        self.pasteboard = pasteboard
        self.interval = interval
        self.settings = settings
        self.accessState = accessState
        self.frontmostApp = frontmostApp
        self.onSnapshot = onSnapshot
        self.onSkip = onSkip
        lastChangeCount = pasteboard.changeCount
    }

    func start() {
        stop()
        lastChangeCount = pasteboard.changeCount
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pollNow() }
        }
        timer.tolerance = interval * 0.4
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Marks a change count produced by Clipboard's own write so it isn't captured again.
    func ignore(changeCount: Int) {
        ignoredChangeCounts.insert(changeCount)
    }

    func pollNow() {
        let count = pasteboard.changeCount
        guard count != lastChangeCount else { return }
        lastChangeCount = count
        if ignoredChangeCounts.remove(count) != nil { return }
        ignoredChangeCounts = ignoredChangeCounts.filter { $0 > count }
        guard accessState().mayReadAutomatically else { return }

        let app = frontmostApp()
        if let reason = CapturePolicy.precheck(types: PasteboardReader.typeNames(pasteboard),
                                               frontmostBundleID: app?.bundleID, settings: settings()) {
            onSkip(reason)
            return
        }
        onSnapshot(PasteboardReader.snapshot(pasteboard, frontmost: app))
    }
}

import AppKit
import ClipFlowCore
import SwiftUI

/// Owns the app's long-lived objects and wires them together.
@MainActor
final class AppController {
    let settings = SettingsStore()
    let model: HistoryModel
    let dataDirectory: URL
    private(set) var hotKeyError: HotKeyError?

    private var monitor: PasteboardMonitor!
    private var hotKey: HotKey?
    private var panel: PanelController!
    private var menuBar: MenuBarController!
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private var retentionTimer: Timer?

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        dataDirectory = support.appendingPathComponent("ClipFlow", isDirectory: true)
        let bundleID = Bundle.main.bundleIdentifier ?? "dev.clipflow.ClipFlow"
        let store = ClipStore(directory: dataDirectory, keyStore: KeychainKeyStore(service: "\(bundleID).history-key"),
                              deviceID: settings.deviceID)
        model = HistoryModel(store: store, settings: settings)
    }

    func start() {
        monitor = PasteboardMonitor(
            pasteboard: .general,
            settings: { [unowned self] in settings.captureSettings },
            accessState: { PasteAccessState.current(for: .general) },
            frontmostApp: { NSWorkspace.shared.frontmostApplication.map { ($0.bundleIdentifier, $0.localizedName) } },
            onSnapshot: { [weak self] snapshot in Task { await self?.model.ingest(snapshot) } },
            onSkip: { _ in })
        panel = PanelController(app: self)
        menuBar = MenuBarController(app: self)
        registerHotKey(settings.shortcut)

        Task {
            await model.load()
            monitor.start()
        }
        let timer = Timer(timeInterval: 3_600, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { _ = Task { await self?.model.applyRetention() } }
        }
        timer.tolerance = 300
        RunLoop.main.add(timer, forMode: .common)
        retentionTimer = timer

        if !settings.hasCompletedOnboarding { showOnboarding() }
    }

    // MARK: Panel

    func togglePanel() {
        panel.toggle()
    }

    /// Restores an entry; optionally pastes it into the app that was active before the panel opened.
    func choose(_ id: UUID, paste: Bool) {
        Task {
            guard await model.restore(id: id, to: .general, onWrite: { [monitor] in monitor?.ignore(changeCount: $0) }) != nil
            else { return }
            panel.hide()
            guard paste else { return }
            // Let the previous app's window become key again before sending ⌘V.
            try? await Task.sleep(for: .milliseconds(80))
            if !AutoPaster().paste() { promptForAccessibilityOnce() }
        }
    }

    private func promptForAccessibilityOnce() {
        let key = "hasPromptedForAccessibility"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        AutoPaster.requestTrust()
    }

    // MARK: Hotkey

    @discardableResult
    func registerHotKey(_ shortcut: Shortcut) -> HotKeyError? {
        hotKey?.unregister()
        hotKey = nil
        do {
            hotKey = try HotKey(shortcut: shortcut) { [weak self] in self?.togglePanel() }
            hotKeyError = nil
        } catch let error as HotKeyError {
            hotKeyError = error
        } catch {
            hotKeyError = .registrationFailed(-1)
        }
        return hotKeyError
    }

    /// Releases the global hotkey while the shortcut recorder listens for keys.
    func suspendHotKey() {
        hotKey?.unregister()
        hotKey = nil
    }

    // MARK: Monitoring

    func setPaused(_ paused: Bool) {
        settings.isPaused = paused
        menuBar.refreshIcon()
    }

    var accessState: PasteAccessState { PasteAccessState.current(for: .general) }

    // MARK: Windows

    func showSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(app: self)))
            window.title = "ClipFlow Settings"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    func showOnboarding() {
        if onboardingWindow == nil {
            let view = OnboardingView(app: self) { [weak self] in
                self?.settings.hasCompletedOnboarding = true
                self?.onboardingWindow?.close()
            }
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = "Welcome to ClipFlow"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            onboardingWindow = window
        }
        NSApp.activate()
        onboardingWindow?.makeKeyAndOrderFront(nil)
    }

    func confirmClearHistory() {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Clear clipboard history?"
        alert.informativeText = "“Clear Unpinned” keeps pinned items. “Clear Everything” deletes all history and its encryption key. This can’t be undone."
        alert.addButton(withTitle: "Clear Unpinned")
        let everything = alert.addButton(withTitle: "Clear Everything")
        everything.hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn: Task { await model.clearUnpinned() }
        case .alertSecondButtonReturn: Task { await model.clearEverything() }
        default: break
        }
    }

    static func openSystemSettings(_ anchor: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }
}

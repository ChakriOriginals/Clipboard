import AppKit
import Carbon.HIToolbox

/// The status item and its menu.
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private unowned let app: AppController
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

    init(app: AppController) {
        self.app = app
        super.init()
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        refreshIcon()
    }

    func refreshIcon() {
        let paused = app.settings.isPaused
        let image = NSImage(systemSymbolName: paused ? "pause.rectangle" : "list.clipboard",
                            accessibilityDescription: paused ? "Clipboard (paused)" : "Clipboard")
        image?.isTemplate = true
        statusItem.button?.image = image
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        for note in statusNotes() {
            let item = NSMenuItem(title: note, action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }
        if menu.numberOfItems > 0 { menu.addItem(.separator()) }

        let history = item("Clipboard History", #selector(openHistory))
        if let key = app.settings.shortcut.menuKeyEquivalent {
            history.keyEquivalent = key
            history.keyEquivalentModifierMask = app.settings.shortcut.modifierFlags
        }
        menu.addItem(history)
        menu.addItem(item(app.settings.isPaused ? "Resume Monitoring" : "Pause Monitoring", #selector(togglePause)))
        menu.addItem(.separator())
        menu.addItem(item("Settings…", #selector(openSettings), key: ","))
        menu.addItem(item("Clear History…", #selector(clearHistory)))
        menu.addItem(.separator())
        menu.addItem(item("Quit Clipboard", #selector(quit), key: "q"))
    }

    private func statusNotes() -> [String] {
        var notes: [String] = []
        if app.settings.isPaused { notes.append("Monitoring paused") }
        switch app.model.status {
        case .locked: notes.append("History locked — Keychain access denied")
        case .failed: notes.append("History unavailable")
        case .newerVersion: notes.append("History needs a newer Clipboard")
        default: break
        }
        switch app.accessState {
        case .needsAlwaysAllow, .denied: notes.append("Clipboard access not allowed — see Settings")
        default: break
        }
        if app.hotKeyError != nil { notes.append("Shortcut unavailable — choose another in Settings") }
        if IsSecureEventInputEnabled() { notes.append("Secure Input is on in another app") }
        return notes
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func openHistory() { app.togglePanel() }
    @objc private func togglePause() { app.setPaused(!app.settings.isPaused) }
    @objc private func openSettings() { app.showSettings() }
    @objc private func clearHistory() { app.confirmClearHistory() }
    @objc private func quit() { NSApp.terminate(nil) }
}

import SwiftUI

struct ShortcutsTab: View {
    let app: AppController
    @State private var error: String?

    var body: some View {
        Form {
            Section {
                LabeledContent("Open clipboard history") {
                    ShortcutRecorder(shortcut: app.settings.shortcut, onRecordingChange: { recording in
                        if recording { app.suspendHotKey() } else { app.registerHotKey(app.settings.shortcut) }
                    }, onRecord: apply)
                }
                if let error {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
                if app.settings.shortcut != .default {
                    Button("Reset to \(Shortcut.default.displayString)") { apply(.default) }
                }
            } footer: {
                Text("While Clipboard runs, this shortcut is reserved system-wide. ⇧⌘V replaces “Paste as plain text” in apps such as Chrome, Slack, and VS Code. Shortcuts must include ⌘ or ⌃.")
            }
            Section("In the history panel") {
                LabeledContent("Move selection", value: "↑ ↓")
                LabeledContent(app.settings.pasteOnSelect ? "Paste selected item" : "Copy selected item", value: "↩")
                LabeledContent("Copy without pasting", value: "⇧↩")
                LabeledContent("Choose item 1–9", value: "⌘1 … ⌘9")
                LabeledContent("Pin or unpin", value: "⌘P")
                LabeledContent("Delete", value: "⌘⌫")
                LabeledContent("Close", value: "esc")
            }
        }
        .formStyle(.grouped)
    }

    private func apply(_ shortcut: Shortcut) {
        guard shortcut.isValid else {
            error = "Use at least ⌘ or ⌃ in the shortcut."
            app.registerHotKey(app.settings.shortcut)
            return
        }
        if app.registerHotKey(shortcut) != nil {
            error = "\(shortcut.displayString) is already used by another app. Choose a different shortcut."
            app.registerHotKey(app.settings.shortcut)
        } else {
            app.settings.shortcut = shortcut
            error = nil
        }
    }
}

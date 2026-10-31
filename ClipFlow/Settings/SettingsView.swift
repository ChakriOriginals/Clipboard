import SwiftUI

struct SettingsView: View {
    let app: AppController

    var body: some View {
        TabView {
            GeneralTab(app: app).tabItem { Label("General", systemImage: "gearshape") }
            ShortcutsTab(app: app).tabItem { Label("Shortcuts", systemImage: "keyboard") }
            HistoryTab(app: app).tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
            PrivacyTab(app: app).tabItem { Label("Privacy", systemImage: "hand.raised") }
            AppearanceTab(app: app).tabItem { Label("Appearance", systemImage: "paintbrush") }
            SyncTab().tabItem { Label("Sync", systemImage: "arrow.triangle.2.circlepath") }
            AboutTab(app: app).tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 560, height: 440)
    }
}

/// A status line with a trailing action, used for permission rows.
struct StatusRow: View {
    let title: String
    let ok: Bool
    let okText: String
    let problemText: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        LabeledContent(title) {
            HStack {
                Label(ok ? okText : problemText, systemImage: ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .foregroundStyle(ok ? .green : .orange)
                if let actionTitle, let action, !ok {
                    Button(actionTitle, action: action)
                }
            }
        }
    }
}

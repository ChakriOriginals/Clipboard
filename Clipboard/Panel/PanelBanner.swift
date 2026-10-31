import AppKit
import SwiftUI

/// One-line notices for states that stop Clipboard from working normally.
struct PanelBanner: View {
    let app: AppController
    let accessState: PasteAccessState

    var body: some View {
        if let notice {
            HStack(spacing: 8) {
                Image(systemName: notice.icon)
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
                Text(notice.message)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button(notice.actionTitle, action: notice.action)
                    .controlSize(.small)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.orange.opacity(0.12))
            .accessibilityElement(children: .combine)
        }
    }

    private struct Notice {
        let icon: String
        let message: String
        let actionTitle: String
        let action: () -> Void
    }

    private var notice: Notice? {
        switch app.model.status {
        case .locked:
            return Notice(icon: "lock", message: "History is locked because Keychain access was denied.",
                          actionTitle: "Retry") { Task { await app.model.load() } }
        case .recovered(let url):
            return Notice(icon: "exclamationmark.triangle",
                          message: "Previous history couldn’t be opened with this Mac’s key and was set aside. Clear Everything deletes it.",
                          actionTitle: "Show File") {
                NSWorkspace.shared.activateFileViewerSelecting([url])
                app.model.acknowledgeRecovery()
            }
        case .newerVersion:
            return Notice(icon: "arrow.up.circle", message: "This history was saved by a newer version of Clipboard. Update Clipboard to use it; nothing has been changed.",
                          actionTitle: "Show File") {
                NSWorkspace.shared.activateFileViewerSelecting([app.dataDirectory])
            }
        case .failed:
            return Notice(icon: "exclamationmark.triangle", message: "History couldn’t be opened.",
                          actionTitle: "Retry") { Task { await app.model.load() } }
        case .ready, .loading:
            break
        }
        if accessState == .needsAlwaysAllow || accessState == .denied {
            return Notice(icon: "hand.raised", message: "macOS is blocking clipboard access. Allow paste access for Clipboard in System Settings.",
                          actionTitle: "Open Settings") { AppController.openSystemSettings("Privacy_Paste") }
        }
        if app.settings.isPaused {
            return Notice(icon: "pause.circle", message: "Monitoring is paused. New copies aren’t saved.",
                          actionTitle: "Resume") { app.setPaused(false) }
        }
        return nil
    }
}

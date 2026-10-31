import AppKit
import SwiftUI

/// One quiet line for states that stop Clipboard from working normally. Color marks the symbol only.
struct PanelBanner: View {
    let model: HistoryModel
    let settings: SettingsStore
    let accessState: PasteAccessState
    let dataDirectory: URL
    let actions: PanelActions

    var body: some View {
        if let notice {
            HStack(spacing: 10) {
                Image(systemName: notice.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
                Text(notice.message)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button(notice.actionTitle, action: notice.action)
                    .controlSize(.small)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: Theme.rowRadius, style: .continuous))
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
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
        switch model.status {
        case .locked:
            return Notice(icon: "lock", message: "History is locked because Keychain access was denied.",
                          actionTitle: "Try Again") { Task { await model.load() } }
        case .recovered(let url):
            return Notice(icon: "exclamationmark.triangle",
                          message: "Earlier history couldn’t be read (damaged, or encrypted with a different key) and was set aside. Clear Everything deletes it.",
                          actionTitle: "Show File") {
                actions.revealInFinder(url)
                model.acknowledgeRecovery()
            }
        case .newerVersion:
            return Notice(icon: "arrow.up.circle",
                          message: "This history was saved by a newer version of Clipboard. Nothing has been changed.",
                          actionTitle: "Show Folder") { actions.revealInFinder(dataDirectory) }
        case .failed:
            return Notice(icon: "exclamationmark.triangle", message: "History couldn’t be opened.",
                          actionTitle: "Try Again") { Task { await model.load() } }
        case .ready, .loading:
            break
        }
        if accessState == .needsAlwaysAllow || accessState == .denied {
            return Notice(icon: "hand.raised", message: "macOS is blocking clipboard access. Allow Paste access for Clipboard.",
                          actionTitle: "Open Settings") { actions.openPrivacySettings("Privacy_Paste") }
        }
        if settings.isPaused {
            return Notice(icon: "pause.circle", message: "Monitoring is paused. New copies aren’t saved.",
                          actionTitle: "Resume") { actions.setPaused(false) }
        }
        return nil
    }
}

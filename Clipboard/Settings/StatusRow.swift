import SwiftUI

/// A permission or status line with a fix-it button when something needs attention.
struct StatusRow: View {
    let title: String
    let ok: Bool
    let okText: String
    let problemText: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 8) {
                Label(ok ? okText : problemText, systemImage: ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(ok ? Color.secondary : Color.orange)
                    .symbolRenderingMode(.hierarchical)
                if let actionTitle, let action, !ok {
                    Button(actionTitle, action: action).controlSize(.small)
                }
            }
        }
    }
}

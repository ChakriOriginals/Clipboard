import SwiftUI

/// Design tokens: one source for sizes, radii and motion so every surface agrees (4-pt grid).
enum Theme {
    static let panelSize = CGSize(width: 760, height: 480)
    static let listWidth: CGFloat = 300
    static let panelRadius: CGFloat = 16
    static let rowRadius: CGFloat = 8
    static let tileRadius: CGFloat = 6

    /// Critically damped (no overshoot); Reduce Motion gets a short ease instead of movement.
    static func motion(reduceMotion: Bool, response: Double = 0.2) -> Animation {
        reduceMotion ? .easeOut(duration: 0.1) : .spring(response: response, dampingFraction: 1)
    }

    static let selectionFill = Color.accentColor.opacity(0.18)
    static let hoverFill = Color.primary.opacity(0.06)
}

/// A keyboard key, drawn like the glyphs in macOS menus.
struct KeyCap: View {
    let key: String

    var body: some View {
        Text(key)
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
            .frame(minWidth: 18, minHeight: 16)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// A key and what it does, for the panel footer.
struct KeyHint: View {
    let key: String
    let label: String

    var body: some View {
        HStack(spacing: 5) {
            KeyCap(key: key)
            Text(label).font(.subheadline).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(key)")
    }
}

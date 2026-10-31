import AppKit

/// Whether ClipFlow may read the general pasteboard in the background (macOS 15.4+ pasteboard privacy).
enum PasteAccessState: Equatable, Sendable {
    /// Always Allow, or a macOS without pasteboard privacy.
    case allowed
    /// Never prompted yet: the first read may show the system alert.
    case mayPrompt
    /// macOS would prompt on every read; the user must choose Always Allow in System Settings.
    case needsAlwaysAllow
    case denied

    /// Reading in `.needsAlwaysAllow` would show an alert on every copy, so we don't.
    var mayReadAutomatically: Bool { self == .allowed || self == .mayPrompt }

    @available(macOS 15.4, *)
    static func from(_ behavior: NSPasteboard.AccessBehavior) -> PasteAccessState {
        switch behavior {
        case .alwaysAllow: .allowed
        case .default: .mayPrompt
        case .ask: .needsAlwaysAllow
        case .alwaysDeny: .denied
        @unknown default: .mayPrompt
        }
    }

    static func current(for pasteboard: NSPasteboard) -> PasteAccessState {
        guard #available(macOS 15.4, *) else { return .allowed }
        return from(pasteboard.accessBehavior)
    }
}

import AppKit
import Carbon.HIToolbox

enum PanelCommand: Equatable {
    case moveUp, moveDown, select, copyOnly, selectIndex(Int), togglePin, delete, close
}

/// Maps key presses in the panel to commands before the search field sees them.
/// Anything not listed here (typing, plain ⌫, ⌘A, ⌘C…) is left to the text field.
enum KeyRouter {
    static func command(keyCode: UInt16, modifiers: NSEvent.ModifierFlags,
                        charactersIgnoringModifiers: String?) -> PanelCommand? {
        let mods = modifiers.intersection([.command, .shift, .option, .control])
        switch Int(keyCode) {
        case kVK_UpArrow: return .moveUp
        case kVK_DownArrow: return .moveDown
        case kVK_Return, kVK_ANSI_KeypadEnter: return mods.contains(.shift) ? .copyOnly : .select
        case kVK_Escape: return .close
        case kVK_Delete where mods == .command: return .delete
        default: break
        }
        guard mods == .command, let chars = charactersIgnoringModifiers?.lowercased() else { return nil }
        if chars == "p" { return .togglePin }
        if let digit = Int(chars), (1...9).contains(digit) { return .selectIndex(digit - 1) }
        return nil
    }
}

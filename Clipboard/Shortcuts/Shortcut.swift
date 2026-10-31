import AppKit
import Carbon.HIToolbox

/// A global keyboard shortcut: virtual key code plus ⌘/⌃/⌥/⇧ modifiers.
struct Shortcut: Codable, Equatable, Sendable {
    let keyCode: UInt32
    private let modifiers: UInt

    static let relevantModifiers: NSEvent.ModifierFlags = [.command, .control, .option, .shift]
    static let `default` = Shortcut(keyCode: UInt32(kVK_ANSI_V), modifiers: [.command, .shift])

    init(keyCode: UInt32, modifiers: NSEvent.ModifierFlags) {
        self.keyCode = keyCode
        self.modifiers = modifiers.intersection(Self.relevantModifiers).rawValue
    }

    var modifierFlags: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifiers) }

    /// macOS 15+ rejects hotkeys whose only modifiers are ⌥ or ⌥⇧; require ⌘ or ⌃.
    var isValid: Bool {
        guard !modifierFlags.isDisjoint(with: [.command, .control]) else { return false }
        // ⌘ plus a standard editing/app key would break that command everywhere (and ⌘V would
        // swallow Clipboard's own synthetic paste).
        return !(modifierFlags == .command && Self.reservedCommandKeys.contains(Int(keyCode)))
    }

    private static let reservedCommandKeys: Set<Int> = [kVK_ANSI_V, kVK_ANSI_C, kVK_ANSI_X, kVK_ANSI_Z,
                                                         kVK_ANSI_A, kVK_ANSI_Q, kVK_ANSI_W]

    var carbonModifiers: UInt32 {
        var result: UInt32 = 0
        if modifierFlags.contains(.command) { result |= UInt32(cmdKey) }
        if modifierFlags.contains(.shift) { result |= UInt32(shiftKey) }
        if modifierFlags.contains(.option) { result |= UInt32(optionKey) }
        if modifierFlags.contains(.control) { result |= UInt32(controlKey) }
        return result
    }

    /// The key as a menu key equivalent (letters and digits only), so menus can show the shortcut.
    var menuKeyEquivalent: String? {
        guard let name = Self.keyNames[Int(keyCode)], name.count == 1, name.first!.isLetter || name.first!.isNumber else { return nil }
        return name.lowercased()
    }

    var displayString: String {
        var s = ""
        if modifierFlags.contains(.control) { s += "⌃" }
        if modifierFlags.contains(.option) { s += "⌥" }
        if modifierFlags.contains(.shift) { s += "⇧" }
        if modifierFlags.contains(.command) { s += "⌘" }
        return s + (Self.keyNames[Int(keyCode)] ?? "Key \(keyCode)")
    }

    /// US-layout labels for display.
    private static let keyNames: [Int: String] = {
        var names: [Int: String] = [
            kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_Escape: "⎋",
            kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_DownArrow: "↓", kVK_UpArrow: "↑",
            kVK_ANSI_Equal: "=", kVK_ANSI_Minus: "-", kVK_ANSI_LeftBracket: "[", kVK_ANSI_RightBracket: "]",
            kVK_ANSI_Quote: "'", kVK_ANSI_Semicolon: ";", kVK_ANSI_Backslash: "\\", kVK_ANSI_Comma: ",",
            kVK_ANSI_Slash: "/", kVK_ANSI_Period: ".", kVK_ANSI_Grave: "`",
        ]
        let letters: [(Int, String)] = [
            (kVK_ANSI_A, "A"), (kVK_ANSI_B, "B"), (kVK_ANSI_C, "C"), (kVK_ANSI_D, "D"), (kVK_ANSI_E, "E"),
            (kVK_ANSI_F, "F"), (kVK_ANSI_G, "G"), (kVK_ANSI_H, "H"), (kVK_ANSI_I, "I"), (kVK_ANSI_J, "J"),
            (kVK_ANSI_K, "K"), (kVK_ANSI_L, "L"), (kVK_ANSI_M, "M"), (kVK_ANSI_N, "N"), (kVK_ANSI_O, "O"),
            (kVK_ANSI_P, "P"), (kVK_ANSI_Q, "Q"), (kVK_ANSI_R, "R"), (kVK_ANSI_S, "S"), (kVK_ANSI_T, "T"),
            (kVK_ANSI_U, "U"), (kVK_ANSI_V, "V"), (kVK_ANSI_W, "W"), (kVK_ANSI_X, "X"), (kVK_ANSI_Y, "Y"),
            (kVK_ANSI_Z, "Z"), (kVK_ANSI_0, "0"), (kVK_ANSI_1, "1"), (kVK_ANSI_2, "2"), (kVK_ANSI_3, "3"),
            (kVK_ANSI_4, "4"), (kVK_ANSI_5, "5"), (kVK_ANSI_6, "6"), (kVK_ANSI_7, "7"), (kVK_ANSI_8, "8"),
            (kVK_ANSI_9, "9"),
        ]
        for (code, name) in letters { names[code] = name }
        let functionKeys = [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
                            kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20]
        for (index, code) in functionKeys.enumerated() { names[code] = "F\(index + 1)" }
        return names
    }()
}

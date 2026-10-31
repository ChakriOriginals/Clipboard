import ApplicationServices
import Carbon.HIToolbox
import CoreGraphics

/// Sends ⌘V to the frontmost app. Requires Accessibility permission; otherwise does nothing.
@MainActor
struct AutoPaster {
    var isTrusted: () -> Bool = { AXIsProcessTrusted() }
    var post: (CGKeyCode) -> Void = AutoPaster.postCommand

    /// Returns false (and posts nothing) when Accessibility isn't granted.
    func paste() -> Bool {
        guard isTrusted() else { return false }
        post(Self.keyCodeForV())
        return true
    }

    /// Pastes only if the pasteboard still holds what ClipFlow wrote, so another app can't swap
    /// its own content in between the restore and the synthetic ⌘V.
    func paste(ifChangeCountIs expected: Int, current: Int) -> Bool {
        guard expected == current, isTrusted() else { return false }
        post(Self.keyCodeForV())
        return true
    }

    /// Shows the system Accessibility prompt (once per signature).
    static func requestTrust() {
        // "AXTrustedCheckOptionPrompt" is the value of kAXTrustedCheckOptionPrompt (a C global Swift 6 treats as unsafe).
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    nonisolated static func postCommand(_ keyCode: CGKeyCode) {
        let source = CGEventSource(stateID: .combinedSessionState)
        for keyDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: keyDown)
            event?.flags = .maskCommand
            event?.post(tap: .cghidEventTap)
        }
    }

    /// The key that types "v" in the current layout (⌘V follows the layout, e.g. Dvorak); US fallback.
    static func keyCodeForV() -> CGKeyCode {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return CGKeyCode(kVK_ANSI_V) }
        let layoutData = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue() as Data
        return layoutData.withUnsafeBytes { buffer -> CGKeyCode in
            guard let layout = buffer.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return CGKeyCode(kVK_ANSI_V) }
            for code in 0..<128 {
                var deadKeys: UInt32 = 0
                var length = 0
                var chars = [UniChar](repeating: 0, count: 4)
                let status = UCKeyTranslate(layout, UInt16(code), UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                                            OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeys, 4, &length, &chars)
                if status == noErr, length == 1, chars[0] == UniChar(("v" as Unicode.Scalar).value) {
                    return CGKeyCode(code)
                }
            }
            return CGKeyCode(kVK_ANSI_V)
        }
    }
}

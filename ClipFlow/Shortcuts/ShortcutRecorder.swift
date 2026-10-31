import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Click, then press a key combination. Escape cancels.
struct ShortcutRecorder: View {
    let shortcut: Shortcut
    let onRecordingChange: (Bool) -> Void
    let onRecord: (Shortcut) -> Void
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Button(recording ? "Type shortcut…" : shortcut.displayString) {
            recording ? stop() : start()
        }
        .frame(minWidth: 120)
        .accessibilityLabel(recording ? "Recording shortcut. Press a key combination, or Escape to cancel."
                                      : "Shortcut \(shortcut.displayString). Click to change.")
        .onDisappear(perform: stop)
    }

    private func start() {
        recording = true
        onRecordingChange(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == UInt16(kVK_Escape), event.modifierFlags.intersection(Shortcut.relevantModifiers).isEmpty {
                stop()
                return nil
            }
            let recorded = Shortcut(keyCode: UInt32(event.keyCode), modifiers: event.modifierFlags)
            stop(registerPrevious: false)
            onRecord(recorded)
            return nil
        }
    }

    private func stop() {
        stop(registerPrevious: true)
    }

    private func stop(registerPrevious: Bool) {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if recording {
            recording = false
            if registerPrevious { onRecordingChange(false) }
        }
    }
}

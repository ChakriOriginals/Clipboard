import AppKit
import ApplicationServices
import SwiftUI

struct OnboardingView: View {
    let app: AppController
    let onDone: () -> Void
    @State private var trusted = AXIsProcessTrusted()
    @State private var access = PasteAccessState.current(for: .general)

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 48, height: 48)
                    .accessibilityHidden(true)
                VStack(alignment: .leading) {
                    Text("Welcome to ClipFlow").font(.title2.weight(.semibold))
                    Text("Press \(app.settings.shortcut.displayString) anytime to see what you’ve copied.")
                        .foregroundStyle(.secondary)
                }
            }
            step(number: 1, title: "Allow clipboard access",
                 detail: "macOS asks before apps read the clipboard. When it asks about ClipFlow, choose “Always Allow”, or turn it on in System Settings › Privacy & Security › Paste.",
                 done: access == .allowed, button: "Open Settings") {
                AppController.openSystemSettings("Privacy_Paste")
            }
            step(number: 2, title: "Paste automatically (optional)",
                 detail: "To paste straight into the app you were using, allow ClipFlow in Accessibility. Without it, ClipFlow copies the item and you press ⌘V.",
                 done: trusted, button: "Allow…") {
                AutoPaster.requestTrust()
            }
            Text("Your history is encrypted and stays on this Mac. Nothing is sent anywhere.")
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Get Started", action: onDone).keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 480)
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            trusted = AXIsProcessTrusted()
            access = PasteAccessState.current(for: .general)
        }
    }

    private func step(number: Int, title: String, detail: String, done: Bool, button: String,
                      action: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: done ? "checkmark.circle.fill" : "\(number).circle")
                .font(.title2)
                .foregroundStyle(done ? .green : .accentColor)
                .accessibilityLabel(done ? "Done" : "Step \(number)")
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if !done { Button(button, action: action).padding(.top, 2) }
            }
        }
    }
}

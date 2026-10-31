import AppKit
import ApplicationServices
import SwiftUI

struct OnboardingView: View {
    let app: AppController
    let onDone: () -> Void
    @State private var trusted = AXIsProcessTrusted()
    @State private var access = PasteAccessState.current(for: .general)

    var body: some View {
        VStack(spacing: 0) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 72, height: 72)
                .accessibilityHidden(true)
            Text("Welcome to Clipboard")
                .font(.system(size: 22, weight: .semibold))
                .padding(.top, 10)
            HStack(spacing: 6) {
                Text("Press")
                KeyCap(key: app.settings.shortcut.displayString)
                Text("anytime to see everything you’ve copied.")
            }
            .foregroundStyle(.secondary)
            .padding(.top, 6)

            VStack(spacing: 0) {
                step(symbol: "doc.on.clipboard", title: "Allow clipboard access",
                     detail: "When macOS asks, choose “Always Allow”. You can change it in System Settings › Privacy & Security › Paste.",
                     done: access == .allowed, button: "Open Settings") {
                    AppController.openSystemSettings("Privacy_Paste")
                }
                Divider().padding(.leading, 52)
                step(symbol: "keyboard", title: "Paste automatically — optional",
                     detail: "Allow Accessibility so choosing an item pastes it where you were typing. Without it, Clipboard copies the item and you press ⌘V.",
                     done: trusted, button: "Allow…") {
                    AutoPaster.requestTrust()
                }
            }
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .padding(.top, 20)

            Label("Your history is encrypted and never leaves this Mac.", systemImage: "lock.fill")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.top, 16)

            Button("Get Started", action: onDone)
                .keyboardShortcut(.defaultAction)
                .controlSize(.large)
                .padding(.top, 20)
        }
        .padding(28)
        .frame(width: 520)
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            trusted = AXIsProcessTrusted()
            access = PasteAccessState.current(for: .general)
        }
    }

    private func step(symbol: String, title: String, detail: String, done: Bool, button: String,
                      action: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: done ? "checkmark.circle.fill" : symbol)
                .font(.system(size: 20))
                .foregroundStyle(done ? Color.green : Color.accentColor)
                .frame(width: 28)
                .accessibilityLabel(done ? "Done" : "")
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if !done { Button(button, action: action).controlSize(.small).padding(.top, 4) }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
    }
}

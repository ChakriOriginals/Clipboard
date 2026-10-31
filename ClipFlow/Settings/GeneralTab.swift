import ApplicationServices
import ServiceManagement
import SwiftUI

struct GeneralTab: View {
    let app: AppController
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?
    @State private var trusted = AXIsProcessTrusted()

    var body: some View {
        @Bindable var settings = app.settings
        Form {
            Section {
                Toggle("Launch ClipFlow at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
            }
            Section {
                Toggle("Paste automatically when choosing an item", isOn: $settings.pasteOnSelect)
                StatusRow(title: "Accessibility", ok: trusted, okText: "Allowed", problemText: "Not allowed",
                          actionTitle: "Allow…") {
                    AutoPaster.requestTrust()
                    AppController.openSystemSettings("Privacy_Accessibility")
                }
            } footer: {
                Text("Automatic paste sends ⌘V to the app you were using, which requires Accessibility permission. Without it, ClipFlow still copies the item so you can paste it yourself.")
            }
            Section {
                StatusRow(title: "Clipboard access", ok: app.accessState.mayReadAutomatically,
                          okText: app.accessState == .allowed ? "Always allowed" : "Will ask once",
                          problemText: "Blocked", actionTitle: "Open Settings…") {
                    AppController.openSystemSettings("Privacy_Paste")
                }
            } footer: {
                Text("macOS asks before apps read the clipboard. Choose “Always Allow” for ClipFlow so it can keep your history.")
            }
        }
        .formStyle(.grouped)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            trusted = AXIsProcessTrusted()
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = "Couldn’t change the login item. Move ClipFlow to /Applications and try again."
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

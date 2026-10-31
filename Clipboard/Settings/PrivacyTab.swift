import AppKit
import ClipboardCore
import SwiftUI

struct PrivacyTab: View {
    let app: AppController
    @State private var selection: String?

    var body: some View {
        @Bindable var settings = app.settings
        Form {
            Section {
                Toggle("Pause monitoring", isOn: Binding(get: { settings.isPaused }, set: { app.setPaused($0) }))
            }
            Section {
                Picker("Possible secrets", selection: $settings.sensitiveHandling) {
                    Text("Save, hide preview, remove automatically").tag(SensitiveHandling.maskAndExpire)
                    Text("Don’t save").tag(SensitiveHandling.dontSave)
                }
                if settings.sensitiveHandling == .maskAndExpire {
                    Picker("Remove after", selection: $settings.sensitiveExpiryMinutes) {
                        Text("10 minutes").tag(Int?.some(10))
                        Text("1 hour").tag(Int?.some(60))
                        Text("1 day").tag(Int?.some(1_440))
                        Text("Never").tag(Int?.none)
                    }
                    .onChange(of: settings.sensitiveExpiryMinutes) { Task { await app.model.applyRetention() } }
                }
            } footer: {
                Text("Clipboard never saves items that password managers mark as concealed. It also looks for things like API keys, private keys and passwords — a best-effort check, so delete anything it misses.")
            }
            Section {
                List(selection: $selection) {
                    ForEach(settings.excludedBundleIDs, id: \.self) { bundleID in
                        Text(Self.appName(for: bundleID)).tag(bundleID)
                    }
                }
                .frame(minHeight: 110)
                HStack {
                    Button("Add App…", action: addApp)
                    Button("Remove") {
                        settings.excludedBundleIDs.removeAll { $0 == selection }
                        selection = nil
                    }
                    .disabled(selection == nil)
                }
            } header: {
                Text("Ignore copies made in these apps")
            } footer: {
                Text("Based on the app in front when the copy happens, so it’s best-effort.")
            }
        }
        .formStyle(.grouped)
    }

    private func addApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        let ids = panel.urls.compactMap { Bundle(url: $0)?.bundleIdentifier }
        for id in ids where !app.settings.excludedBundleIDs.contains(id) {
            app.settings.excludedBundleIDs.append(id)
        }
    }

    private static let knownNames = ["com.apple.keychainaccess": "Keychain Access", "com.apple.Passwords": "Passwords",
                                     "com.1password.1password": "1Password", "com.bitwarden.desktop": "Bitwarden"]

    static func appName(for bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return knownNames[bundleID] ?? bundleID
        }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }
}

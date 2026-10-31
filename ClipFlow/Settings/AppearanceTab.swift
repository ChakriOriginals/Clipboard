import SwiftUI

struct AppearanceTab: View {
    let app: AppController

    var body: some View {
        @Bindable var settings = app.settings
        Form {
            Section {
                Picker("Open panel", selection: $settings.panelPosition) {
                    Text("Centered on screen").tag(PanelPosition.center)
                    Text("Near the pointer").tag(PanelPosition.nearMouse)
                }
                Toggle("Show image thumbnails", isOn: $settings.showThumbnails)
            } footer: {
                Text("ClipFlow follows your system appearance and accessibility settings, including Reduce Motion, Reduce Transparency and Increase Contrast.")
            }
        }
        .formStyle(.grouped)
    }
}

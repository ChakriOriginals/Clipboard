import AppKit
import SwiftUI

struct AboutTab: View {
    let app: AppController

    private var version: String {
        let info = Bundle.main.infoDictionary
        return "\(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?"))"
    }

    var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 72, height: 72)
                .accessibilityHidden(true)
            Text("ClipFlow").font(.title2.weight(.semibold))
            Text("Version \(version)").foregroundStyle(.secondary)
            Text("Clipboard history for your Mac. Local, encrypted, no account, no tracking.")
                .multilineTextAlignment(.center)
            Text("Open source under the MIT License.").font(.caption).foregroundStyle(.secondary)
            Button("Show Data Folder in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([app.dataDirectory])
            }
            .padding(.top, 6)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

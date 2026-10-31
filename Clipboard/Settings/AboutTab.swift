import AppKit
import SwiftUI

struct AboutTab: View {
    let app: AppController

    private var version: String {
        let info = Bundle.main.infoDictionary
        return "Version \(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?"))"
    }

    var body: some View {
        VStack(spacing: 0) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
                .accessibilityHidden(true)
            Text("Clipboard")
                .font(.system(size: 22, weight: .semibold))
                .padding(.top, 8)
            Text(version)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.top, 2)
            Text("Everything you copy, one keystroke away.\nLocal, encrypted, no account, no tracking.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.top, 14)
            HStack(spacing: 10) {
                Button("Show Data Folder") { NSWorkspace.shared.activateFileViewerSelecting([app.dataDirectory]) }
            }
            .padding(.top, 18)
            Text("Open source under the MIT License.")
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .padding(.top, 18)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }
}

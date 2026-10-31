import SwiftUI

struct SyncTab: View {
    var body: some View {
        Form {
            Section {
                Label("Your history stays on this Mac.", systemImage: "lock.laptopcomputer")
                    .font(.headline)
                Text("Syncing between your Mac, iPhone and iPad is planned for a future version. It will be off by default, encrypted before it leaves your device, and won’t need a ClipFlow account.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

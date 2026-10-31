import SwiftUI

struct HistoryTab: View {
    let app: AppController

    var body: some View {
        @Bindable var settings = app.settings
        Form {
            Section {
                Picker("Keep items for", selection: $settings.retentionDays) {
                    Text("1 day").tag(Int?.some(1))
                    Text("7 days").tag(Int?.some(7))
                    Text("30 days").tag(Int?.some(30))
                    Text("90 days").tag(Int?.some(90))
                    Text("Forever").tag(Int?.none)
                }
                Picker("Maximum items", selection: $settings.maxItems) {
                    ForEach([100, 500, 1_000, 5_000, 10_000], id: \.self) { Text($0.formatted()).tag($0) }
                }
            } footer: {
                Text("Pinned items are never removed automatically.")
            }
            .onChange(of: settings.retentionDays) { Task { await app.model.applyRetention() } }
            .onChange(of: settings.maxItems) { Task { await app.model.applyRetention() } }

            Section("Capture") {
                Toggle("Images", isOn: $settings.captureImages)
                Toggle("File references", isOn: $settings.captureFiles)
            }

            Section {
                LabeledContent("Items in history", value: app.model.items.count.formatted())
                HStack {
                    Spacer()
                    Button("Clear History…") { app.confirmClearHistory() }
                }
            }
        }
        .formStyle(.grouped)
    }
}

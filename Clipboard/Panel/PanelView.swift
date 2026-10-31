import ClipboardCore
import SwiftUI

struct PanelView: View {
    let app: AppController
    let focus: PanelFocus
    let accessState: PasteAccessState
    @FocusState private var searchFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var model: HistoryModel { app.model }

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            searchBar(text: $model.query.text)
            filterBar
            Divider()
            PanelBanner(app: app, accessState: accessState)
            if model.results.isEmpty {
                emptyState
            } else {
                list
            }
            Divider()
            footer
        }
        .frame(minWidth: 420, minHeight: 300)
        .onChange(of: focus.token, initial: true) { searchFocused = true }
    }

    private func searchBar(text: Binding<String>) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("Search clipboard history", text: text)
                .textFieldStyle(.plain)
                .font(.title3)
                .focused($searchFocused)
                .accessibilityLabel("Search clipboard history")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var filterBar: some View {
        @Bindable var model = model
        return HStack(spacing: 6) {
            ForEach(KindFilter.allCases, id: \.self) { kind in
                FilterChip(title: kind.title, systemImage: kind.systemImage, isOn: model.query.kind == kind) {
                    model.query.kind = kind
                }
            }
            Spacer(minLength: 8)
            Picker("Date", selection: $model.query.date) {
                ForEach(DateFilter.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
            .accessibilityLabel("Date filter")
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    section("Pinned", model.pinnedResults, offset: 0)
                    section("Recent", model.recentResults, offset: model.pinnedResults.count)
                }
                .padding(8)
            }
            .onChange(of: model.selectedID) { _, id in
                guard let id else { return }
                if reduceMotion {
                    proxy.scrollTo(id)
                } else {
                    withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(id) }
                }
            }
        }
    }

    @ViewBuilder
    private func section(_ title: String, _ items: [ClipItem], offset: Int) -> some View {
        if !items.isEmpty {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.top, 6)
                .accessibilityAddTraits(.isHeader)
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                ClipRowView(app: app, item: item, index: offset + index, isSelected: item.id == model.selectedID)
                    .id(item.id)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: model.items.isEmpty ? "clipboard" : "magnifyingglass")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(.secondary)
            Text(model.items.isEmpty ? "Nothing copied yet" : "No matches")
                .font(.headline)
            Text(model.items.isEmpty ? "Copy something in any app and it will appear here."
                                     : "Try a different search or filter.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .accessibilityElement(children: .combine)
    }

    private var footer: some View {
        HStack(spacing: 14) {
            hint("↩", app.settings.pasteOnSelect ? "Paste" : "Copy")
            hint("⇧↩", "Copy")
            hint("⌘P", "Pin")
            hint("⌘⌫", "Delete")
            Spacer()
            hint("esc", "Close")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .accessibilityElement(children: .combine)
    }

    private func hint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(key).fontWeight(.semibold)
            Text(label)
        }
    }
}

private struct FilterChip: View {
    let title: String
    let systemImage: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .labelStyle(.titleAndIcon)
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(isOn ? Color.accentColor.opacity(0.2) : Color.clear, in: Capsule())
                .overlay(Capsule().strokeBorder(isOn ? Color.accentColor : Color.secondary.opacity(0.35)))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

extension KindFilter {
    var title: String {
        switch self {
        case .all: "All"
        case .pinned: "Pinned"
        case .text: "Text"
        case .urls: "Links"
        case .code: "Code"
        case .images: "Images"
        case .files: "Files"
        }
    }

    var systemImage: String {
        switch self {
        case .all: "square.stack"
        case .pinned: "pin"
        case .text: "text.alignleft"
        case .urls: "link"
        case .code: "chevron.left.forwardslash.chevron.right"
        case .images: "photo"
        case .files: "doc"
        }
    }
}

extension DateFilter {
    var title: String {
        switch self {
        case .any: "Any time"
        case .today: "Today"
        case .last7Days: "Last 7 days"
        case .last30Days: "Last 30 days"
        }
    }
}

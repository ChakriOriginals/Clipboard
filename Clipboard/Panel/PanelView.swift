import ClipboardCore
import SwiftUI

/// What the panel can ask the app to do.
struct PanelActions {
    var choose: @MainActor (UUID, Bool) -> Void
    var setPaused: @MainActor (Bool) -> Void
    var revealInFinder: @MainActor (URL) -> Void
    var openPrivacySettings: @MainActor (String) -> Void
}

/// The history panel: search and filters on top, list on the left, exact preview on the right.
struct PanelView: View {
    let model: HistoryModel
    let settings: SettingsStore
    let focus: PanelFocus
    let accessState: PasteAccessState
    let dataDirectory: URL
    let actions: PanelActions
    @FocusState private var searchFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var selectionSpace

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            header(text: $model.query.text, kind: $model.query.kind, date: $model.query.date)
            PanelBanner(model: model, settings: settings, accessState: accessState, dataDirectory: dataDirectory, actions: actions)
            Divider()
            if model.results.isEmpty {
                emptyState
            } else {
                HStack(spacing: 0) {
                    listColumn
                        .frame(width: Theme.listWidth)
                    Divider()
                    PreviewPane(model: model, settings: settings, item: model.selectedItem)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            Divider()
            footer
        }
        .frame(width: Theme.panelSize.width, height: Theme.panelSize.height)
        .onChange(of: focus.token, initial: true) { searchFocused = true }
    }

    // MARK: Header

    private func header(text: Binding<String>, kind: Binding<KindFilter>, date: Binding<DateFilter>) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                TextField("Search Clipboard", text: text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 17))
                    .focused($searchFocused)
                    .accessibilityLabel("Search clipboard history")
                if !text.wrappedValue.isEmpty {
                    Button { text.wrappedValue = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            HStack(spacing: 4) {
                ForEach(KindFilter.allCases, id: \.self) { filter in
                    FilterChip(title: filter.title, isOn: kind.wrappedValue == filter) { kind.wrappedValue = filter }
                }
                Spacer(minLength: 8)
                Picker("Date", selection: date) {
                    ForEach(DateFilter.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .menuStyle(.borderlessButton)
                .controlSize(.small)
                .fixedSize()
                .accessibilityLabel("Date filter")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    // MARK: List

    private var emptyState: some View {
        ContentUnavailableView {
            Label(model.items.isEmpty ? "Nothing Copied Yet" : "No Matches",
                  systemImage: model.items.isEmpty ? "clipboard" : "magnifyingglass")
        } description: {
            Text(model.items.isEmpty ? "Copy something in any app and it appears here."
                                     : "Try a different search or filter.")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var listColumn: some View {
        ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 1) {
                            section("Pinned", model.pinnedResults, offset: 0)
                            section("Recent", model.recentResults, offset: model.pinnedResults.count)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .animation(reduceMotion ? nil : Theme.motion(reduceMotion: false), value: model.selectedID)
                    }
                    .scrollIndicators(.automatic)
                    .onChange(of: model.selectedID) { _, id in
                        if let id { proxy.scrollTo(id) }
                    }
        }
    }

    @ViewBuilder
    private func section(_ title: String, _ items: [ClipItem], offset: Int) -> some View {
        if !items.isEmpty {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.top, offset == 0 ? 2 : 10)
                .padding(.bottom, 2)
                .accessibilityAddTraits(.isHeader)
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                ClipRowView(model: model, settings: settings, focus: focus, actions: actions, item: item,
                            index: offset + index, isSelected: item.id == model.selectedID, selectionSpace: selectionSpace)
                    .id(item.id)
            }
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 16) {
            KeyHint(key: "↩", label: settings.pasteOnSelect ? "Paste" : "Copy")
            KeyHint(key: "⇧↩", label: "Copy")
            KeyHint(key: "⌘P", label: "Pin")
            KeyHint(key: "⌘⌫", label: "Delete")
            Spacer()
            KeyHint(key: "esc", label: "Close")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
    }
}

/// A filter choice. The accent marks the active filter only; everything else stays monochrome.
private struct FilterChip: View {
    let title: String
    let isOn: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(isOn ? .semibold : .regular))
                .foregroundStyle(isOn ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
                .padding(.horizontal, 10)
                .frame(height: 24)
                .background(isOn ? Theme.selectionFill : (hovering ? Theme.hoverFill : .clear), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
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
}

extension DateFilter {
    var title: String {
        switch self {
        case .any: "Any Time"
        case .today: "Today"
        case .last7Days: "Last 7 Days"
        case .last30Days: "Last 30 Days"
        }
    }
}

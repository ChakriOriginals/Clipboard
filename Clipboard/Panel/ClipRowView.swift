import AppKit
import ClipboardCore
import SwiftUI

struct ClipRowView: View {
    let model: HistoryModel
    let settings: SettingsStore
    let focus: PanelFocus
    let actions: PanelActions
    let item: ClipItem
    let index: Int
    let isSelected: Bool
    let selectionSpace: Namespace.ID
    @State private var thumbnail: NSImage?
    @State private var hovering = false

    private static let relative: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    var body: some View {
        HStack(spacing: 10) {
            leading
            VStack(alignment: .leading, spacing: 1) {
                Text(item.displayPreview)
                    .font(item.kind == .code && !item.isSensitive ? .system(size: 12, design: .monospaced) : .body)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(item.isSensitive ? .secondary : .primary)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if item.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            if index < 9 {
                Text("⌘\(index + 1)")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: Theme.rowRadius, style: .continuous)
                    .fill(Theme.selectionFill)
                    .matchedGeometryEffect(id: "selection", in: selectionSpace)
            } else if hovering {
                RoundedRectangle(cornerRadius: Theme.rowRadius, style: .continuous).fill(Theme.hoverFill)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: Theme.rowRadius, style: .continuous))
        .onHover { inside in
            hovering = inside
            // The preview follows the pointer, but only once the mouse has actually moved, so
            // keyboard navigation isn't hijacked when the list scrolls under a resting cursor.
            if inside, focus.pointerActive { model.selectedID = item.id }
        }
        .onTapGesture { actions.choose(item.id, settings.pasteOnSelect) }
        .contextMenu { menu }
        .task(id: item.id) {
            if item.hasThumbnail, settings.showThumbnails, !item.isSensitive {
                thumbnail = await model.thumbnail(for: item.id)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(item.kind.label), \(item.displayPreview)")
        .accessibilityValue(subtitle + (item.isPinned ? ", pinned" : ""))
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
        .accessibilityAction { actions.choose(item.id, settings.pasteOnSelect) }
        .accessibilityAction(named: item.isPinned ? "Unpin" : "Pin") { Task { await model.togglePin(item.id) } }
        .accessibilityAction(named: "Delete") { Task { await model.delete(item.id) } }
    }

    @ViewBuilder
    private var leading: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Theme.tileRadius, style: .continuous).fill(.quaternary)
            if let thumbnail, !item.isSensitive {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 28, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.tileRadius, style: .continuous))
            } else {
                Image(systemName: item.isSensitive ? "lock.fill" : item.kind.systemImage)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 28, height: 28)
    }

    private var subtitle: String {
        let time = Self.relative.localizedString(for: item.lastCopiedAt, relativeTo: Date())
        guard let app = item.summary.sourceAppName else { return time }
        return "\(app) · \(time)"
    }

    @ViewBuilder
    private var menu: some View {
        Button("Paste") { actions.choose(item.id, true) }
        Button("Copy") { actions.choose(item.id, false) }
        if item.kind == .url, !item.isSensitive, !item.summary.previewText.hasSuffix("…"),
           let url = ContentClassifier.openableURL(item.summary.previewText) {
            Button("Open in Browser") { NSWorkspace.shared.open(url) }
        }
        Divider()
        Button(item.isPinned ? "Unpin" : "Pin") { Task { await model.togglePin(item.id) } }
        Button(item.isSensitive ? "Mark as Not Sensitive" : "Mark as Sensitive") {
            Task { await model.toggleSensitive(item.id) }
        }
        Divider()
        Button("Delete", role: .destructive) { Task { await model.delete(item.id) } }
    }
}

extension ClipKind {
    var systemImage: String {
        switch self {
        case .text: "text.alignleft"
        case .richText: "doc.richtext"
        case .url: "link"
        case .code: "chevron.left.forwardslash.chevron.right"
        case .image: "photo"
        case .file: "doc"
        }
    }

    var label: String {
        switch self {
        case .text: "Text"
        case .richText: "Rich Text"
        case .url: "Link"
        case .code: "Code"
        case .image: "Image"
        case .file: "File"
        }
    }
}

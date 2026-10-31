import AppKit
import ClipFlowCore
import SwiftUI

struct ClipRowView: View {
    let app: AppController
    let item: ClipItem
    let index: Int
    let isSelected: Bool
    @State private var thumbnail: NSImage?

    private static let relative: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    var body: some View {
        HStack(spacing: 10) {
            leading
                .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.summary.previewText)
                    .font(item.kind == .code ? .system(.body, design: .monospaced) : .body)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .italic(item.isSensitive)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(isSelected ? AnyShapeStyle(.white.opacity(0.85)) : AnyShapeStyle(.secondary))
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if item.isPinned {
                Image(systemName: "pin.fill")
                    .font(.caption)
                    .accessibilityHidden(true)
            }
            if index < 9 {
                Text("⌘\(index + 1)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(isSelected ? AnyShapeStyle(.white.opacity(0.85)) : AnyShapeStyle(.tertiary))
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
        .background(isSelected ? Color.accentColor : Color.clear, in: RoundedRectangle(cornerRadius: 7))
        .contentShape(Rectangle())
        .onTapGesture { app.choose(item.id, paste: app.settings.pasteOnSelect) }
        .contextMenu { menu }
        .task(id: item.id) {
            if item.hasThumbnail, app.settings.showThumbnails {
                thumbnail = await app.model.thumbnail(for: item.id)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(item.kind.label), \(item.summary.previewText)")
        .accessibilityValue(subtitle + (item.isPinned ? ", pinned" : ""))
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
        .accessibilityAction { app.choose(item.id, paste: app.settings.pasteOnSelect) }
        .accessibilityAction(named: item.isPinned ? "Unpin" : "Pin") { Task { await app.model.togglePin(item.id) } }
        .accessibilityAction(named: "Delete") { Task { await app.model.delete(item.id) } }
    }

    @ViewBuilder
    private var leading: some View {
        if let thumbnail {
            Image(nsImage: thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 36, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 5))
        } else {
            Image(systemName: item.isSensitive ? "lock.fill" : item.kind.systemImage)
                .font(.system(size: 16))
                .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
        }
    }

    private var subtitle: String {
        let time = Self.relative.localizedString(for: item.lastCopiedAt, relativeTo: Date())
        guard let app = item.summary.sourceAppName else { return time }
        return "\(app) · \(time)"
    }

    @ViewBuilder
    private var menu: some View {
        Button("Paste") { app.choose(item.id, paste: true) }
        Button("Copy") { app.choose(item.id, paste: false) }
        if item.kind == .url, !item.isSensitive, !item.summary.previewText.hasSuffix("…"), let url = ContentClassifier.openableURL(item.summary.previewText) {
            Button("Open in Browser") { NSWorkspace.shared.open(url) }
        }
        Divider()
        Button(item.isPinned ? "Unpin" : "Pin") { Task { await app.model.togglePin(item.id) } }
        Button(item.isSensitive ? "Mark as Not Sensitive" : "Mark as Sensitive") {
            Task { await app.model.toggleSensitive(item.id) }
        }
        Divider()
        Button("Delete", role: .destructive) { Task { await app.model.delete(item.id) } }
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
        case .richText: "Rich text"
        case .url: "Link"
        case .code: "Code"
        case .image: "Image"
        case .file: "File"
        }
    }
}

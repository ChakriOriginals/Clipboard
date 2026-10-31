import AppKit
import ClipboardCore
import SwiftUI

/// Shows exactly what choosing the selected item will paste: full text with real line breaks, the image,
/// every file, and which flavors go to the pasteboard. Sensitive items stay masked until revealed.
struct PreviewPane: View {
    let model: HistoryModel
    let settings: SettingsStore
    let item: ClipItem?
    @State private var loaded: Loaded?

    /// A preview remembers the exact item value it was made from, so it is never drawn for another
    /// item (or an older version of this one) while the next one loads.
    private struct Loaded {
        let item: ClipItem
        let preview: ContentPreview
        var image: NSImage?
    }

    private struct LoadKey: Equatable {
        let item: ClipItem
        let visible: Bool
    }

    private var current: Loaded? { loaded.flatMap { $0.item == item ? $0 : nil } }

    private func isVisible(_ item: ClipItem) -> Bool { !item.isSensitive || model.revealedID == item.id }

    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()

    var body: some View {
        if let item {
            VStack(alignment: .leading, spacing: 0) {
                content(for: item)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                Divider()
                details(for: item)
            }
            // Keyed on the whole item: a re-copy can replace the content under the same id.
            .task(id: LoadKey(item: item, visible: isVisible(item))) { await load(item) }
        } else {
            ContentUnavailableView("No Selection", systemImage: "clipboard",
                                   description: Text("Select an item to see exactly what will be pasted."))
        }
    }

    private func load(_ item: ClipItem) async {
        loaded = nil
        // A masked sensitive item is not decrypted at all until the user reveals it.
        guard isVisible(item) else { return }
        // Let fast arrow-key repeats pass without decrypting every row they cross.
        try? await Task.sleep(for: .milliseconds(50))
        guard !Task.isCancelled, let preview = await model.preview(for: item.id), !Task.isCancelled else { return }
        loaded = Loaded(item: item, preview: preview)
        if let png = preview.imagePNG, settings.showThumbnails {
            // Bounded decode: never expand a huge image just to preview it.
            let small = await Task.detached(priority: .userInitiated) {
                Thumbnailer.thumbnailPNG(fromImageData: png, maxPixel: 1_200)
            }.value
            if !Task.isCancelled, loaded?.item == item { loaded?.image = small.flatMap(NSImage.init(data:)) }
        }
    }

    // MARK: Content

    @ViewBuilder
    private func content(for item: ClipItem) -> some View {
        if !isVisible(item) {
            VStack(spacing: 10) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(.tertiary)
                Text("Sensitive Item").font(.headline)
                Text("Hidden so it doesn’t appear on screen.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("Reveal") { model.reveal(item.id) }
                    .controlSize(.small)
                    .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let current {
            let preview = current.preview
            if let image = current.image, preview.fileNames.isEmpty, preview.text == nil {
                imageView(image)
                    .padding(20)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if current.image != nil || !preview.fileNames.isEmpty || preview.text != nil {
                // Everything that pastes is shown, e.g. text that rides along with an image or files.
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if let image = current.image {
                            imageView(image).frame(maxHeight: 220)
                        }
                        ForEach(Array(preview.fileNames.enumerated()), id: \.offset) { _, name in
                            Label(name, systemImage: "doc").font(.body)
                        }
                        if let text = preview.text {
                            let label = Text(text)
                                .font(item.kind == .code ? .system(size: 12, design: .monospaced) : .body)
                                .lineSpacing(item.kind == .code ? 2 : 1)
                            // A secret leaves only through restore (↩ / ⇧↩), which marks it concealed and
                            // keeps it off other devices; ⌘C on selected preview text would do neither.
                            if item.isSensitive { label } else { label.textSelection(.enabled) }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                }
            } else {
                Text(item.displayPreview)
                    .foregroundStyle(.secondary)
                    .padding(16)
            }
        } else {
            Color.clear
        }
    }

    private func imageView(_ image: NSImage) -> some View {
        Image(nsImage: image)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: Theme.tileRadius, style: .continuous))
            .shadow(color: .black.opacity(0.12), radius: 4, y: 1)
            .accessibilityLabel("Image preview")
    }

    // MARK: Details

    private func details(for item: ClipItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(metadata(for: item))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if let preview = current?.preview {
                HStack(spacing: 6) {
                    Text("Pastes as").font(.subheadline).foregroundStyle(.tertiary)
                    ForEach(preview.flavors, id: \.self) { flavor in
                        Text(flavor)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.quaternary, in: Capsule())
                    }
                    if preview.hasInvisibleCharacters {
                        Label("Invisible characters", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.orange)
                            .help("This text contains invisible or direction-changing characters, shown as ⟨U+…⟩.")
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func metadata(for item: ClipItem) -> String {
        var parts = [item.kind.label]
        if let app = item.summary.sourceAppName { parts.append(app) }
        parts.append(item.lastCopiedAt.formatted(date: .abbreviated, time: .shortened))
        guard isVisible(item) else { return parts.joined(separator: " · ") } // no size or shape for a masked secret
        parts.append(Self.byteFormatter.string(fromByteCount: Int64(item.byteSize)))
        if let preview = current?.preview {
            if preview.lineCount > 1 { parts.append("\(preview.lineCount) lines") }
            if preview.itemCount > 1 { parts.append("\(preview.itemCount) items") }
            if preview.isTruncated { parts.append("preview shortened") }
        }
        return parts.joined(separator: " · ")
    }
}

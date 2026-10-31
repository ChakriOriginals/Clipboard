import AppKit
import ClipboardCore
import SwiftUI

/// Shows exactly what choosing the selected item will paste: full text with real line breaks, the image,
/// every file, and which flavors go to the pasteboard. Sensitive items stay masked until revealed.
struct PreviewPane: View {
    let model: HistoryModel
    let settings: SettingsStore
    let item: ClipItem?
    @State private var preview: ContentPreview?
    @State private var image: NSImage?

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
            .task(id: item.id) { await load(item) }
        } else {
            ContentUnavailableView("No Selection", systemImage: "clipboard",
                                   description: Text("Select an item to see exactly what will be pasted."))
        }
    }

    private func load(_ item: ClipItem) async {
        preview = nil
        image = nil
        // Let fast arrow-key repeats pass without decrypting every row they cross.
        try? await Task.sleep(for: .milliseconds(50))
        guard !Task.isCancelled, let loaded = await model.preview(for: item.id), !Task.isCancelled else { return }
        preview = loaded
        if let png = loaded.imagePNG, settings.showThumbnails {
            // Bounded decode: never expand a huge image just to preview it.
            let small = await Task.detached(priority: .userInitiated) {
                Thumbnailer.thumbnailPNG(fromImageData: png, maxPixel: 1_200)
            }.value
            if !Task.isCancelled { image = small.flatMap(NSImage.init(data:)) }
        }
    }

    // MARK: Content

    @ViewBuilder
    private func content(for item: ClipItem) -> some View {
        if item.isSensitive && model.revealedID != item.id {
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
        } else if let preview {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.tileRadius, style: .continuous))
                    .shadow(color: .black.opacity(0.12), radius: 4, y: 1)
                    .padding(20)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel("Image preview")
            } else if !preview.fileNames.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(preview.fileNames.enumerated()), id: \.offset) { _, name in
                            Label(name, systemImage: "doc").font(.body)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                }
            } else if let text = preview.text {
                ScrollView {
                    Text(text)
                        .font(item.kind == .code ? .system(size: 12, design: .monospaced) : .body)
                        .lineSpacing(item.kind == .code ? 2 : 1)
                        .textSelection(.enabled)
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

    // MARK: Details

    private func details(for item: ClipItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(metadata(for: item))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if let preview {
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
        parts.append(Self.byteFormatter.string(fromByteCount: Int64(item.byteSize)))
        if let preview {
            if preview.lineCount > 1 { parts.append("\(preview.lineCount) lines") }
            if preview.itemCount > 1 { parts.append("\(preview.itemCount) items") }
            if preview.isTruncated { parts.append("preview shortened") }
        }
        return parts.joined(separator: " · ")
    }
}

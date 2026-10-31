import Foundation

public enum SkipReason: String, Equatable, Sendable {
    case paused, concealed, excludedApp, empty, tooLarge, sensitive, disabledKind
}

public enum CaptureDecision: Sendable {
    case skip(SkipReason)
    case capture(ClipDraft)
}

/// Decides whether and how a pasteboard snapshot becomes a history entry. Pure apart from ImageIO work.
public enum CapturePolicy {
    public static let maxTextBytes = 2_000_000
    public static let maxImageBytes = 10_000_000
    public static let maxSourceImageBytes = 100_000_000
    public static let maxImagePixels = 100_000_000
    public static let maxFileURLs = 1_000
    public static let sensitivePreview = "Sensitive item — hidden"

    private static let textTypes: Set<String> = [PasteboardType.plainText, PasteboardType.rtf, PasteboardType.html, PasteboardType.url]

    /// Checks that need only type names and the frontmost app, so the monitor can skip a change
    /// without ever reading its content (paused, password-manager markers, excluded app, nothing supported).
    public static func precheck(types: Set<String>, frontmostBundleID: String?, settings: CaptureSettings) -> SkipReason? {
        if settings.isPaused { return .paused }
        if !types.isDisjoint(with: PasteboardType.neverCapture) { return .concealed }
        if let app = frontmostBundleID, settings.excludedBundleIDs.contains(app) { return .excludedApp }
        if types.isDisjoint(with: PasteboardType.allowlist) { return .empty }
        return nil
    }

    public static func decide(_ snapshot: PasteboardSnapshot, settings: CaptureSettings) -> CaptureDecision {
        if let reason = precheck(types: snapshot.types, frontmostBundleID: snapshot.frontmostBundleID, settings: settings) {
            return .skip(reason)
        }

        var items = snapshot.items
            .map { $0.filter { PasteboardType.allowlist.contains($0.type) && !$0.data.isEmpty } }
            .filter { !$0.isEmpty }
        if items.isEmpty { return .skip(.empty) }

        let textBytes = items.joined().filter { textTypes.contains($0.type) }.reduce(0) { $0 + $1.data.count }
        if textBytes > maxTextBytes { return .skip(.tooLarge) }
        if items.joined().filter({ $0.type == PasteboardType.fileURL }).count > maxFileURLs { return .skip(.tooLarge) }

        // Normalize images to PNG; TIFF is never stored.
        var imageSize: (width: Int, height: Int)?
        for index in items.indices {
            let png = items[index].first { $0.type == PasteboardType.png }?.data
            let tiff = items[index].first { $0.type == PasteboardType.tiff }?.data
            guard png != nil || tiff != nil else { continue }
            items[index].removeAll { $0.type == PasteboardType.tiff || $0.type == PasteboardType.png }
            let source = png ?? tiff!
            if source.count > maxSourceImageBytes { return .skip(.tooLarge) }
            if let png, png.count > maxImageBytes { return .skip(.tooLarge) }
            guard let size = Thumbnailer.pixelSize(source) else { continue }
            if size.width * size.height > maxImagePixels { return .skip(.tooLarge) }
            guard let pngData = png ?? Thumbnailer.pngData(fromImageData: source) else { continue }
            if pngData.count > maxImageBytes { return .skip(.tooLarge) }
            items[index].insert(Representation(type: PasteboardType.png, data: pngData), at: 0)
            if index == 0 { imageSize = size }
        }
        items.removeAll { $0.isEmpty }

        guard let classification = ContentClassifier.classify(items) else { return .skip(.empty) }
        switch classification.kind {
        case .image where !settings.captureImages, .file where !settings.captureFiles:
            return .skip(.disabledKind)
        default:
            break
        }

        var preview = classification.previewText
        var thumbnail: Data?
        if classification.kind == .image {
            thumbnail = Thumbnailer.thumbnailPNG(fromImageData: classification.canonical)
            if let imageSize { preview = "Image \(imageSize.width)×\(imageSize.height)" }
        }

        var sensitive = false
        if [.text, .richText, .code, .url].contains(classification.kind),
           let text = String(data: classification.canonical, encoding: .utf8),
           SensitivityDetector.isSensitive(text) {
            if settings.sensitiveHandling == .dontSave { return .skip(.sensitive) }
            sensitive = true
            preview = sensitivePreview
        }

        return .capture(ClipDraft(
            kind: classification.kind, previewText: preview,
            sourceAppBundleID: snapshot.frontmostBundleID, sourceAppName: snapshot.frontmostAppName,
            fileNames: classification.fileNames, isSensitive: sensitive,
            content: ClipContent(items: items), canonical: classification.canonical, thumbnailPNG: thumbnail,
            byteSize: items.joined().reduce(0) { $0 + $1.data.count }))
    }
}

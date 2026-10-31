import AppKit
import ClipboardCore

/// Reads allowlisted flavors from a pasteboard into a snapshot. Never reads other flavors' data.
@MainActor
enum PasteboardReader {
    static func typeNames(_ pasteboard: NSPasteboard) -> Set<String> {
        Set((pasteboard.pasteboardItems ?? []).flatMap { $0.types.map(\.rawValue) })
    }

    /// Returns nil when the change is over a per-change cap. The caps are the ones `CapturePolicy.decide`
    /// enforces, checked here while reading so an oversized change is never fully read or parsed on the
    /// main thread.
    static func snapshot(_ pasteboard: NSPasteboard, frontmost: (bundleID: String?, name: String?)?) -> PasteboardSnapshot? {
        let pasteboardItems = pasteboard.pasteboardItems ?? []
        guard pasteboardItems.count <= CapturePolicy.maxItems else { return nil }
        var types = Set<String>()
        var items: [[Representation]] = []
        var totalBytes = 0
        var textBytes = 0
        for item in pasteboardItems {
            var reps: [Representation] = []
            for type in item.types {
                types.insert(type.rawValue)
                guard PasteboardType.allowlist.contains(type.rawValue), let data = item.data(forType: type) else { continue }
                totalBytes += data.count
                if CapturePolicy.textTypes.contains(type.rawValue) { textBytes += data.count }
                guard totalBytes <= CapturePolicy.maxTotalBytes, textBytes <= CapturePolicy.maxTextBytes else { return nil }
                reps.append(Representation(type: type.rawValue, data: data))
            }
            if let derived = derivedPlainText(reps) {
                textBytes += derived.data.count
                guard textBytes <= CapturePolicy.maxTextBytes else { return nil }
                reps.append(derived)
            }
            items.append(reps)
        }
        return PasteboardSnapshot(items: items, types: types, frontmostBundleID: frontmost?.bundleID,
                                  frontmostAppName: frontmost?.name)
    }

    /// RTF without a plain-text flavor: derive one with AppKit so core never parses RTF.
    private static func derivedPlainText(_ reps: [Representation]) -> Representation? {
        guard !reps.contains(where: { $0.type == PasteboardType.plainText }),
              let rtf = reps.first(where: { $0.type == PasteboardType.rtf })?.data,
              rtf.count <= CapturePolicy.maxTextBytes,
              let string = NSAttributedString(rtf: rtf, documentAttributes: nil)?.string, !string.isEmpty
        else { return nil }
        return Representation(type: PasteboardType.plainText, data: Data(string.utf8))
    }
}

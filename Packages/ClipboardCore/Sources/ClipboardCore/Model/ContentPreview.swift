import Foundation

/// Everything the preview pane shows for one entry: exactly what a paste will deliver, made readable.
/// Real line breaks are kept; invisible format/bidi characters are made visible so text can't be spoofed.
public struct ContentPreview: Equatable, Sendable {
    public let text: String?
    public let isTruncated: Bool
    public let lineCount: Int
    public let hasInvisibleCharacters: Bool
    public let imagePNG: Data?
    public let fileNames: [String]
    /// Human names of the flavors that will be written to the pasteboard, in a stable order.
    public let flavors: [String]
    public let itemCount: Int

    public static let maxCharacters = 10_000

    private static let flavorNames: [(type: String, name: String)] = [
        (PasteboardType.plainText, "Plain Text"), (PasteboardType.rtf, "Rich Text"), (PasteboardType.html, "HTML"),
        (PasteboardType.url, "URL"), (PasteboardType.png, "Image"), (PasteboardType.fileURL, "Files"),
    ]

    public static func make(from content: ClipContent) -> ContentPreview {
        let all = content.items.joined()
        let types = Set(all.map(\.type))
        let flavors = flavorNames.filter { types.contains($0.type) }.map(\.name)
        let first = content.items.first ?? []
        func string(_ type: String) -> String? {
            first.first { $0.type == type }.flatMap { String(data: $0.data, encoding: .utf8) }
        }

        var invisible = false
        let fileNames = all.filter { $0.type == PasteboardType.fileURL }
            .compactMap { String(data: $0.data, encoding: .utf8).flatMap(URL.init(string:)) }
            .filter(\.isFileURL).map { escaped($0.lastPathComponent, found: &invisible) }

        var raw = string(PasteboardType.plainText) ?? string(PasteboardType.url)
        if raw == nil, fileNames.isEmpty, let html = string(PasteboardType.html) {
            raw = ContentClassifier.stripTags(html)
        }

        var text: String?
        var truncated = false
        if let raw {
            let limited = raw.count > maxCharacters ? String(raw.prefix(maxCharacters)) : raw
            let shown = escaped(limited, found: &invisible)
            truncated = limited.count < raw.count || shown.count > maxCharacters
            text = String(shown.prefix(maxCharacters))
        }
        return ContentPreview(
            text: text, isTruncated: truncated,
            lineCount: text.map { $0.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).count } ?? 0,
            hasInvisibleCharacters: invisible,
            imagePNG: first.first { $0.type == PasteboardType.png }?.data,
            fileNames: fileNames, flavors: flavors, itemCount: content.items.count)
    }

    /// Makes characters that render as nothing but still act when pasted visible as ⟨U+XXXX⟩:
    /// format/bidi and other default-ignorable characters (except the joiner and variation selectors that
    /// build emoji) and control characters other than tab and line breaks.
    private static let emojiParts: Set<Unicode.Scalar> = ["\u{200D}", "\u{FE0E}", "\u{FE0F}"]

    static func escaped(_ string: String, found: inout Bool) -> String {
        let scalars = Array(string.unicodeScalars)
        var out = String.UnicodeScalarView()
        for (i, scalar) in scalars.enumerated() {
            let properties = scalar.properties
            let category = properties.generalCategory
            let invisible = (category == .format || properties.isDefaultIgnorableCodePoint) && !emojiParts.contains(scalar)
            let lineBreak = scalar == "\n" || (scalar == "\r" && i + 1 < scalars.count && scalars[i + 1] == "\n")
            if invisible || (category == .control && scalar != "\t" && !lineBreak) {
                found = true
                out.append(contentsOf: "⟨U+\(String(scalar.value, radix: 16, uppercase: true))⟩".unicodeScalars)
            } else {
                out.append(scalar)
            }
        }
        return String(out)
    }
}

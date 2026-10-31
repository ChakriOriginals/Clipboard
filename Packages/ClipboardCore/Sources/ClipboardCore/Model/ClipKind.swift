/// What a clipboard entry holds, in display/filter priority order: file > image > url > code > richText > text.
public enum ClipKind: String, Codable, Sendable, CaseIterable {
    case text, richText, url, code, image, file
}

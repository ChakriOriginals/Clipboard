import Foundation

public struct Classification: Equatable, Sendable {
    public let kind: ClipKind
    public let previewText: String
    public let fileNames: [String]
    public let canonical: Data
}

/// Decides an entry's kind and preview from its flavors. Pure; never parses RTF or renders HTML.
public enum ContentClassifier {
    public static func classify(_ items: [[Representation]]) -> Classification? {
        let fileURLs = items.flatMap { $0 }.filter { $0.type == PasteboardType.fileURL }.compactMap(fileURL)
        if !fileURLs.isEmpty {
            let names = fileURLs.map(\.lastPathComponent)
            return Classification(kind: .file, previewText: preview(names.joined(separator: ", ")), fileNames: names,
                                  canonical: Data(fileURLs.map(\.absoluteString).joined(separator: "\n").utf8))
        }
        guard let first = items.first, !first.isEmpty else { return nil }
        func flavor(_ type: String) -> Data? { first.first { $0.type == type }?.data }

        if let png = flavor(PasteboardType.png), !png.isEmpty {
            return Classification(kind: .image, previewText: "Image", fileNames: [], canonical: png)
        }

        let hasRich = flavor(PasteboardType.rtf) != nil || flavor(PasteboardType.html) != nil
        let plain = flavor(PasteboardType.plainText).flatMap { String(data: $0, encoding: .utf8) }
            ?? flavor(PasteboardType.url).flatMap { String(data: $0, encoding: .utf8) }

        guard let text = plain, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            if let html = flavor(PasteboardType.html).flatMap({ String(data: $0, encoding: .utf8) }) {
                let stripped = stripTags(html)
                guard !stripped.isEmpty else { return nil }
                return Classification(kind: .richText, previewText: preview(stripped), fileNames: [],
                                      canonical: Data(stripped.utf8))
            }
            if let rtf = flavor(PasteboardType.rtf), !rtf.isEmpty {
                return Classification(kind: .richText, previewText: "Rich text", fileNames: [], canonical: rtf)
            }
            return nil
        }

        let kind: ClipKind
        if openableURL(text) != nil {
            kind = .url
        } else if looksLikeCode(text) {
            kind = .code
        } else {
            kind = hasRich ? .richText : .text
        }
        return Classification(kind: kind, previewText: preview(text), fileNames: [], canonical: Data(text.utf8))
    }

    /// Whitespace-collapsed, truncated on grapheme boundaries.
    public static func preview(_ text: String, limit: Int = 1000) -> String {
        let collapsed = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard collapsed.count > limit else { return collapsed }
        return String(collapsed.prefix(limit)) + "…"
    }

    /// Non-nil only for a single trimmed http(s) URL with a host — the only URLs ClipFlow will open.
    public static func openableURL(_ text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(where: \.isWhitespace),
              let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https", let host = url.host, !host.isEmpty
        else { return nil }
        return url
    }

    private static func fileURL(_ representation: Representation) -> URL? {
        guard let string = String(data: representation.data, encoding: .utf8),
              let url = URL(string: string.trimmingCharacters(in: .whitespacesAndNewlines)), url.isFileURL
        else { return nil }
        return url
    }

    // MARK: Heuristics

    private static let codeKeywords = try! NSRegularExpression(
        pattern: #"(\b(func|let|var|const|def|class|import|return|if|else|for|while|public|private|struct|fn|elif|try|catch|function)\b|=>|->|#include)"#)

    static func looksLikeCode(_ text: String) -> Bool {
        let sample = String(text.prefix(20_000))
        let lines = sample.split(separator: "\n", omittingEmptySubsequences: true)
        var score = 0
        let hasBraces = sample.contains("{") && sample.contains("}")
        let semicolonLines = lines.filter { $0.trimmingCharacters(in: .whitespaces).hasSuffix(";") }.count
        if hasBraces || semicolonLines >= 2 { score += 2 }
        if lines.count > 1, lines.dropFirst().contains(where: { $0.hasPrefix("  ") || $0.hasPrefix("\t") }) { score += 1 }
        if lines.contains(where: { $0.trimmingCharacters(in: .whitespaces).hasSuffix(":") }),
           lines.contains(where: { $0.hasPrefix("    ") || $0.hasPrefix("\t") }) { score += 1 }
        let range = NSRange(sample.startIndex..., in: sample)
        if codeKeywords.numberOfMatches(in: sample, range: range) >= 2 { score += 2 }
        let proseLines = lines.filter {
            let t = $0.trimmingCharacters(in: .whitespaces)
            return (t.hasSuffix(".") || t.hasSuffix("?") || t.hasSuffix("!")) && t.split(separator: " ").count >= 3
        }.count
        if !lines.isEmpty, proseLines * 2 >= lines.count { score -= 2 }
        return score >= 3
    }

    /// Removes tags and the contents of <script>/<style> in one linear pass (no regex backtracking
    /// on attacker-controlled HTML). A "<" that does not start a tag is kept as text.
    static func stripTags(_ html: String) -> String {
        let chars = Array(html.prefix(2_000_000).unicodeScalars)
        // nextClose[i] = index of the first ">" at or after i (one backward pass keeps this linear).
        var nextClose = [Int](repeating: -1, count: chars.count + 1)
        for j in stride(from: chars.count - 1, through: 0, by: -1) {
            nextClose[j] = chars[j] == ">" ? j : nextClose[j + 1]
        }
        var out = String.UnicodeScalarView()
        var i = 0
        var skipUntil: String?          // closing tag name while inside script/style
        while i < chars.count {
            let c = chars[i]
            guard c == "<", i + 1 < chars.count,
                  chars[i + 1] == "/" || chars[i + 1] == "!" || chars[i + 1].properties.isAlphabetic,
                  case let close = nextClose[i + 1], close >= 0
            else {
                if skipUntil == nil { out.append(c) }
                i += 1
                continue
            }
            let tag = String(String.UnicodeScalarView(chars[(i + 1)..<close])).lowercased()
            let name = tag.drop { $0 == "/" }.prefix { $0.isLetter }
            if let block = skipUntil {
                if tag.hasPrefix("/") && name == block { skipUntil = nil }
            } else if !tag.hasPrefix("/"), name == "script" || name == "style" {
                skipUntil = String(name)
            }
            if skipUntil == nil { out.append(" ") }
            i = close + 1
        }
        var text = String(out)
        for (entity, char) in [("&nbsp;", " "), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&amp;", "&")] {
            text = text.replacingOccurrences(of: entity, with: char)
        }
        return preview(text, limit: Int.max)
    }
}

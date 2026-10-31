import Foundation

/// Local, best-effort detection of secrets in plain text (SECURITY_MODEL §5).
/// A convenience, not a defense: false positives and negatives are expected.
public enum SensitivityDetector {
    private static let patterns: [NSRegularExpression] = [
        #"-----BEGIN [A-Z ]*PRIVATE KEY-----"#,
        #"\bAKIA[0-9A-Z]{16}\b"#,
        #"\bgh[pousr]_[A-Za-z0-9]{36,}\b"#,
        #"\bgithub_pat_[A-Za-z0-9_]{22,}\b"#,
        #"\bglpat-[A-Za-z0-9_\-]{20,}"#,
        #"\bxox[abprs]-[A-Za-z0-9-]{10,}"#,
        #"\b[sr]k_live_[A-Za-z0-9]{16,}\b"#,
        #"\bsk-[A-Za-z0-9_\-]{20,}"#,
        #"\bAIza[0-9A-Za-z_\-]{35}\b"#,
        #"\beyJ[A-Za-z0-9_\-]{8,}\.eyJ[A-Za-z0-9_\-]{8,}\.[A-Za-z0-9_\-]{8,}"#,
        #"(?i)(?<![a-z])(password|passwd|pwd|secret|token|api[_-]?key)\b"?\s*[:=]\s*\S+"#,
    ].map { try! NSRegularExpression(pattern: $0) }

    private static let fileNameLike = try! NSRegularExpression(pattern: #"^[A-Za-z0-9_\-]+(\.[A-Za-z]{1,5})+$"#)

    public static func isSensitive(_ text: String) -> Bool {
        let sample = String(text.prefix(100_000))
        let range = NSRange(sample.startIndex..., in: sample)
        if patterns.contains(where: { $0.firstMatch(in: sample, range: range) != nil }) { return true }
        return isPasswordLike(sample.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    static func isPasswordLike(_ s: String) -> Bool {
        guard (8...128).contains(s.count), !s.contains(where: \.isWhitespace),
              !s.contains("://"), !s.contains("@") || s.filter({ $0 == "@" }).count > 1,
              !s.hasPrefix("/"), !s.hasPrefix("~"),
              fileNameLike.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) == nil
        else { return false }
        let hasLower = s.contains(where: \.isLowercase)
        let hasUpper = s.contains(where: \.isUppercase)
        let digits = s.filter(\.isNumber).count
        let hasSymbol = s.contains { !$0.isLetter && !$0.isNumber }
        let classes = [hasLower, hasUpper, digits > 0, hasSymbol].filter { $0 }.count
        let entropy = shannonEntropy(s)
        if hasSymbol && classes >= 3 && entropy >= 3.0 { return true }
        return s.count >= 20 && classes >= 3 && digits >= 3 && entropy >= 4.0
    }

    static func shannonEntropy(_ s: String) -> Double {
        var counts: [Character: Int] = [:]
        for c in s { counts[c, default: 0] += 1 }
        let n = Double(s.count)
        return counts.values.reduce(0) { acc, count in
            let p = Double(count) / n
            return acc - p * log2(p)
        }
    }
}

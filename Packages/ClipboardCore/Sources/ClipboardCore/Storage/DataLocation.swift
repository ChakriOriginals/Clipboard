import Foundation

/// Where history lives under Application Support. The app was renamed from ClipFlow to Clipboard; the old
/// folder is moved once. A "Clipboard" folder that holds someone else's files is never used or merged into.
public enum DataLocation {
    static let current = "Clipboard"
    static let legacy = "ClipFlow"
    static let fallback = "dev.clipflow.ClipFlow"

    public static func resolve(applicationSupport: URL, fileManager fm: FileManager = .default) -> URL {
        let currentURL = applicationSupport.appendingPathComponent(current, isDirectory: true)
        let legacyURL = applicationSupport.appendingPathComponent(legacy, isDirectory: true)
        let legacyExists = fm.fileExists(atPath: legacyURL.path)

        switch ownership(of: currentURL, fileManager: fm) {
        case .ours:
            return currentURL
        case .missing:
            guard legacyExists else { return currentURL }
            return (try? fm.moveItem(at: legacyURL, to: currentURL)) != nil ? currentURL : legacyURL
        case .empty:
            guard legacyExists else { return currentURL }
            do {
                try fm.removeItem(at: currentURL)
                try fm.moveItem(at: legacyURL, to: currentURL)
                return currentURL
            } catch {
                return legacyURL
            }
        case .foreign:
            return legacyExists ? legacyURL : applicationSupport.appendingPathComponent(fallback, isDirectory: true)
        }
    }

    private enum Ownership { case missing, empty, ours, foreign }

    private static func ownership(of url: URL, fileManager fm: FileManager) -> Ownership {
        guard let names = try? fm.contentsOfDirectory(atPath: url.path) else { return .missing }
        if names.contains("history.sqlite") { return .ours }
        return names.filter { $0 != ".DS_Store" }.isEmpty ? .empty : .foreign
    }
}

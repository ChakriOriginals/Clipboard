/// Full payload of an entry, decrypted only when restoring. One inner array per pasteboard item,
/// so multi-item copies (several files from Finder) round-trip.
public struct ClipContent: Codable, Sendable, Equatable {
    public let items: [[Representation]]

    public init(items: [[Representation]]) {
        self.items = items
    }
}

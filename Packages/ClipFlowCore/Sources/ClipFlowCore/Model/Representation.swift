import Foundation

/// One pasteboard flavor: a UTI and its bytes.
public struct Representation: Codable, Sendable, Equatable {
    public let type: String
    public let data: Data

    public init(type: String, data: Data) {
        self.type = type
        self.data = data
    }
}

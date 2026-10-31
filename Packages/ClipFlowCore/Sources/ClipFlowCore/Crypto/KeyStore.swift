import CryptoKit
import Foundation

public enum KeyStoreError: Error, Equatable {
    /// The key exists (or may exist) but could not be read — e.g. the user denied Keychain access.
    case unreadable(OSStatus)
    case writeFailed(OSStatus)
}

/// Holds the history master key. `loadKey` returns nil only when no key exists.
public protocol KeyStore: Sendable {
    func loadKey() throws -> SymmetricKey?
    func createKey() throws -> SymmetricKey
    func deleteKey() throws
}

/// Test and preview double. Never persists anything.
public final class InMemoryKeyStore: KeyStore, @unchecked Sendable {
    private let lock = NSLock()
    private var key: SymmetricKey?

    public init(key: SymmetricKey? = nil) {
        self.key = key
    }

    public func loadKey() throws -> SymmetricKey? {
        lock.withLock { key }
    }

    public func createKey() throws -> SymmetricKey {
        let new = SymmetricKey(size: .bits256)
        lock.withLock { key = new }
        return new
    }

    public func deleteKey() throws {
        lock.withLock { key = nil }
    }
}

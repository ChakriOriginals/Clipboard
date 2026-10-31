import CryptoKit
import Foundation
import os

public enum StoreOpenResult: Sendable, Equatable {
    case opened
    /// The previous database could not be decrypted and was moved aside (never deleted).
    case recoveredFromUnreadable(movedTo: URL)
}

public enum ClipStoreError: Error, Equatable {
    /// The Keychain holds a key we may not read (e.g. access denied). Nothing was touched.
    case locked(OSStatus)
    case notOpen
    case notFound
}

/// Encrypted clipboard history repository. Serializes all SQLite access.
public actor ClipStore {
    private let directory: URL
    private let keyStore: KeyStore
    private let deviceID: String
    private var db: SQLiteDatabase?
    private var box: CryptoBox?
    private let log = Logger(subsystem: "dev.clipflow.ClipFlow", category: "store")

    private static let canaryPlaintext = Data("ClipFlow canary v1".utf8)
    private static let encoder: PropertyListEncoder = {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        return encoder
    }()

    public init(directory: URL, keyStore: KeyStore, deviceID: String) {
        self.directory = directory
        self.keyStore = keyStore
        self.deviceID = deviceID
    }

    private var databaseURL: URL { directory.appendingPathComponent("history.sqlite") }

    // MARK: Lifecycle

    public func open() throws -> StoreOpenResult {
        close()
        let key: SymmetricKey?
        do {
            key = try keyStore.loadKey()
        } catch KeyStoreError.unreadable(let status) {
            throw ClipStoreError.locked(status)
        }
        try prepareDirectory()

        let fm = FileManager.default
        var result = StoreOpenResult.opened
        let masterKey: SymmetricKey
        if let key {
            masterKey = key
        } else {
            if fm.fileExists(atPath: databaseURL.path) {
                result = .recoveredFromUnreadable(movedTo: try moveDatabaseAside())
            }
            masterKey = try keyStore.createKey()
        }
        let box = CryptoBox(masterKey: masterKey)

        do {
            try openDatabase(box: box)
        } catch {
            log.error("History database unreadable; moving aside")
            close()
            result = .recoveredFromUnreadable(movedTo: try moveDatabaseAside())
            try openDatabase(box: box)
        }
        return result
    }

    /// Deletes the database and the key, then starts fresh with a new key (crypto-shredding).
    public func destroyEverything() throws {
        close()
        for suffix in ["", "-journal", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: databaseURL.path + suffix)
        }
        try keyStore.deleteKey()
        _ = try open()
    }

    private func close() {
        db?.close()
        db = nil
        box = nil
    }

    private func prepareDirectory() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var url = directory
        try url.setResourceValues(values)
    }

    private func openDatabase(box: CryptoBox) throws {
        let isNew = !FileManager.default.fileExists(atPath: databaseURL.path)
        let db = try SQLiteDatabase(path: databaseURL.path)
        try db.execute("PRAGMA journal_mode = DELETE; PRAGMA secure_delete = ON;")
        try Schema.migrate(db)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: databaseURL.path)

        var canary: Data?
        try db.query("SELECT value FROM meta WHERE key = 'canary'", []) { canary = $0.blob(0) }
        if let canary {
            guard (try? box.open(canary, aad: "canary")) == Self.canaryPlaintext else {
                db.close()
                throw ClipStoreError.locked(errSecDecode)
            }
        } else {
            // A database with rows but no canary was not written by us; refuse to adopt it.
            var rows = 0
            try db.query("SELECT COUNT(*) FROM clips", []) { rows = Int($0.int(0)) }
            guard isNew || rows == 0 else {
                db.close()
                throw ClipStoreError.locked(errSecDecode)
            }
            try db.run("INSERT INTO meta (key, value) VALUES ('canary', ?)",
                       [.blob(try box.seal(Self.canaryPlaintext, aad: "canary"))])
        }
        self.db = db
        self.box = box
    }

    private func moveDatabaseAside() throws -> URL {
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        var target = directory.appendingPathComponent("history.unreadable-\(stamp).sqlite")
        var counter = 1
        while FileManager.default.fileExists(atPath: target.path) {
            target = directory.appendingPathComponent("history.unreadable-\(stamp)-\(counter).sqlite")
            counter += 1
        }
        try FileManager.default.moveItem(at: databaseURL, to: target)
        try? FileManager.default.removeItem(atPath: databaseURL.path + "-journal")
        return target
    }

    private func requireOpen() throws -> (SQLiteDatabase, CryptoBox) {
        guard let db, let box else { throw ClipStoreError.notOpen }
        return (db, box)
    }

    // MARK: Writes

    public func insertOrBump(_ draft: ClipDraft, now: Date) throws -> ClipItem {
        let (db, box) = try requireOpen()
        let hash = box.contentHash(kind: draft.kind, canonical: draft.canonical)
        var existing: UUID?
        try db.query("SELECT id FROM clips WHERE content_hash = ?", [.blob(hash)]) {
            existing = $0.text(0).flatMap(UUID.init(uuidString:))
        }
        if let existing {
            try bump(id: existing, now: now)
            return try item(id: existing)
        }

        let id = UUID()
        let summary = ClipSummary(previewText: draft.previewText, sourceAppBundleID: draft.sourceAppBundleID,
                                  sourceAppName: draft.sourceAppName, fileNames: draft.fileNames)
        let sealedSummary = try box.seal(try Self.encoder.encode(summary), aad: "summary:\(id.uuidString)")
        let sealedContent = try box.seal(try Self.encoder.encode(draft.content), aad: "content:\(id.uuidString)")
        let sealedThumbnail = try draft.thumbnailPNG.map { try box.seal($0, aad: "thumbnail:\(id.uuidString)") }
        try db.run("""
            INSERT INTO clips (id, kind, created_at, last_copied_at, content_hash, is_pinned, is_sensitive,
                               device_id, byte_size, summary, thumbnail, content)
            VALUES (?, ?, ?, ?, ?, 0, ?, ?, ?, ?, ?, ?)
            """, [.text(id.uuidString), .text(draft.kind.rawValue), .double(now.timeIntervalSince1970),
                  .double(now.timeIntervalSince1970), .blob(hash), .int(draft.isSensitive ? 1 : 0),
                  .text(deviceID), .int(Int64(draft.byteSize)), .blob(sealedSummary),
                  sealedThumbnail.map(SQLValue.blob) ?? .null, .blob(sealedContent)])
        return ClipItem(id: id, kind: draft.kind, createdAt: now, lastCopiedAt: now, contentHash: hash,
                        isPinned: false, isSensitive: draft.isSensitive, deviceID: deviceID,
                        byteSize: draft.byteSize, hasThumbnail: draft.thumbnailPNG != nil, summary: summary)
    }

    public func bump(id: UUID, now: Date) throws {
        try update("UPDATE clips SET last_copied_at = ? WHERE id = ?", [.double(now.timeIntervalSince1970), .text(id.uuidString)])
    }

    public func setPinned(_ id: UUID, _ pinned: Bool) throws {
        try update("UPDATE clips SET is_pinned = ? WHERE id = ?", [.int(pinned ? 1 : 0), .text(id.uuidString)])
    }

    public func setSensitive(_ id: UUID, _ sensitive: Bool) throws {
        try update("UPDATE clips SET is_sensitive = ? WHERE id = ?", [.int(sensitive ? 1 : 0), .text(id.uuidString)])
    }

    public func delete(ids: [UUID]) throws {
        let (db, _) = try requireOpen()
        guard !ids.isEmpty else { return }
        try db.transaction {
            for id in ids {
                try db.run("DELETE FROM clips WHERE id = ?", [.text(id.uuidString)])
            }
        }
    }

    public func clearUnpinned() throws {
        let (db, _) = try requireOpen()
        try db.run("DELETE FROM clips WHERE is_pinned = 0", [])
        try db.execute("VACUUM")
    }

    private func update(_ sql: String, _ args: [SQLValue]) throws {
        let (db, _) = try requireOpen()
        try db.run(sql, args)
        guard db.changes > 0 else { throw ClipStoreError.notFound }
    }

    // MARK: Reads

    /// All entries, newest first. Rows that fail to decrypt or decode are deleted and counted.
    public func allItems() throws -> (items: [ClipItem], purgedCorrupt: Int) {
        let (db, box) = try requireOpen()
        var items: [ClipItem] = []
        var corrupt: [UUID] = []
        try db.query("""
            SELECT id, kind, created_at, last_copied_at, content_hash, is_pinned, is_sensitive, device_id,
                   byte_size, summary, thumbnail IS NOT NULL
            FROM clips ORDER BY last_copied_at DESC
            """, []) { row in
            guard let id = row.text(0).flatMap(UUID.init(uuidString:)) else { return }
            if let item = Self.decodeItem(row: row, id: id, box: box) {
                items.append(item)
            } else {
                corrupt.append(id)
            }
        }
        if !corrupt.isEmpty {
            log.error("Purging \(corrupt.count, privacy: .public) unreadable history rows")
            try delete(ids: corrupt)
        }
        return (items, corrupt.count)
    }

    public func content(id: UUID) throws -> ClipContent {
        let (db, box) = try requireOpen()
        var sealed: Data?
        try db.query("SELECT content FROM clips WHERE id = ?", [.text(id.uuidString)]) { sealed = $0.blob(0) }
        guard let sealed else { throw ClipStoreError.notFound }
        let plain = try box.open(sealed, aad: "content:\(id.uuidString)")
        return try PropertyListDecoder().decode(ClipContent.self, from: plain)
    }

    public func thumbnail(id: UUID) throws -> Data? {
        let (db, box) = try requireOpen()
        var sealed: Data?
        try db.query("SELECT thumbnail FROM clips WHERE id = ? AND thumbnail IS NOT NULL", [.text(id.uuidString)]) {
            sealed = $0.blob(0)
        }
        return try sealed.map { try box.open($0, aad: "thumbnail:\(id.uuidString)") }
    }

    private func item(id: UUID) throws -> ClipItem {
        let (db, box) = try requireOpen()
        var found: ClipItem?
        try db.query("""
            SELECT id, kind, created_at, last_copied_at, content_hash, is_pinned, is_sensitive, device_id,
                   byte_size, summary, thumbnail IS NOT NULL
            FROM clips WHERE id = ?
            """, [.text(id.uuidString)]) { found = Self.decodeItem(row: $0, id: id, box: box) }
        guard let found else { throw ClipStoreError.notFound }
        return found
    }

    private static func decodeItem(row: SQLiteDatabase.Row, id: UUID, box: CryptoBox) -> ClipItem? {
        guard let kind = row.text(1).flatMap(ClipKind.init(rawValue:)),
              let plain = try? box.open(row.blob(9), aad: "summary:\(id.uuidString)"),
              let summary = try? PropertyListDecoder().decode(ClipSummary.self, from: plain)
        else { return nil }
        return ClipItem(id: id, kind: kind, createdAt: Date(timeIntervalSince1970: row.double(2)),
                        lastCopiedAt: Date(timeIntervalSince1970: row.double(3)), contentHash: row.blob(4),
                        isPinned: row.int(5) != 0, isSensitive: row.int(6) != 0, deviceID: row.text(7) ?? "",
                        byteSize: Int(row.int(8)), hasThumbnail: row.int(10) != 0, summary: summary)
    }
}

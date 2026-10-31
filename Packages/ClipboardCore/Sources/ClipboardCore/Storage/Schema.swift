/// Ordered schema migrations; index + 1 == resulting `user_version`.
enum Schema {
    static let migrations: [String] = [
        """
        CREATE TABLE meta (
          key   TEXT PRIMARY KEY,
          value BLOB NOT NULL
        );
        CREATE TABLE clips (
          id              TEXT PRIMARY KEY,
          kind            TEXT NOT NULL,
          created_at      REAL NOT NULL,
          last_copied_at  REAL NOT NULL,
          content_hash    BLOB NOT NULL UNIQUE,
          is_pinned       INTEGER NOT NULL DEFAULT 0,
          is_sensitive    INTEGER NOT NULL DEFAULT 0,
          device_id       TEXT NOT NULL,
          byte_size       INTEGER NOT NULL,
          summary         BLOB NOT NULL,
          thumbnail       BLOB,
          content         BLOB NOT NULL
        );
        CREATE INDEX clips_last_copied ON clips(last_copied_at DESC);
        """,
    ]

    static func migrate(_ db: SQLiteDatabase) throws {
        let current = try db.userVersion()
        // A newer Clipboard wrote this file: never migrate down or purge rows we can't understand.
        if current > migrations.count { throw ClipStoreError.newerVersion }
        guard current < migrations.count else { return }
        try db.transaction {
            for version in current..<migrations.count {
                try db.execute(migrations[version])
            }
            try db.setUserVersion(migrations.count)
        }
    }
}

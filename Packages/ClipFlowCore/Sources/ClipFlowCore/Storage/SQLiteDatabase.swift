import Foundation
import SQLite3

public enum SQLValue: Sendable {
    case int(Int64), double(Double), text(String), blob(Data), null
}

public struct SQLiteError: Error, CustomStringConvertible {
    public let code: Int32
    public let message: String
    public var description: String { "SQLite error \(code): \(message)" }
}

/// Minimal wrapper over the system SQLite C API. Not thread-safe: owned by a single actor.
final class SQLiteDatabase {
    private var handle: OpaquePointer?
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init(path: String) throws {
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        let rc = sqlite3_open_v2(path, &handle, flags, nil)
        guard rc == SQLITE_OK else {
            let error = SQLiteError(code: rc, message: String(cString: sqlite3_errstr(rc)))
            sqlite3_close(handle)
            handle = nil
            throw error
        }
    }

    deinit {
        close()
    }

    func close() {
        if let handle { sqlite3_close_v2(handle) }
        handle = nil
    }

    var changes: Int { Int(sqlite3_changes(handle)) }

    func execute(_ sql: String) throws {
        try check(sqlite3_exec(handle, sql, nil, nil, nil))
    }

    func run(_ sql: String, _ args: [SQLValue]) throws {
        let statement = try prepare(sql, args)
        defer { sqlite3_finalize(statement) }
        let rc = sqlite3_step(statement)
        guard rc == SQLITE_DONE || rc == SQLITE_ROW else { throw error(rc) }
    }

    func query(_ sql: String, _ args: [SQLValue], row: (Row) throws -> Void) throws {
        let statement = try prepare(sql, args)
        defer { sqlite3_finalize(statement) }
        while true {
            let rc = sqlite3_step(statement)
            if rc == SQLITE_DONE { return }
            guard rc == SQLITE_ROW else { throw error(rc) }
            try row(Row(statement: statement!))
        }
    }

    func transaction(_ body: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE")
        do {
            try body()
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    func userVersion() throws -> Int {
        var version = 0
        try query("PRAGMA user_version", []) { version = Int($0.int(0)) }
        return version
    }

    func setUserVersion(_ version: Int) throws {
        try execute("PRAGMA user_version = \(version)")
    }

    struct Row {
        let statement: OpaquePointer

        func int(_ column: Int32) -> Int64 { sqlite3_column_int64(statement, column) }
        func double(_ column: Int32) -> Double { sqlite3_column_double(statement, column) }

        func text(_ column: Int32) -> String? {
            guard let pointer = sqlite3_column_text(statement, column) else { return nil }
            return String(cString: pointer)
        }

        func blob(_ column: Int32) -> Data {
            let count = Int(sqlite3_column_bytes(statement, column))
            guard count > 0, let pointer = sqlite3_column_blob(statement, column) else { return Data() }
            return Data(bytes: pointer, count: count)
        }

        func isNull(_ column: Int32) -> Bool { sqlite3_column_type(statement, column) == SQLITE_NULL }
    }

    private func prepare(_ sql: String, _ args: [SQLValue]) throws -> OpaquePointer? {
        var statement: OpaquePointer?
        try check(sqlite3_prepare_v2(handle, sql, -1, &statement, nil))
        for (offset, value) in args.enumerated() {
            let index = Int32(offset + 1)
            let rc: Int32
            switch value {
            case .int(let v): rc = sqlite3_bind_int64(statement, index, v)
            case .double(let v): rc = sqlite3_bind_double(statement, index, v)
            case .text(let v): rc = sqlite3_bind_text(statement, index, v, -1, Self.transient)
            case .blob(let v):
                rc = v.withUnsafeBytes { buffer in
                    // A zero-length blob must still bind as a blob, not NULL.
                    sqlite3_bind_blob(statement, index, buffer.baseAddress ?? UnsafeRawPointer(bitPattern: 1),
                                      Int32(v.count), Self.transient)
                }
            case .null: rc = sqlite3_bind_null(statement, index)
            }
            if rc != SQLITE_OK {
                sqlite3_finalize(statement)
                throw error(rc)
            }
        }
        return statement
    }

    private func check(_ rc: Int32) throws {
        guard rc == SQLITE_OK else { throw error(rc) }
    }

    private func error(_ rc: Int32) -> SQLiteError {
        SQLiteError(code: rc, message: handle.map { String(cString: sqlite3_errmsg($0)) } ?? String(cString: sqlite3_errstr(rc)))
    }
}

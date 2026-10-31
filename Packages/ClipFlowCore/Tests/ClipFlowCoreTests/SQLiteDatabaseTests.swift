import XCTest
@testable import ClipFlowCore

final class SQLiteDatabaseTests: XCTestCase {
    var db: SQLiteDatabase!

    override func setUpWithError() throws {
        db = try SQLiteDatabase(path: makeTempDirectory().appendingPathComponent("t.sqlite").path)
        try db.execute("CREATE TABLE t (i INTEGER, d REAL, s TEXT, b BLOB)")
    }

    func testRunAndQueryAllTypes() throws {
        try db.run("INSERT INTO t VALUES (?, ?, ?, ?)", [.int(42), .double(1.5), .text("héllo 👋"), .blob(Data([0, 1, 2]))])
        var rows = 0
        try db.query("SELECT i, d, s, b FROM t", []) { row in
            rows += 1
            XCTAssertEqual(row.int(0), 42)
            XCTAssertEqual(row.double(1), 1.5)
            XCTAssertEqual(row.text(2), "héllo 👋")
            XCTAssertEqual(row.blob(3), Data([0, 1, 2]))
        }
        XCTAssertEqual(rows, 1)
    }

    func testNullAndEmptyBlob() throws {
        try db.run("INSERT INTO t VALUES (?, ?, ?, ?)", [.null, .null, .null, .blob(Data())])
        try db.query("SELECT s, b FROM t", []) { row in
            XCTAssertNil(row.text(0))
            XCTAssertEqual(row.blob(1), Data())
        }
    }

    func testTransactionRollsBackOnError() throws {
        struct Boom: Error {}
        XCTAssertThrowsError(try db.transaction {
            try db.run("INSERT INTO t (i) VALUES (1)", [])
            throw Boom()
        })
        var count = -1
        try db.query("SELECT COUNT(*) FROM t", []) { count = Int($0.int(0)) }
        XCTAssertEqual(count, 0)
    }

    func testUserVersion() throws {
        XCTAssertEqual(try db.userVersion(), 0)
        try db.setUserVersion(3)
        XCTAssertEqual(try db.userVersion(), 3)
    }

    func testSyntaxErrorThrows() {
        XCTAssertThrowsError(try db.execute("NOT SQL"))
    }

    func testChangesReportsAffectedRows() throws {
        try db.run("INSERT INTO t (i) VALUES (1), (2)", [])
        try db.run("DELETE FROM t", [])
        XCTAssertEqual(db.changes, 2)
    }
}

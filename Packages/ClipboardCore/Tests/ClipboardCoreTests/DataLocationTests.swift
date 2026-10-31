import XCTest
@testable import ClipboardCore

final class DataLocationTests: XCTestCase {
    var support: URL!
    let fm = FileManager.default

    override func setUp() { support = makeTempDirectory() }
    override func tearDown() { try? fm.removeItem(at: support) }

    func folder(_ name: String, history: Bool = false, otherFile: Bool = false) -> URL {
        let url = support.appendingPathComponent(name)
        try? fm.createDirectory(at: url, withIntermediateDirectories: true)
        if history { fm.createFile(atPath: url.appendingPathComponent("history.sqlite").path, contents: Data("db".utf8)) }
        if otherFile { fm.createFile(atPath: url.appendingPathComponent("someone-else.plist").path, contents: Data()) }
        return url
    }

    func testFreshInstallUsesClipboardFolder() {
        XCTAssertEqual(DataLocation.resolve(applicationSupport: support).lastPathComponent, "Clipboard")
    }

    func testLegacyFolderIsMovedOnceWithItsHistory() throws {
        _ = folder("ClipFlow", history: true)
        let resolved = DataLocation.resolve(applicationSupport: support)
        XCTAssertEqual(resolved.lastPathComponent, "Clipboard")
        XCTAssertTrue(fm.fileExists(atPath: resolved.appendingPathComponent("history.sqlite").path))
        XCTAssertFalse(fm.fileExists(atPath: support.appendingPathComponent("ClipFlow").path))
        XCTAssertEqual(DataLocation.resolve(applicationSupport: support), resolved) // idempotent
    }

    func testAlreadyMigratedLeavesLegacyLeftoverAlone() {
        _ = folder("Clipboard", history: true)
        _ = folder("ClipFlow", otherFile: true)
        XCTAssertEqual(DataLocation.resolve(applicationSupport: support).lastPathComponent, "Clipboard")
        XCTAssertTrue(fm.fileExists(atPath: support.appendingPathComponent("ClipFlow/someone-else.plist").path))
    }

    func testForeignClipboardFolderIsNeverUsedOrMerged() {
        _ = folder("Clipboard", otherFile: true)
        _ = folder("ClipFlow", history: true)
        XCTAssertEqual(DataLocation.resolve(applicationSupport: support).lastPathComponent, "ClipFlow")
        XCTAssertFalse(fm.fileExists(atPath: support.appendingPathComponent("Clipboard/history.sqlite").path))
    }

    func testForeignClipboardFolderOnFreshInstallUsesBundleNamedFolder() {
        _ = folder("Clipboard", otherFile: true)
        XCTAssertEqual(DataLocation.resolve(applicationSupport: support).lastPathComponent, "dev.clipflow.ClipFlow")
    }

    func testEmptyClipboardFolderIsAdopted() {
        _ = folder("Clipboard")
        _ = folder("ClipFlow", history: true)
        let resolved = DataLocation.resolve(applicationSupport: support)
        XCTAssertEqual(resolved.lastPathComponent, "Clipboard")
        XCTAssertTrue(fm.fileExists(atPath: resolved.appendingPathComponent("history.sqlite").path))
    }
}

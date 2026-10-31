import CryptoKit
import XCTest
@testable import ClipFlowCore

final class CryptoBoxTests: XCTestCase {
    let box = CryptoBox(masterKey: SymmetricKey(size: .bits256))
    let plaintext = Data("hello clipboard 👋".utf8)

    func testSealOpenRoundTrip() throws {
        let sealed = try box.seal(plaintext, aad: "summary:1")
        XCTAssertEqual(try box.open(sealed, aad: "summary:1"), plaintext)
    }

    func testOpenWithWrongAADThrows() throws {
        let sealed = try box.seal(plaintext, aad: "summary:1")
        XCTAssertThrowsError(try box.open(sealed, aad: "content:1"))
        XCTAssertThrowsError(try box.open(sealed, aad: "summary:2"))
    }

    func testOpenWithWrongKeyThrows() throws {
        let sealed = try box.seal(plaintext, aad: "a")
        let other = CryptoBox(masterKey: SymmetricKey(size: .bits256))
        XCTAssertThrowsError(try other.open(sealed, aad: "a"))
    }

    func testTamperedCiphertextThrows() throws {
        var sealed = try box.seal(plaintext, aad: "a")
        sealed[sealed.count / 2] ^= 0x01
        XCTAssertThrowsError(try box.open(sealed, aad: "a"))
    }

    func testNoncesDiffer() throws {
        XCTAssertNotEqual(try box.seal(plaintext, aad: "a"), try box.seal(plaintext, aad: "a"))
    }

    func testSealedDataDoesNotContainPlaintext() throws {
        let marker = Data("hunter2-secret-marker".utf8)
        let sealed = try box.seal(marker, aad: "a")
        XCTAssertNil(sealed.range(of: marker))
    }

    func testContentHashStableAndKeyed() {
        let canonical = Data("same".utf8)
        XCTAssertEqual(box.contentHash(kind: .text, canonical: canonical),
                       box.contentHash(kind: .text, canonical: canonical))
        XCTAssertNotEqual(box.contentHash(kind: .text, canonical: canonical),
                          box.contentHash(kind: .code, canonical: canonical))
        let other = CryptoBox(masterKey: SymmetricKey(size: .bits256))
        XCTAssertNotEqual(box.contentHash(kind: .text, canonical: canonical),
                          other.contentHash(kind: .text, canonical: canonical))
        XCTAssertEqual(box.contentHash(kind: .text, canonical: canonical).count, 32)
    }
}

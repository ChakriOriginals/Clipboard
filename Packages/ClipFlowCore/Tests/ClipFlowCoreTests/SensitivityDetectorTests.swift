import XCTest
@testable import ClipFlowCore

/// Secret-shaped fixtures are assembled at runtime so repository secret scanners don't flag them.
final class SensitivityDetectorTests: XCTestCase {
    let alnum36 = String(String(repeating: "aB3dE5fG7h", count: 4).prefix(36))

    func testPrivateKey() {
        XCTAssertTrue(SensitivityDetector.isSensitive("-----BEGIN " + "OPENSSH PRIVATE KEY-----\nb3BlbnNzaC1rZXktdjEAAAAA\n-----END OPENSSH PRIVATE KEY-----"))
        XCTAssertTrue(SensitivityDetector.isSensitive("-----BEGIN " + "RSA PRIVATE KEY-----\nMIIE"))
    }

    func testKnownTokens() {
        let tokens: [String] = [
            "AKIA" + "IOSFODNN7EXAMPLE",
            "ghp_" + alnum36,
            "github_pat_" + "11ABCDEFG0123456789_abcdefghijklmnopqrstuvwxyz",
            "glpat-" + "abcdefghij0123456789",
            "xox" + "b-123456789012-1234567890123-AbCdEfGhIjKl",
            "sk_" + "live_" + "abcdefghijklmnop1234",
            "sk-" + "ant-api03-abcdefghijklmnopqrstuvwxyz",
            "AIza" + "SyA1234567890abcdefghijklmnopqrstuv",
            "eyJ" + "hbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dozjgNryP4J3jVmNHl0w5N_XgL0n3I9PlFUP0THsR8U",
        ]
        for token in tokens {
            XCTAssertTrue(SensitivityDetector.isSensitive(token), token)
            XCTAssertTrue(SensitivityDetector.isSensitive("export TOKEN_VALUE \(token) # note"), "embedded \(token)")
        }
    }

    func testCredentialAssignments() {
        XCTAssertTrue(SensitivityDetector.isSensitive("password = hunter2"))
        XCTAssertTrue(SensitivityDetector.isSensitive("DB_PASSWORD: s3cr3t!"))
        XCTAssertTrue(SensitivityDetector.isSensitive("api_key=abc123"))
        XCTAssertTrue(SensitivityDetector.isSensitive("{\"token\": \"abc\"}"))
    }

    func testPasswordLike() {
        XCTAssertTrue(SensitivityDetector.isSensitive("Tr0ub4dor&3xK"))
        XCTAssertTrue(SensitivityDetector.isSensitive("aB3dE5fG7hJ9kL1mN3pQ"))
    }

    func testOrdinaryTextIsNotSensitive() {
        let ordinary = ["hello world", "https://github.com/apple/swift", "/usr/local/bin", "user@example.com",
                        "README.md", "12345678", "example.com", "myVariableName2", "Hello, World!",
                        "The password policy changed last week, see the wiki.",
                        "Line one of a note.\nLine two of a note.\nLine three.", "", "café ☕️"]
        for text in ordinary {
            XCTAssertFalse(SensitivityDetector.isSensitive(text), text)
        }
    }

    func testHugeInputIsFast() {
        let big = String(repeating: "lorem ipsum dolor sit amet ", count: 80_000) // ~2 MB
        let start = Date()
        XCTAssertFalse(SensitivityDetector.isSensitive(big))
        XCTAssertLessThan(Date().timeIntervalSince(start), 1.0)
    }
}

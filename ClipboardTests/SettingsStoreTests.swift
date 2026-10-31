import ClipboardCore
import XCTest
@testable import Clipboard

@MainActor
final class SettingsStoreTests: XCTestCase {
    var defaults: UserDefaults!
    var suite: String!

    override func setUp() async throws {
        (defaults, suite) = makeTestDefaults()
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
    }

    func testDefaults() {
        let s = SettingsStore(defaults: defaults)
        XCTAssertEqual(s.shortcut, .default)
        XCTAssertTrue(s.pasteOnSelect)
        XCTAssertEqual(s.retentionDays, 30)
        XCTAssertEqual(s.maxItems, 1_000)
        XCTAssertTrue(s.captureImages)
        XCTAssertTrue(s.captureFiles)
        XCTAssertEqual(s.sensitiveHandling, .maskAndExpire)
        XCTAssertEqual(s.sensitiveExpiryMinutes, 60)
        XCTAssertTrue(s.excludedBundleIDs.contains("com.apple.keychainaccess"))
        XCTAssertTrue(s.excludedBundleIDs.contains("com.1password.1password"))
        XCTAssertFalse(s.isPaused)
        XCTAssertEqual(s.panelPosition, .center)
        XCTAssertTrue(s.showThumbnails)
        XCTAssertFalse(s.hasCompletedOnboarding)
        XCTAssertEqual(s.retentionSettings, RetentionSettings(maxAge: 30 * 86_400, maxCount: 1_000, sensitiveExpiry: 3_600))
    }

    func testSettingsPersistAcrossInstances() {
        let a = SettingsStore(defaults: defaults)
        a.shortcut = Shortcut(keyCode: 9, modifiers: [.control, .option])
        a.pasteOnSelect = false
        a.retentionDays = nil
        a.maxItems = 5_000
        a.captureImages = false
        a.sensitiveHandling = .dontSave
        a.sensitiveExpiryMinutes = nil
        a.excludedBundleIDs = ["com.example"]
        a.isPaused = true
        a.panelPosition = .nearMouse
        a.showThumbnails = false
        a.hasCompletedOnboarding = true

        let b = SettingsStore(defaults: defaults)
        XCTAssertEqual(b.shortcut, Shortcut(keyCode: 9, modifiers: [.control, .option]))
        XCTAssertFalse(b.pasteOnSelect)
        XCTAssertNil(b.retentionDays)
        XCTAssertEqual(b.maxItems, 5_000)
        XCTAssertFalse(b.captureImages)
        XCTAssertEqual(b.sensitiveHandling, .dontSave)
        XCTAssertNil(b.sensitiveExpiryMinutes)
        XCTAssertEqual(b.excludedBundleIDs, ["com.example"])
        XCTAssertTrue(b.isPaused)
        XCTAssertEqual(b.panelPosition, .nearMouse)
        XCTAssertFalse(b.showThumbnails)
        XCTAssertTrue(b.hasCompletedOnboarding)
        XCTAssertEqual(b.retentionSettings, RetentionSettings(maxAge: nil, maxCount: 5_000, sensitiveExpiry: nil))
        XCTAssertEqual(b.captureSettings, CaptureSettings(isPaused: true, excludedBundleIDs: ["com.example"], captureImages: false,
                                                          captureFiles: true, sensitiveHandling: .dontSave))
    }

    func testDeviceIDGeneratedOnceAndStable() {
        let id = SettingsStore(defaults: defaults).deviceID
        XCTAssertNotNil(UUID(uuidString: id))
        XCTAssertEqual(SettingsStore(defaults: defaults).deviceID, id)
    }

    func testCorruptShortcutFallsBackToDefault() {
        defaults.set(Data("garbage".utf8), forKey: "shortcut")
        XCTAssertEqual(SettingsStore(defaults: defaults).shortcut, .default)
    }

    func testOutOfRangeIntegersFallBackToDefaults() {
        defaults.set(-1, forKey: "maxItems")
        defaults.set(-5, forKey: "retentionDays")
        defaults.set(999_999, forKey: "sensitiveExpiryMinutes")
        let s = SettingsStore(defaults: defaults)
        XCTAssertEqual(s.maxItems, 1_000)
        XCTAssertNil(s.retentionDays)
        XCTAssertEqual(s.sensitiveExpiryMinutes, 60)
    }
}

import ClipboardCore
import Foundation
import Observation

enum PanelPosition: String, CaseIterable, Sendable {
    case center, nearMouse
}

/// Typed, observable wrapper over UserDefaults.
@MainActor
@Observable
final class SettingsStore {
    @ObservationIgnored private let defaults: UserDefaults

    static let defaultExcludedApps = ["com.apple.keychainaccess", "com.apple.Passwords",
                                      "com.1password.1password", "com.bitwarden.desktop"]

    static let retentionDayChoices = [1, 7, 30, 90]
    static let maxItemChoices = [100, 500, 1_000, 5_000, 10_000]
    static let sensitiveExpiryChoices = [10, 60, 1_440]

    var shortcut: Shortcut { didSet { defaults.set(try? JSONEncoder().encode(shortcut), forKey: "shortcut") } }
    var pasteOnSelect: Bool { didSet { defaults.set(pasteOnSelect, forKey: "pasteOnSelect") } }
    /// nil = keep forever.
    var retentionDays: Int? { didSet { defaults.set(retentionDays ?? 0, forKey: "retentionDays") } }
    var maxItems: Int { didSet { defaults.set(maxItems, forKey: "maxItems") } }
    var captureImages: Bool { didSet { defaults.set(captureImages, forKey: "captureImages") } }
    var captureFiles: Bool { didSet { defaults.set(captureFiles, forKey: "captureFiles") } }
    var sensitiveHandling: SensitiveHandling { didSet { defaults.set(sensitiveHandling.rawValue, forKey: "sensitiveHandling") } }
    /// nil = never auto-remove sensitive items.
    var sensitiveExpiryMinutes: Int? { didSet { defaults.set(sensitiveExpiryMinutes ?? 0, forKey: "sensitiveExpiryMinutes") } }
    var excludedBundleIDs: [String] { didSet { defaults.set(excludedBundleIDs, forKey: "excludedBundleIDs") } }
    var isPaused: Bool { didSet { defaults.set(isPaused, forKey: "isPaused") } }
    var panelPosition: PanelPosition { didSet { defaults.set(panelPosition.rawValue, forKey: "panelPosition") } }
    var showThumbnails: Bool { didSet { defaults.set(showThumbnails, forKey: "showThumbnails") } }
    var hasCompletedOnboarding: Bool { didSet { defaults.set(hasCompletedOnboarding, forKey: "hasCompletedOnboarding") } }
    let deviceID: String

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        func bool(_ key: String, _ fallback: Bool) -> Bool { defaults.object(forKey: key) as? Bool ?? fallback }
        func int(_ key: String, _ fallback: Int) -> Int { defaults.object(forKey: key) as? Int ?? fallback }

        shortcut = defaults.data(forKey: "shortcut").flatMap { try? JSONDecoder().decode(Shortcut.self, from: $0) } ?? .default
        pasteOnSelect = bool("pasteOnSelect", true)
        // Values come from a plist any same-user process can edit: accept only what the UI offers.
        let days = int("retentionDays", 30)
        retentionDays = days <= 0 ? nil : (Self.retentionDayChoices.contains(days) ? days : 30)
        let max = int("maxItems", 1_000)
        maxItems = Self.maxItemChoices.contains(max) ? max : 1_000
        captureImages = bool("captureImages", true)
        captureFiles = bool("captureFiles", true)
        sensitiveHandling = defaults.string(forKey: "sensitiveHandling").flatMap(SensitiveHandling.init(rawValue:)) ?? .maskAndExpire
        let minutes = int("sensitiveExpiryMinutes", 60)
        sensitiveExpiryMinutes = minutes <= 0 ? nil : (Self.sensitiveExpiryChoices.contains(minutes) ? minutes : 60)
        excludedBundleIDs = defaults.stringArray(forKey: "excludedBundleIDs") ?? Self.defaultExcludedApps
        isPaused = bool("isPaused", false)
        panelPosition = defaults.string(forKey: "panelPosition").flatMap(PanelPosition.init(rawValue:)) ?? .center
        showThumbnails = bool("showThumbnails", true)
        hasCompletedOnboarding = bool("hasCompletedOnboarding", false)
        if let id = defaults.string(forKey: "deviceID") {
            deviceID = id
        } else {
            deviceID = UUID().uuidString
            defaults.set(deviceID, forKey: "deviceID")
        }
    }

    var captureSettings: CaptureSettings {
        CaptureSettings(isPaused: isPaused, excludedBundleIDs: Set(excludedBundleIDs), captureImages: captureImages,
                        captureFiles: captureFiles, sensitiveHandling: sensitiveHandling)
    }

    var retentionSettings: RetentionSettings {
        RetentionSettings(maxAge: retentionDays.map { TimeInterval($0) * 86_400 }, maxCount: maxItems,
                          sensitiveExpiry: sensitiveExpiryMinutes.map { TimeInterval($0) * 60 })
    }
}

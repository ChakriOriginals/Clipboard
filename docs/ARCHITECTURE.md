# ClipFlow — Architecture

Status: Draft for approval · Date: 2026-10-30

## 1. Approaches considered

**Project structure**
| Option | Trade-off | Verdict |
|---|---|---|
| A. XcodeGen `project.yml` + local SwiftPM package `ClipFlowCore` | Real `.app` bundle runs from Xcode (Keychain/TCC need a bundle ID); core logic tested with fast `swift test`; contributors need `brew install xcodegen`. | **Chosen** |
| B. Pure SwiftPM + bundling script | No extra tool, but running from Xcode launches a bare binary with no bundle identity — breaks permission and Keychain testing. | Rejected |
| C. Committed `.xcodeproj` | `project.pbxproj` merge conflicts in an open-source repo. | Rejected |

**Encrypted storage**
| Option | Trade-off | Verdict |
|---|---|---|
| System SQLite + per-row AES-GCM (CryptoKit) | Zero dependencies; metadata columns stay plaintext; search must happen in memory over decrypted previews. | **Chosen** |
| SQLCipher | Whole-file encryption but a C dependency to build and maintain. | Rejected |
| SwiftData / Core Data | No control over encryption at rest. | Rejected |

## 2. Repository layout

```
ClipFlow/
├── project.yml                  # XcodeGen spec (app + app tests); .xcodeproj is generated, gitignored
├── Makefile                     # generate, build, test, app, release
├── Packages/ClipFlowCore/       # AppKit-free logic, reusable by a future iOS app
│   ├── Package.swift
│   ├── Sources/ClipFlowCore/
│   │   ├── Model/               # ClipKind, ClipItem, ClipSummary, ClipContent, Representation
│   │   ├── Capture/             # PasteboardSnapshot, CapturePolicy, ContentClassifier, SensitivityDetector, Thumbnailer
│   │   ├── Storage/             # SQLiteDatabase (thin C-API wrapper), ClipStore (actor), Schema
│   │   ├── Crypto/              # CryptoBox (AES-GCM + HKDF), KeyStore protocol, KeychainKeyStore
│   │   ├── Search/              # SearchQuery, SearchIndex
│   │   └── Retention/           # RetentionPolicy
│   └── Tests/ClipFlowCoreTests/
├── ClipFlow/                    # macOS app target (AppKit + SwiftUI)
│   ├── App/                     # ClipFlowApp, AppDelegate, MenuBarController, Onboarding
│   ├── Clipboard/               # PasteboardMonitor, PasteboardWriter, AutoPaster
│   ├── Panel/                   # ClipboardPanel (NSPanel), PanelController, PanelView, RowView, KeyRouter
│   ├── Shortcuts/               # HotKey (Carbon), ShortcutRecorder
│   ├── Settings/                # SettingsStore, SettingsView + tabs
│   ├── HistoryModel.swift       # @MainActor @Observable façade used by UI
│   └── Resources/               # Assets.xcassets, Info.plist, ClipFlow.entitlements
├── ClipFlowTests/               # app-level integration tests (named pasteboards, hotkey registration)
├── docs/
└── .github/
```

## 3. Domain model

```swift
enum ClipKind: String { case text, richText, url, code, image, file }

struct Representation: Codable, Sendable {   // one pasteboard flavor
    let type: String                          // UTI, e.g. "public.utf8-plain-text"
    let data: Data
}

struct ClipContent: Codable, Sendable {      // full payload, loaded only on restore
    let items: [[Representation]]             // one entry per NSPasteboardItem (multi-file copies round-trip)
}

struct ClipSummary: Codable, Sendable {      // small payload, loaded for listing/search
    let previewText: String                   // ≤ 1,000 chars, single-line-normalized for display
    let sourceAppBundleID: String?            // best-effort
    let sourceAppName: String?
    let fileNames: [String]                   // file kind only
}

struct ClipItem: Identifiable, Sendable {     // a row, decrypted summary in memory
    let id: UUID
    var kind: ClipKind
    let createdAt: Date
    var lastCopiedAt: Date
    let contentHash: Data                     // HMAC-SHA256, see SECURITY_MODEL
    var isPinned: Bool
    var isSensitive: Bool
    let deviceID: String                      // random per-install UUID, for future sync
    let byteSize: Int
    let summary: ClipSummary
}
```

Supported representations (allowlist; everything else is dropped):
`public.utf8-plain-text`, `public.rtf`, `public.html`, `public.url`, `public.file-url`, `public.png`,
`public.tiff` (converted to PNG at capture). TIFF is never stored.

## 4. Components and responsibilities

### Core (`ClipFlowCore`, no AppKit)
- **PasteboardSnapshot** — `[Representation]` plus `changeCount` and `frontmostBundleID`. Built by the app,
  consumed by core. Makes everything downstream testable without a real pasteboard.
- **CapturePolicy** — pure function `decide(snapshot, settings) -> .skip(Reason) | .capture(ClipDraft)`:
  concealed/transient markers, paused, excluded app, allowlist filtering, size limits, image toggle,
  sensitivity handling.
- **ContentClassifier** — pure: representations → `(ClipKind, previewText)`. URL = single trimmed token
  parsing to `http(s)` with a host, or a `public.url` flavor. Code = scored heuristic on plain text
  (multi-line + indentation/braces/semicolons/keywords). Core never parses RTF or HTML: if a snapshot has
  RTF but no plain-text flavor, the app's monitor derives plain text with AppKit (size-capped) and adds it
  to the snapshot; HTML-only content gets a crude tag-strip preview and is never rendered.
- **SensitivityDetector** — pure: plain text → `Bool` (see SECURITY_MODEL §5).
- **Thumbnailer** — ImageIO `CGImageSourceCreateThumbnailAtIndex`, max 256 px, PNG output; also TIFF→PNG.
- **CryptoBox** — AES-GCM seal/open with AAD; HKDF-derived subkeys for encryption and hashing.
- **KeyStore** — protocol (`loadOrCreateKey`, `deleteKey`) with `KeychainKeyStore` and an in-memory test
  double. The one protocol that earns its keep: tests must never touch the user's Keychain.
- **SQLiteDatabase** — ~150-line wrapper over `sqlite3` C API: open, exec, prepared statements, bind,
  step, transactions, `user_version` migrations.
- **ClipStore** (actor) — repository: insert-or-bump (dedup by hash), fetch summaries, fetch content,
  pin, mark sensitive, delete, delete many, clear unpinned, destroy (delete file + key). Owns the DB
  handle and the CryptoBox. Verifies the key canary on open.
- **SearchIndex** — pure filtering over `[ClipItem]` with a precomputed folded search string per item.
- **RetentionPolicy** — pure: `idsToDelete(items, policy, now) -> [UUID]`.

### App (`ClipFlow`)
- **PasteboardMonitor** — `Timer` (0.5 s, tolerance 0.2 s) comparing `NSPasteboard.changeCount`. Before
  reading content it checks `accessBehavior` (macOS 15.4+): `.alwaysAllow` → read; `.default` → read (the
  first read may trigger the system alert, after which the state changes); `.ask` → do **not** read
  automatically (that would alert on every copy) — set `accessState = .needsAlwaysAllow` and show remediation
  in menu/panel/onboarding with an "Open Privacy Settings" button; `.alwaysDeny` → same, `.denied`.
  Reading `changeCount` and `types` is metadata and does not read content. On change,
  reads only allowlisted types with size caps, builds a `PasteboardSnapshot`, and hands it to `HistoryModel`.
  Takes an `NSPasteboard` parameter so integration tests use a uniquely named pasteboard. Skips the
  change count recorded by `PasteboardWriter` (feedback-loop guard).
- **PasteboardWriter** — writes a `ClipContent` back (all representations; images also as `NSImage` so TIFF
  consumers work), records the resulting `changeCount`.
- **AutoPaster** — if `AXIsProcessTrusted()`, posts `⌘V` via `CGEvent` to the HID tap using the key code
  that produces "v" in the current keyboard layout (UCKeyTranslate lookup, fallback 9). Otherwise no-op
  and reports "not permitted".
- **HotKey** — Carbon `RegisterEventHotKey`/`InstallEventHandler` (public, no permission needed).
  Reports registration failure (e.g. taken by another app) to Settings.
- **ClipboardPanel / PanelController** — `NSPanel` with `.nonactivatingPanel`, `canBecomeKey = true`,
  level `.floating`, `collectionBehavior [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]`.
  Non-activating means the previously active app stays frontmost, so `⌘V` lands there without re-activation.
  Hosts SwiftUI in `NSHostingView` over `NSVisualEffectView` (12 pt corner radius). Closes on `resignKey`.
- **KeyRouter** — local `NSEvent` keyDown monitor active while the panel is key; maps keys to panel commands
  before the text field sees them. Pure mapping function is unit-tested.
- **ThumbnailCache** — `NSCache`-backed (count limit ~200), rows request thumbnails lazily from
  `ClipStore` when they appear; memory is bounded regardless of history size (C10).
- **HistoryModel** (`@MainActor @Observable`) — holds `[ClipItem]` (summaries only, no thumbnails), current query, filters,
  selection; calls `ClipStore`; runs retention (launch, post-capture, hourly timer).
- **SettingsStore** (`@Observable`) — typed wrapper over `UserDefaults`.
- **MenuBarController** — `NSStatusItem` + `NSMenu`; paused and "paste access denied" states.

## 5. Data flow

```
copy in any app
  → PasteboardMonitor (timer sees changeCount++)            [main]
  → read allowlisted flavors, ≤ caps → PasteboardSnapshot   [main]
  → CapturePolicy.decide (pure)                             [main, µs]
  → Thumbnailer / classify / hash / seal                    [ClipStore actor, off main]
  → INSERT or bump lastCopiedAt                             [ClipStore actor]
  → HistoryModel.items updated, retention applied           [main]

⌘⇧V → HotKey → PanelController.show → PanelView (search focused)
  type → SearchIndex.filter (in-memory, main)
  Return → ClipStore.content(id) (decrypt) → PasteboardWriter → close panel → AutoPaster ⌘V
```

## 6. Persistence

Location: `~/Library/Application Support/ClipFlow/history.sqlite` — directory `0700`, file `0600`,
directory marked `isExcludedFromBackup` (Time Machine).

```sql
PRAGMA journal_mode = DELETE;     -- no long-lived WAL file holding old pages
PRAGMA secure_delete = ON;        -- overwrite freed pages
PRAGMA foreign_keys = ON;

CREATE TABLE meta (
  key   TEXT PRIMARY KEY,
  value BLOB NOT NULL               -- 'canary': sealed known plaintext for key verification
);

CREATE TABLE clips (
  id              TEXT PRIMARY KEY,   -- UUID string
  kind            TEXT NOT NULL,
  created_at      REAL NOT NULL,      -- seconds since 1970
  last_copied_at  REAL NOT NULL,
  content_hash    BLOB NOT NULL UNIQUE,
  is_pinned       INTEGER NOT NULL DEFAULT 0,
  is_sensitive    INTEGER NOT NULL DEFAULT 0,
  device_id       TEXT NOT NULL,
  byte_size       INTEGER NOT NULL,
  summary         BLOB NOT NULL,      -- AES-GCM(JSON ClipSummary), AAD = "summary:" + id
  thumbnail       BLOB,               -- AES-GCM(PNG ≤ 256 px), AAD = "thumbnail:" + id; images only
  content         BLOB NOT NULL       -- AES-GCM(JSON ClipContent), AAD = "content:" + id
);
CREATE INDEX clips_last_copied ON clips(last_copied_at DESC);
```

Migrations: `PRAGMA user_version`; ordered list of migration closures run in a transaction at open.

Corrupt rows (decryption or decode failure) are skipped at load, counted, and deleted; they never crash
the app. If the DB file itself cannot be opened or the canary fails, it is renamed to
`history.unreadable-<timestamp>.sqlite` and a fresh DB is created; the user is notified (X4).

## 7. Concurrency

Swift 6 language mode, strict concurrency. `ClipStore` is an actor (serializes all SQLite access; one
connection). UI state lives on the main actor. Search runs synchronously on the main actor (≈ ms for 10k
items; measured by a perf test — move to a background task only if the target is missed). Deleting while
searching is safe: search operates on the value-type `[ClipItem]` snapshot; the model removes items after
the store confirms.

## 8. Platform constraints (investigated)

| Topic | Finding | Consequence |
|---|---|---|
| Clipboard monitoring | `NSPasteboard` has no change notification; polling `changeCount` is the standard approach. | 0.5 s timer with tolerance; no busy-wait. |
| Pasteboard privacy | macOS 15.4 SDK added `NSPasteboard.accessBehavior` (`default/ask/alwaysAllow/alwaysDeny`); 15.4 shipped it as an opt-in preview and later releases enforce prompting for programmatic general-pasteboard reads. Exact enforcement and the Settings pane name are verified manually on the target OS (TEST_PLAN M-tests). | Monitor gates reads on `accessBehavior` (see §4); onboarding and menu explain how to set Always Allow. |
| Global shortcut | Carbon `RegisterEventHotKey` is public and needs no permission. Since macOS 15 it rejects shortcuts whose only modifiers are ⌥ or ⌥⇧. The standard AppKit "Paste and Match Style" is ⌥⇧⌘V; `⌘⇧V` is "paste as plain text" only in some apps (Chrome, Slack, Google Docs, VS Code…), which ClipFlow overrides while registered. | Rebindable; recorder requires ⌘ or ⌃; conflict note in Settings. |
| Automated paste | Posting `CGEvent`s to other apps requires Accessibility (`AXIsProcessTrusted`). TCC grants are tied to the code signature; ad-hoc rebuilds reset them. | Optional; copy-only fallback. |
| Secure Input | Secure Event Input blocks event taps/keystroke monitoring. Whether Carbon hotkeys keep firing is **unverified** (reports conflict). `IsSecureEventInputEnabled()` detects it. | Verify manually (TEST_PLAN); menu note only if verified to matter. |
| Source app | No API identifies the app that wrote the pasteboard. Frontmost app at detection is a heuristic. | Exclusions documented as best-effort. |
| App Sandbox | Sandboxed apps cannot reliably post events to other apps for auto-paste and need temporary exceptions. | Not sandboxed; Hardened Runtime on; distributed outside the Mac App Store. |
| Keychain | Data-protection keychain needs a keychain-access-groups entitlement and provisioning (Team ID). ClipFlow uses the file-based login keychain in all builds; its ACL is tied to the code signature, so ad-hoc rebuilds may prompt "ClipFlow wants to use…". Accessibility constants like `…ThisDeviceOnly` are ignored by the file-based keychain (TN3137). | Accept; "Always Allow" once per build. Optional stable signing (below) avoids repeat prompts. |
| Signing for builders | Default: ad-hoc (`CODE_SIGN_IDENTITY = -`). Optional untracked `Local.xcconfig` sets `DEVELOPMENT_TEAM` (free Personal Team works) for a stable signature, so Accessibility and Keychain grants survive rebuilds. | Documented in README/CONTRIBUTING. |
| Signing / notarization | Notarization requires a paid Developer ID. Ad-hoc signed apps from GitHub are quarantined; Gatekeeper requires right-click › Open or `xattr -dr com.apple.quarantine`. | Release workflow builds ad-hoc by default, Developer ID + notarization when secrets are configured. |
| iOS / iPadOS | Apps can read the pasteboard only in the foreground; iOS 16+ shows a paste permission prompt; no background monitoring. Universal Clipboard has no public API — it simply populates the local pasteboard. | Phase C companion is user-initiated capture + synced history only. |
| CloudKit | Requires a paid Developer Program membership, an iCloud container entitlement, and a signed-in iCloud account with iCloud Drive enabled. | Phase C only; see §9. |

## 9. Cross-device sync (design only — not implemented)

**Option A — CloudKit private database.** Each `clips` row becomes a `CKRecord` whose payload is the same
AES-GCM ciphertext. Conflict rule: last-writer-wins on `lastCopiedAt`; pin and delete use tombstones.
Key distribution: synchronizable Keychain item (iCloud Keychain, end-to-end encrypted), or CloudKit
Advanced Data Protection where enabled. Pros: no server, works across networks, Apple handles
offline queues and push. Cons: paid developer account, iCloud required, Apple outages, entitlement and
container setup make building from source harder for contributors.

**Option B — Local network peer-to-peer** (`Network.framework`, Bonjour `_clipflow._tcp`, TLS 1.3 with a
pre-shared key from a pairing code shown on one device and typed on the other). Pros: no account, no
cloud, works without a paid membership on macOS. Cons: devices must be on the same network and both
awake; iOS background limits mean the phone rarely receives anything unless open; pairing, revocation,
and retry logic are ours to build and secure; Local Network privacy prompts.

**Recommendation:** CloudKit (A) for Phase C, because the iPhone cannot run a background peer; CloudKit
push plus end-to-end encrypted payloads is the only design that delivers history to a phone that was
asleep. Gate it behind a build flag so the default open-source build has no iCloud entitlement.
Requires a security review of key distribution before implementation.

## 10. Builder's latitude

Visual details (spacing, exact colors, icon choice), test helper structure, the exact code-detection
scoring weights, and Makefile targets are left to the implementer, within the acceptance criteria.

## 11. CI

GitHub Actions on `macos-latest` with the runner's default Xcode (Swift ≥ 6.0). Package declares
`swift-tools-version: 6.0` and avoids newer-only language features so it builds on older runners.
Jobs: `swift test` (core), `xcodegen generate && xcodebuild test` (app, unsigned), static privacy checks
(no network APIs, no content in log calls). Actions pinned by commit SHA.

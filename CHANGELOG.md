# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Changed
- Renamed from ClipFlow to **Clipboard**. Existing history, settings and permissions carry over: the bundle identifier is unchanged and the data folder moves from `Application Support/ClipFlow` to `Application Support/Clipboard` on first launch.

## [0.1.0] - 2026-10-30

### Added
- Menu bar app that records clipboard history while running: text, rich text, links, code, images and file references.
- Floating history panel on ⇧⌘V (configurable) with search, kind and date filters, keyboard navigation,
  ⌘1–⌘9 quick picks, pinned section, and paste into the previous app (with Accessibility permission).
- Encrypted local storage (SQLite + AES-256-GCM, key in Keychain), de-duplication, crypto-shredding
  “Clear Everything”, safe recovery when history can’t be decrypted, locked state when Keychain access is denied.
- Privacy controls: pause, app exclusions, concealed-item filtering, secret detection with masking and expiry,
  retention by age and count.
- Settings, first-run onboarding, launch at login.

### Security
Fixes from the pre-release code review and security audit (run 1, see `docs/security-audit/`):
- HTML preview stripping is linear; a crafted HTML-only copy could previously pin a CPU core for hours.
- Per-change limits on item count and total bytes; overflow-safe image dimension checks; lazy, bounded TIFF on restore.
- Capture is serialized and coalesced; history order uses the observed copy time.
- Auto-paste is bound to ClipFlow's own pasteboard write and to the app that was frontmost.
- Sensitive expiry is enforced within a minute and on read; manual "Mark as sensitive" masks preview, search and thumbnails.
- Clear Everything also removes set-aside history copies; recovery never moves live history aside for transient errors.
- Release builds no longer carry `get-task-allow` or coverage instrumentation.
- Release workflow: protected `release` environment, least-privilege publish job, tag must be on `main` and match the version.

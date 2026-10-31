# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

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

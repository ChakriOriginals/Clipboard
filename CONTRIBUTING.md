# Contributing to ClipFlow

Thanks for helping. ClipFlow is small on purpose; the bar for new features is “would most users notice if
this were missing?”

## Setup

```bash
brew install xcodegen
make test        # core tests, app tests, privacy checks
make generate    # creates ClipFlow.xcodeproj for Xcode
```

The app tests run inside the app as a test host. They use private, uniquely named pasteboards, temporary
folders and throwaway `UserDefaults`, so they never touch your clipboard, Keychain or history.

Optional: add `Config/Local.xcconfig` (untracked) with your free Personal Team so permissions survive
rebuilds — see the README.

## Layout

- `Packages/ClipFlowCore` — everything that doesn’t need AppKit: model, capture rules, classification,
  sensitivity checks, encryption, SQLite storage, search, retention. Fast `swift test`.
- `ClipFlow/` — the macOS app: pasteboard monitor and writer, hotkey, panel, settings, menu bar.
- `docs/` — product spec, architecture, security model, test plan.

## Rules

- **Test first.** Write a failing test, make it pass, then tidy. Bug fixes start with a test that reproduces
  the bug.
- **No clipboard content in logs.** Use `os.Logger` with counts, kinds and error types only. `scripts/privacy-check.sh`
  enforces the basics in CI; reviewers check the rest.
- **No networking.** ClipFlow has no network code. A change that adds any needs a design discussion first.
- **No new dependencies** without a strong reason.
- **No warnings.** The project treats Swift warnings as errors.
- Keep changes focused; update docs and `CHANGELOG.md` when behavior changes.

## Pull requests

1. Fork, branch from `main`.
2. `make test` passes locally.
3. Fill in the PR template, including how you tested any UI changes by hand.

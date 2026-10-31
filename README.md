# Clipboard

Clipboard history for macOS: press **⇧⌘V**, find anything you copied, and paste it where you were working.
Like Windows' Win + V, built natively for the Mac.

- **Local and encrypted.** History stays on your Mac, encrypted with a key kept in your Keychain.
- **No account, no network, no tracking.** The app contains no networking code at all.
- **Keyboard first.** Search, arrow keys, Return to paste, ⌘1–⌘9 for the first nine items.
- **Text, rich text, links, code, images and files**, with pinning, filters and automatic cleanup.
- **Careful with secrets.** Items that password managers mark as concealed are never saved; things that
  look like API keys or passwords are hidden and removed after an hour (configurable).

<p align="center">
  <img src="docs/images/panel-light.png" width="720" alt="Clipboard panel in light mode: search, filters, history list and a preview of exactly what will be pasted">
</p>

<p align="center">
  <img src="docs/images/panel-dark.png" width="360" alt="Clipboard panel in dark mode">
  <img src="docs/images/panel-sensitive.png" width="360" alt="A sensitive item stays hidden until you choose Reveal">
</p>

- **What you see is what you paste.** The preview shows the full item — every line, the image, every file — and
  names each format that will be pasted. Invisible or direction-changing characters are shown, not hidden.

## Requirements

- macOS 14 Sonoma or later (Apple silicon or Intel).
- To build: Xcode 26 or later (the macOS 26 SDK provides Liquid Glass; the app still runs on macOS 14+) and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

## Install

### From a release

1. Download `Clipboard-<version>.zip` from GitHub Releases and check it against the `.sha256` file:
   `shasum -a 256 Clipboard-<version>.zip`
2. Unzip and move **Clipboard.app** to `/Applications`.
3. Release builds are ad-hoc signed unless the release notes say they are notarized. macOS will refuse to
   open an un-notarized app the first time: open **System Settings › Privacy & Security** and click
   **Open Anyway** next to the Clipboard message (or run `xattr -dr com.apple.quarantine /Applications/Clipboard.app`).

### Build from source

```bash
git clone <this repository> Clipboard && cd Clipboard
brew install xcodegen
make app          # builds build/Clipboard.app (Release)
make run          # builds and opens it
```

`make test` runs the core tests, the app tests and the privacy checks. `make generate` creates
`Clipboard.xcodeproj` if you prefer to work in Xcode (the project file is generated, not committed).

Builds are ad-hoc signed, so no Apple Developer account is needed. Each rebuild changes the signature, which
means macOS forgets the Accessibility permission and the Keychain may ask again. To avoid that, create an
untracked `Config/Local.xcconfig` with a free Apple ID “Personal Team”:

```
DEVELOPMENT_TEAM = ABCDE12345
CODE_SIGN_IDENTITY = Apple Development
```

## Permissions

| Permission | Why | Without it |
|---|---|---|
| **Paste** (System Settings › Privacy & Security › Paste) — choose **Always Allow** | macOS 15.4+ asks before an app reads the clipboard. Clipboard reads it each time you copy. | Clipboard can’t record history. If macOS is set to ask every time, Clipboard stops reading rather than prompting on each copy. |
| **Accessibility** (optional) | Sends ⌘V to the app you were using, so choosing an item pastes it. | Choosing an item copies it; you press ⌘V yourself. |

Clipboard never asks for Full Disk Access, Screen Recording, Input Monitoring, or network access.

## Keyboard shortcuts

| Where | Keys | Action |
|---|---|---|
| Anywhere | ⇧⌘V (configurable) | Open or close the history panel |
| Panel | type | Search |
| Panel | move the pointer | Select the row under it (the preview follows) |
| Panel | ↑ ↓ | Move selection |
| Panel | ↩ | Paste (or copy, if automatic paste is off) |
| Panel | ⇧↩ | Copy without pasting |
| Panel | ⌘1 … ⌘9 | Choose one of the first nine items |
| Panel | ⌘P | Pin or unpin |
| Panel | ⌘⌫ | Delete |
| Panel | esc | Close |

⇧⌘V is “paste as plain text” in some apps (Chrome, Slack, VS Code). While Clipboard runs, the shortcut opens
Clipboard instead; pick another in **Settings › Shortcuts** if you rely on it. Shortcuts must include ⌘ or ⌃.

## Privacy model

- History lives in `~/Library/Application Support/Clipboard/history.sqlite` (moved there automatically from the
  pre-rename `ClipFlow` folder) (folder readable only by you,
  excluded from Time Machine).
- Every entry’s content, preview, thumbnail and source app are encrypted with AES-256-GCM. The key is a random
  256-bit key in your login Keychain. Timestamps, kind (text/link/image…), size and pin status are stored
  unencrypted so history can be sorted and cleaned up without decrypting it.
- **Clear Everything** deletes the database *and* the key. Deleted data can’t be recovered — by you either.
- There is no recovery if the Keychain item is lost. That is deliberate.
- Clipboard does not protect against malware already running as your user: such software can read the live
  clipboard and your unlocked Keychain directly.

Details: [docs/SECURITY_MODEL.md](docs/SECURITY_MODEL.md) and [PRIVACY.md](PRIVACY.md).

## Known limitations

- Only copies made while Clipboard is running are recorded.
- “Ignore copies made in these apps” uses the app in front at the time of the copy. macOS doesn’t say which app
  wrote to the clipboard, so this is best-effort.
- Secret detection is a heuristic. It will miss some secrets and flag some harmless text.
- Some apps enable Secure Input (password fields, Terminal’s Secure Keyboard Entry); whether the global shortcut
  still works then has not been verified yet. The menu bar icon always works.
- Text over 2 MB, images over 10 MB (as PNG) and more than 1,000 files in one copy are skipped.

## Roadmap

- **Now (0.1):** macOS app — capture, encrypted history, search and filters, pinning, retention, privacy controls.
- **Next:** import/export (encrypted), per-item preview pane, more file-type previews.
- **Later:** iPhone and iPad companion with end-to-end-encrypted iCloud sync (opt-in). iOS doesn’t allow
  background clipboard monitoring, so the phone app will capture on request. See
  [docs/ARCHITECTURE.md §9](docs/ARCHITECTURE.md).

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Security issues: see [SECURITY.md](SECURITY.md) — please don’t open
public issues for vulnerabilities.

## License

[MIT](LICENSE)

# Clipboard

**Clipboard history for macOS.** Press **⇧⌘V** anywhere to see everything you've copied, search it, and paste
any item back into the app you were using. It works like Windows' Win + V, built natively for the Mac.

[![CI](https://github.com/ChakriOriginals/Clipboard/actions/workflows/ci.yml/badge.svg)](https://github.com/ChakriOriginals/Clipboard/actions/workflows/ci.yml)
![macOS 14+](https://img.shields.io/badge/macOS-14%2B-black?logo=apple)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue)](LICENSE)

<p align="center">
  <a href="docs/media/clipboard-demo.mp4">
    <img src="docs/media/clipboard-demo.gif" width="720" alt="Clipboard in 21 seconds: press ⇧⌘V, search your history, catch a file name with a hidden character, reveal a masked password">
  </a>
  <br>
  <sub><a href="docs/media/clipboard-demo.mp4">Watch the 21-second video with sound</a></sub>
</p>

## What it does

Clipboard runs in the menu bar and keeps a history of what you copy, from text and links to images and copied
files. Open the panel with ⇧⌘V, type a few letters to find an item, and press Return to paste it
where you were working.

- **The preview shows exactly what will be pasted.** You see every line, the full image and every file, plus the
  formats that will go to the other app. Invisible and direction-changing characters appear as `⟨U+202E⟩`,
  so you can spot a file that looks like `invoice_ppa.pdf` but is really `invoice_‮fdp.app`.
- **Secrets stay hidden.** Items that password managers mark as concealed are never saved. Text that looks
  like an API key or password is masked until you click **Reveal**, and removed after an hour by default.
- **Your history stays on your Mac.** It is encrypted with a key kept in your Keychain. There is no account or
  tracking, and the app contains no networking code.
- **Keyboard first.** Search as you type, move with the arrow keys, press Return to paste, or press ⌘1–⌘9 to
  choose one of the first nine items. Pin items you reuse.

<p align="center">
  <img src="docs/images/panel-light.png" width="720" alt="The Clipboard panel: search field, filters, the history list on the left and a preview of the selected item on the right">
</p>
<p align="center">
  <img src="docs/images/panel-dark.png" width="360" alt="The panel in dark mode">
  <img src="docs/images/panel-sensitive.png" width="360" alt="A sensitive item is hidden until you click Reveal">
</p>

## Install

There are no prebuilt downloads yet, so you need to build the app from source on a Mac running macOS 14 Sonoma
or later.

### 1. Install the tools

1. Install **Xcode 26 or later** from the [Mac App Store](https://apps.apple.com/app/xcode/id497799835).
   Open it once and let it finish installing its components. The Command Line Tools alone are not enough.
2. Make sure the command line uses that Xcode:

   ```bash
   xcode-select -p
   ```

   It should print a path inside `/Applications/Xcode.app`. If it prints `/Library/Developer/CommandLineTools`
   instead, switch it (this asks for your password):

   ```bash
   sudo xcode-select -s /Applications/Xcode.app
   ```

3. Install [Homebrew](https://brew.sh) if you don't have it, then install XcodeGen, which generates the
   Xcode project:

   ```bash
   brew install xcodegen
   ```

### 2. Build the app

```bash
git clone https://github.com/ChakriOriginals/Clipboard.git
cd Clipboard
make app
```

When the build finishes, you'll see `Built build/Clipboard.app`.

### 3. Move it to Applications and open it

```bash
cp -R build/Clipboard.app /Applications/
open /Applications/Clipboard.app
```

Clipboard has no Dock icon. Look for its clipboard icon in the menu bar. A welcome window explains the two
permissions below.

### 4. Allow access

| Permission | Where | Why |
|---|---|---|
| **Paste** (macOS 15.4 and later) | When macOS asks, choose **Always Allow**. To change it later: **System Settings › Privacy & Security › Paste**. | Clipboard reads the clipboard each time you copy. If macOS is set to ask every time, Clipboard stops recording instead of prompting on each copy. |
| **Keychain** | If macOS asks whether Clipboard may use its key, choose **Always Allow**. | The key that encrypts your history lives in your login Keychain. If you deny it, history stays locked until you allow it. |
| **Accessibility** (optional) | **System Settings › Privacy & Security › Accessibility**, then turn on **Clipboard**. | Lets Clipboard press ⌘V for you, so choosing an item pastes it. Without it, choosing an item copies it and you press ⌘V yourself. |

Clipboard never asks for Full Disk Access, Screen Recording, Input Monitoring or network access.

To start Clipboard automatically, turn on **Launch Clipboard at login** in **Settings › General** (menu bar icon
› Settings…).

### Coming from ClipFlow?

Clipboard used to be called ClipFlow. Quit ClipFlow first (menu bar icon › Quit), because only one copy of the
app can run at a time. Then install Clipboard as above and delete `ClipFlow.app`. Your history and
settings carry over: on first launch the data folder moves from `~/Library/Application Support/ClipFlow` to
`~/Library/Application Support/Clipboard`.

### Updating

```bash
cd Clipboard
git pull
make app
cp -R build/Clipboard.app /Applications/
```

Quit Clipboard before copying the new version over the old one. Builds made on your Mac are signed locally,
and each new build has a different signature. macOS may therefore ask for Keychain access again, and you may
need to turn Accessibility off and on for Clipboard. To avoid this, sign with a free Apple ID: create
`Config/Local.xcconfig` (it is not committed) containing your team ID from Xcode › Settings › Accounts:

```
DEVELOPMENT_TEAM = ABCDE12345
CODE_SIGN_IDENTITY = Apple Development
```

### Uninstalling

1. Turn off **Launch Clipboard at login**, then choose **Quit Clipboard** from the menu bar icon.
2. Delete `/Applications/Clipboard.app`.
3. To remove your history, its encryption key and your settings as well:

   ```bash
   rm -rf ~/Library/Application\ Support/Clipboard
   security delete-generic-password -s dev.clipflow.ClipFlow.history-key
   defaults delete dev.clipflow.ClipFlow
   ```

### Troubleshooting

| Problem | Fix |
|---|---|
| `xcodebuild requires Xcode, but active developer directory … is a command line tools instance` | Run `sudo xcode-select -s /Applications/Xcode.app` (step 1). |
| `xcodegen: command not found` | Run `brew install xcodegen`. |
| A build error mentions `NSGlassEffectView` | Your Xcode is older than 26. Update it from the App Store. |
| Clipboard quits right after opening | Another copy is running, usually an old ClipFlow or an earlier build. Quit it from its menu bar icon and open Clipboard again. |
| Nothing is recorded | Check **System Settings › Privacy & Security › Paste** and choose **Always Allow** for Clipboard. If the menu shows **Resume Monitoring**, choose it. |
| Return copies but doesn't paste | Turn on Accessibility for Clipboard. After a rebuild, turn it off and on again. |
| The panel says history is locked | Clipboard couldn't read its Keychain key. Click **Try Again** and choose **Always Allow**. |

## Using Clipboard

| Where | Keys | Action |
|---|---|---|
| Anywhere | ⇧⌘V (you can change it) | Open or close the history panel |
| Panel | type | Search |
| Panel | ↑ ↓, or move the pointer | Select an item (the preview follows) |
| Panel | ↩ | Paste the item (or copy it, if automatic paste is off) |
| Panel | ⇧↩ | Copy without pasting |
| Panel | ⌘1 … ⌘9 | Choose one of the first nine items |
| Panel | ⌘P | Pin or unpin |
| Panel | ⌘⌫ | Delete |
| Panel | esc | Close |

Some apps (Chrome, Slack and VS Code among them) use ⇧⌘V for "paste as plain text". While Clipboard runs, the
shortcut opens Clipboard instead. If you rely on it, pick another shortcut in **Settings › Shortcuts**.

In **Settings** you can also choose how long items are kept (30 days by default, up to 10,000 items), what
happens to possible secrets, which apps to ignore, and whether to record images and file references. Pinned
items are never removed automatically.

## Privacy and security

- History is stored in `~/Library/Application Support/Clipboard/history.sqlite`. The folder is readable only by
  you and excluded from Time Machine.
- Each item's content, preview, thumbnail and source app are encrypted with AES-256-GCM using a random 256-bit
  key in your login Keychain. Timestamps, item kind, size and pin status are stored unencrypted so history can
  be sorted and cleaned up without decrypting it.
- **Clear Everything** (menu bar icon › Clear History…) deletes the database and the key, so Clipboard cannot
  restore the old history. If the Keychain item is lost, the history can't be recovered either.
- Restored secrets are marked so other clipboard tools skip them, and they stay on this Mac instead of syncing
  to your other devices through Universal Clipboard.
- Clipboard can't protect you from malware already running as your user. Such software can read the live
  clipboard directly, and your Keychain while you're logged in.

The full threat model is in [docs/SECURITY_MODEL.md](docs/SECURITY_MODEL.md), with security audit reports in
[docs/security-audit](docs/security-audit/README.md) and data handling in [PRIVACY.md](PRIVACY.md).

## Limitations

- Only copies made while Clipboard is running are recorded.
- "Ignore copies made in these apps" uses the app that was in front during the copy. macOS doesn't say which
  app wrote to the clipboard, so this is best effort.
- Secret detection is a heuristic. It misses some secrets and flags some harmless text.
- It hasn't been tested whether the global shortcut works while an app uses Secure Input (password fields, or
  Terminal's Secure Keyboard Entry). The menu bar icon always works.
- A single copy is skipped if it holds more than 2 MB of text, an image over 10 MB as PNG or more than
  1,000 files. Unpinned history is limited to 2 GB in total, and the oldest items go first.

## Roadmap

- **Now:** the macOS app described above.
- **Next:** signed and notarized downloads on the Releases page, and encrypted import and export.
- **Later:** an iPhone and iPad companion with opt-in, end-to-end encrypted iCloud sync. iOS doesn't allow
  background clipboard monitoring, so the phone app will capture on request. See
  [docs/ARCHITECTURE.md §9](docs/ARCHITECTURE.md).

## Development

```bash
make test        # core tests, app tests and privacy checks
make generate    # creates Clipboard.xcodeproj to work in Xcode (the project file isn't committed)
make run         # builds the Release app and opens it
```

The app is split into `Packages/ClipboardCore` (storage, encryption, capture rules and search, with no AppKit)
and the `Clipboard` app target (menu bar, panel, settings). Start with
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md), and see [CONTRIBUTING.md](CONTRIBUTING.md) before opening a pull
request. Please report security issues privately as described in [SECURITY.md](SECURITY.md).

## License

[MIT](LICENSE)

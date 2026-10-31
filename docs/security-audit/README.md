# Security audits

Clipboard has had two source-code security audits. Both looked for ways another app on your Mac, a web page or a
copy of the history file could read your history, change what gets pasted, or slow down or crash the app.

| Audit | Date | Scope | Result |
|---|---|---|---|
| First | 2026-10-30 | The whole app before the first release | 11 possible issues, all fixed before release. None exposed history in plain text. |
| Second | 2026-10-31 | The redesign and the rename to Clipboard | 18 possible issues. 15 are fixed and 2 partly fixed. The last one concerns GitHub release settings, not the app. |

What the fixes cover, in short:

- **Existing history.** The rename kept the encryption settings, so history from the previous version still opens.
- **The preview.** It shows invisible and control characters and keeps up with the item you're looking at.
- **Secrets.** A revealed item is hidden again when you move away or reopen the panel, and it can't be copied
  from the preview.
- **Heavy copies.** Very large or crafted copies are rejected before they can tie up the app or fill the disk.
- **Clearing history.** Clear Everything also removes copies still being saved.
- **Releases.** Packaging refuses builds that allow debugging or contain test instrumentation.

The full list of changes is in [CHANGELOG.md](../../CHANGELOG.md), and the threat model is in
[SECURITY_MODEL.md](../SECURITY_MODEL.md). To report a problem, see [SECURITY.md](../../SECURITY.md).

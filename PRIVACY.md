# Privacy

Clipboard is built so that your clipboard stays yours.

**What Clipboard stores:** items you copy while it runs — text, rich text, links, code, images (as PNG, plus a
small thumbnail) and references to files (their paths, never their contents) — together with when you copied
them, their type and size, whether you pinned them, and the app that was in front when you copied.

**Where:** only on your Mac, in `~/Library/Application Support/Clipboard/`. The folder is excluded from Time
Machine. Content, previews, thumbnails and app names are encrypted with a key that lives in your login Keychain.

**What Clipboard never does:**
- send anything over the network (the app contains no networking code);
- collect analytics, crash reports or usage data;
- save items that password managers mark as concealed or transient;
- write clipboard content to system logs;
- open links or files unless you choose “Open”.

**What you control:** pause monitoring, exclude apps, choose how long history is kept, choose whether possible
secrets are saved (hidden and removed after a set time) or not saved at all, delete single items, clear
unpinned items, or **Clear Everything**, which deletes the history file and its encryption key.

**Limits:** deleted data may survive in places Clipboard doesn’t control (for example SSD blocks or manual
backups of your Library folder), but only as ciphertext; Clear Everything destroys the key that could decrypt
it. Anyone who can use your unlocked Mac can open your history, just as they could read your clipboard.

**Future sync:** if sync is added, it will be opt-in, end-to-end encrypted, and use your own iCloud account.
This document will be updated before any such release.

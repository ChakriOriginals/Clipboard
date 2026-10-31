# Clipboard — Security Model

Status: Draft for approval · Date: 2026-10-30

## 1. Assets

Clipboard history: passwords, tokens, private keys, personal messages, confidential documents, images,
file paths. The history encryption key. The user's trust that a "clipboard manager" is not a keylogger
with a nicer UI.

## 2. Threat model

| Adversary | In scope? | Mitigation |
|---|---|---|
| Someone who obtains a copy of the history file (stolen backup, synced folder, disk image, forensic copy without the user's login keychain) | **Yes** | Per-row AES-GCM; key only in Keychain; DB excluded from Time Machine. |
| Another user account on the same Mac | **Yes** | `0700` directory, `0600` file, key in this user's login keychain. |
| Malicious clipboard content (crafted RTF/HTML, huge payloads, weird file URLs, `javascript:` links) | **Yes** | Type allowlist, size caps, no HTML rendering, RTF parsed only via AppKit with a size cap and only when no plain text exists, URLs opened only on explicit action and only `http`/`https`, file contents never read. |
| Shoulder-surfing the panel | Partially | Sensitive items masked; Reveal is explicit and lasts only for that selection and that opening of the panel. A masked item is not decrypted for the preview and shows no size or shape. |
| Accidental leakage via logs or crash reports | **Yes** | No content in logs; no third-party crash reporting; no network code. |
| Malware running as the same user with Keychain access or Accessibility | **No** | Out of scope: it can read the live pasteboard and the unlocked keychain directly. Stated honestly in README. |
| Physical attacker with the unlocked, logged-in Mac | **No** | They can open the panel. FileVault and the screen lock are the defense. |
| Compromised build toolchain / dependencies | Partially | Zero third-party runtime dependencies; CI pins actions by SHA. |

## 3. Cryptography

- **Master key:** 256-bit random (`SymmetricKey(size: .bits256)`), created at first launch.
- **Subkeys (HKDF-SHA256, salt = "ClipFlow.v1", frozen since 0.1.0):** `encKey` (info "enc"), `hashKey` (info "hash").
- **Encryption:** `AES.GCM.seal(plaintext, using: encKey, authenticating: aad)`; random 96-bit nonce per seal
  (CryptoKit default); stored as the combined representation (nonce ‖ ciphertext ‖ tag).
- **AAD:** `"summary:" + id` or `"content:" + id`, so ciphertexts cannot be swapped between rows or
  columns without detection.
- **Content hash for dedup:** `HMAC-SHA256(hashKey, kind ‖ 0x00 ‖ canonical bytes)`, where canonical bytes are
  the plain text (UTF-8) for text kinds, PNG bytes for images, and the newline-joined file URLs for files.
  Keyed so the plaintext hash column cannot be used to confirm guesses of short secrets.
- **Canary:** `meta.canary` = seal("ClipFlow canary v1", aad "canary"). Open fails → wrong/missing key.
- **Nonce budget:** random nonces are safe far beyond 2³² seals per key; history never approaches this.

Plaintext columns (by design, to allow sorting, retention and dedup without decryption): id, kind,
timestamps, pinned/sensitive flags, device id, byte size, keyed hash. These leak *activity patterns*
(when and what kind of thing was copied, how big), not content.

## 4. Key lifecycle

| Event | Behavior |
|---|---|
| First launch | Generate key; store as a generic password in the login (file-based) keychain: service `<bundle id>.history-key`, account `v1`, not synchronizable. (Accessibility classes such as `…ThisDeviceOnly` do not apply to the file-based keychain — TN3137.) |
| Normal launch | Load key; verify canary. |
| Key exists but cannot be read (user denied the ACL prompt, `errSecAuthFailed`, `errSecInteractionNotAllowed`, any status other than success / `errSecItemNotFound`) | **Locked state**: do not capture, do not open or modify the DB, do not create a key. Menu shows "History locked — Keychain access was denied" with **Retry**. No data loss. |
| Key not found (`errSecItemNotFound`), DB has data | Rename DB to `history.unreadable-<timestamp>.sqlite`, create fresh DB + key, notify user. Never delete the old file automatically. |
| Key present, canary fails | Same as above. |
| Clear Everything | Close DB, delete DB file, delete key from Keychain, create fresh key and DB (crypto-shred). |
| Rebuild with a different signature | Legacy keychain ACL may prompt; user chooses Always Allow. No data loss. |
| Rotation | Not automatic. "Clear Everything" is the rotation mechanism for v1. |

**Backup behavior:** the app-support directory is excluded from Time Machine. The login keychain *is*
backed up by Time Machine (encrypted by the login password). Because the DB is excluded, a backup alone
does not contain history. Manual copies of `~/Library` would contain both — documented.

**Recovery limitations:** there is no recovery. Lose the Keychain item → lose history. This is deliberate
and documented in README and PRIVACY.md.

**Migration:** schema migrations via `user_version`. A future crypto change bumps the AAD/`info` version
(`v2`) and re-encrypts rows in a migration transaction.

## 5. Sensitive content

**Never captured** (any one marker type present):
`org.nspasteboard.ConcealedType`, `org.nspasteboard.TransientType`, `org.nspasteboard.AutoGeneratedType`,
`com.agilebits.onepassword`, `de.petermaurer.TransientPasteboardType`, `com.typeit4me.clipping`,
`Pasteboard generator type`, `net.antelle.keeweb`.

**Heuristic detection** (local, pure function, plain text only):
1. PEM private key blocks (`-----BEGIN … PRIVATE KEY-----`).
2. Known token formats: AWS access key (`AKIA[0-9A-Z]{16}`), GitHub (`ghp_`, `gho_`, `ghu_`, `ghs_`,
   `github_pat_`), GitLab `glpat-`, Slack `xox[abprs]-`, Stripe `sk_live_` / `rk_live_`, OpenAI/Anthropic
   `sk-…` (≥ 20 chars), Google API `AIza…` (39 chars), JWT (`eyJ…\.eyJ…\.…`).
3. Credential assignments: `(password|passwd|pwd|secret|token|api[_-]?key)\s*[:=]\s*\S+`.
4. Password-like: single line, no whitespace, 8–128 chars, not a URL/email/path, ≥ 3 of 4 character
   classes, Shannon entropy ≥ 3.0 bits/char.

Heuristics are a convenience, not a defense. False positives are expected: users can toggle "Mark as not
sensitive"; false negatives are possible: users can mark sensitive, delete, or pause.

**Handling** (setting): *Save, mask, expire* (default) — stored encrypted like everything else; the real
preview stays inside the encrypted summary and is masked at display time ("Sensitive item — hidden"),
in the accessibility label, and in the search index; thumbnails are not shown. "Mark as (not) sensitive"
toggles all of this both ways. Expired sensitive items disappear from the panel and cannot be restored the
moment they expire; the deletion sweep runs every minute. Restored sensitive items carry
`org.nspasteboard.ConcealedType` so other clipboard tools skip them. Or *Don't save*.

## 6. Input handling rules

- Read only allowlisted flavors; check `data.count` before decoding; skip, never truncate. The per-change
  item, byte and text caps are enforced while reading, so an oversized change is never fully read or
  RTF-parsed on the main thread.
- File URLs: accept only `file://` URLs that parse; store the URL and display the last path component.
  Never read, stat for content, or open files.
- URLs: "Open" only for `http`/`https` schemes, only via explicit user action, via `NSWorkspace.open`.
- HTML: stored as opaque bytes for restore; never rendered or parsed by `NSAttributedString`
  (which would spin up WebKit).
- RTF: parsed via AppKit only to derive a preview when no plain text exists; capped at 2 MB.
- Images: decoded with ImageIO for thumbnailing; capped at 10 MB encoded and 100 megapixels per image, with
  overflow-checked, positive-only dimension math. TIFF for other apps is produced lazily on request and only
  for the first image of a restore only, up to 25 megapixels. All TIFFs in one change share one 100-megapixel
  decode budget, checked from image headers before decoding.
- Per pasteboard change: at most 1,000 items and 100 MB across all flavors, checked again after images are
  converted to PNG; anything larger is skipped.
- HTML preview stripping is a single linear pass, and secret-detection patterns cannot backtrack
  quadratically (no backtracking regex on untrusted input).
- Capture is serialized: one snapshot is processed at a time and a flood of changes coalesces to the latest,
  so a writer cannot pile up decode work. History order uses the time the change was observed.
- Auto-paste posts ⌘V only if the pasteboard still holds Clipboard's own write and the app that was frontmost
  when the panel opened is still frontmost; a second ↩ during a restore is ignored.
- While the panel is open, new copies never insert or reorder visible rows (they update in place and appear
  when the panel reopens or the user searches), so ⌘1–9 and hover always pick what the user saw.
- What you see is what you paste: the preview shows every pasted line, the image, every file and the
  text that rides along with them, names each flavor, and shows invisible, direction-changing and control
  characters (other than tab and line breaks) as ⟨U+…⟩, in text and file names. The preview is tied to the
  exact item version it was built from and reloads when a re-copy replaces the content.
- A capture still in progress when history is cleared is dropped, not saved into the fresh history.
- Unpinned history is bounded by count, age and a 2 GB total size; deletes that free more than 64 MB
  compact the database so space is returned.
- HTML is reduced to text by a linear scanner that ends comments only at `-->` and keeps every other
  character, so the preview's escaping sees what a rich-text paste will render.
- Code: displayed as text in a monospaced font. Never executed or syntax-highlighted via external tools.

## 7. Process and platform

- Not sandboxed (auto-paste); Hardened Runtime enabled. Release builds carry no `get-task-allow` entitlement
  and no coverage instrumentation; `scripts/package-release.sh` refuses to package either.
- One instance at a time; SQLite uses a busy timeout. The live database is moved aside only when it is not
  Clipboard history for this key (canary mismatch, foreign rows, not-a-database, corrupt) — never for busy or I/O
  errors. A database written by a newer schema is refused and left untouched. Rows that fail AES-GCM
  authentication are purged; authentic rows the app does not understand are kept.
- Clear Everything also deletes `history.unreadable-*.sqlite` copies left by earlier recoveries, and on any
  failure clears in-memory history and reports the failure instead of pretending to succeed.
- No network code: CI fails if `URLSession`, `Network`, `NWConnection`, or `CFNetwork` appear in sources.
- Logging: `os.Logger(subsystem: <bundle id>)`. Messages contain only kinds, counts, byte sizes, and error
  codes; interpolations of content-derived values are forbidden (CI grep for `previewText`, `data` in log
  calls; code review).
- Feedback loops: the writer records the change count it produced; the monitor ignores it.
- Secure deletion: `secure_delete = ON` overwrites freed pages in the DB file; SSD wear-leveling and APFS
  copy-on-write mean old blocks can persist physically — mitigated because those blocks hold ciphertext
  only. "Clear Everything" destroys the key, making any residual ciphertext unreadable.

## 8. Residual risks

- Same-user malware with Accessibility/Keychain access can read history (and the live clipboard anyway).
- Settings (UserDefaults) can be edited by same-user processes; out-of-range values fall back to defaults.
- Activity metadata (timestamps, kinds, sizes) is plaintext in the DB.
- The global shortcut overrides `⌘⇧V` in other apps while registered.
- Exclusions rely on the frontmost app, which may not be the app that wrote the pasteboard.
- Heuristic detection misses unknown secret formats.

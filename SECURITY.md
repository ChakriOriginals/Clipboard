# Security Policy

Clipboard stores clipboard history, which often contains secrets. Security reports are taken seriously.

## Reporting a vulnerability

Please **don’t open a public issue**. Use GitHub’s private reporting: **Security › Report a vulnerability** on
this repository. Include the version, macOS version, steps to reproduce and the impact you expect.

You’ll get an acknowledgement within 7 days. Confirmed issues are fixed in a release and credited in
`CHANGELOG.md` unless you prefer otherwise.

## Supported versions

Only the latest release gets security fixes.

## Scope

In scope: anything that exposes clipboard history beyond what [docs/SECURITY_MODEL.md](docs/SECURITY_MODEL.md)
promises — plaintext on disk, content in logs, decryption without the Keychain key, crashes or code execution
from crafted clipboard content, opening URLs or files without an explicit user action.

Out of scope (documented limitations): malware already running as your user, an attacker with your unlocked
Mac, and the best-effort nature of app exclusions and secret detection.

Audit reports live in [docs/security-audit/](docs/security-audit/).

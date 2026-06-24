# LoginCodeDetector

LoginCodeDetector is a native macOS menu bar utility that watches an IMAP inbox for one-time login codes. It detects likely 2FA messages locally, shows a notification, and can optionally copy high-confidence codes to the clipboard.

This repository is published as source code only. No signed, notarized, or packaged `.app` release is currently provided.

## Requirements

- macOS 15 or newer
- Swift 6 / Xcode with Swift 6 support
- An IMAP account with an app password or equivalent credential

## Build and Run

```sh
swift test
swift run LoginCodeDetector
```

`swift run` starts the menu bar UI for development, but macOS notification delivery requires launching from a real `.app` bundle. The development executable disables `UNUserNotificationCenter` setup to avoid crashing outside an app bundle.

For a proper app bundle during development, open `Package.swift` in Xcode, select the `LoginCodeDetectorApp` scheme, and run it from Xcode.

## IMAP Setup

The first-run setup flow asks for an email address and app password, then tries to discover a secure IMAP server. Discovery uses provider defaults, autoconfig endpoints, and common IMAP hostnames. If discovery fails, you can enter the IMAP server manually.

The app supports:

- Implicit TLS IMAP, typically port `993`
- STARTTLS IMAP, typically port `143`
- IMAP IDLE when supported by the server
- Polling fallback when IDLE is unavailable or disabled
- One configured IMAP account with one or more watched mailboxes

Passwords are never sent until TLS is active and certificate verification has succeeded. Plaintext IMAP login is refused.

## Privacy and Storage

Code detection runs locally on message content fetched through IMAP. Credentials are stored in macOS Keychain. App settings are stored in:

```text
~/Library/Application Support/LoginCodeDetector/config.json
```

Mailbox UID state is stored in:

```text
~/Library/Application Support/LoginCodeDetector/uid-state.json
```

If auto-copy is enabled, high-confidence codes are written to the macOS clipboard. Clipboard contents are visible to other local apps with pasteboard access, so leave auto-copy disabled if that tradeoff is not acceptable.

See `PRIVACY.md` for the concise privacy statement.

## Security Notes

- Use an app-specific password when your email provider supports it.
- The app requires TLS for IMAP login.
- Logs use private OSLog formatting for runtime status messages.
- This is a local utility, not a hosted service.

To report a security issue, see `SECURITY.md`.

## Limitations

- Only one IMAP account is supported in the current UI.
- OAuth-based mail login is not supported.
- Code detection is heuristic and can miss messages or identify non-2FA messages.
- No signed release build is published yet.

## License

No license is granted. All rights reserved. See `LICENSE`.

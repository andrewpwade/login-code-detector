# LoginCodeDetector

Native macOS menu bar utility for watching an IMAP inbox for one-time codes.

## Requirements

- macOS 15 or newer
- Swift 6 / Xcode with Swift 6 support
- An IMAP account with an app password or equivalent credential

## Development

```sh
swift test
swift run LoginCodeDetector
```

`swift run` starts the menu bar UI for development, but macOS notification delivery requires launching from a real `.app` bundle. The development executable disables `UNUserNotificationCenter` setup to avoid crashing outside an app bundle.

For a real app bundle, open `Package.swift` in Xcode, select the `LoginCodeDetectorApp` scheme, and run it from Xcode. That launches the app as a proper macOS bundle so notifications work.

No signed release build is published yet.

## IMAP Setup

The getting started wizard can discover the IMAP server from your email address and app password. It tries provider defaults, autoconfig endpoints, and common IMAP hostnames, then verifies the account before asking which mailboxes to watch.

You can still enter your IMAP username, app password, server, port, and mailboxes manually in Preferences. The app supports implicit TLS IMAP, typically on port `993`, and STARTTLS on port `143`. It uses IMAP IDLE when available and falls back to polling.

The configuration is stored as an account list for future multi-account support, but the app currently watches only the first account.

Codes are parsed locally. Credentials are stored in macOS Keychain.

## Privacy

Mail is read over IMAP and code detection runs locally. Credentials are stored in macOS Keychain. App settings are stored in `~/Library/Application Support/LoginCodeDetector/config.json`.

If auto-copy is enabled, high-confidence codes are written to the macOS clipboard.

## Limitations

Only one account is currently supported. IMAP is the only supported mail protocol. Code detection is heuristic and may miss some messages or identify non-2FA messages.

## License

No license is granted. All rights reserved.

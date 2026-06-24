# Privacy

LoginCodeDetector is a local macOS utility. It connects directly from your Mac to your configured IMAP server.

- Email message content is fetched over IMAP only for watched mailboxes.
- Code detection runs locally on your Mac.
- IMAP credentials are stored in macOS Keychain.
- App settings and mailbox UID state are stored under `~/Library/Application Support/LoginCodeDetector/`.
- No analytics, telemetry, or third-party tracking is implemented.
- If auto-copy is enabled, detected codes are written to the macOS clipboard.

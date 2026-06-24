# Security Policy

## Supported Versions

This repository currently supports the latest source version on the default branch. No signed binary releases are published.

## Reporting a Vulnerability

Please do not open a public GitHub issue for credential handling, TLS, parser, or data-exposure vulnerabilities.

Report security concerns privately to the repository owner. Include:

- A concise description of the issue
- Steps to reproduce, if available
- Impact and affected files or versions
- Any suggested fix or mitigation

## Security Posture

LoginCodeDetector stores IMAP credentials in macOS Keychain and refuses to send passwords before TLS is active and verified. Message parsing and code detection run locally. If auto-copy is enabled, detected codes are placed on the macOS clipboard, which can be read by other local apps with pasteboard access.

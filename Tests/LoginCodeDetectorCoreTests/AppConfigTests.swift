import Foundation
import XCTest
@testable import LoginCodeDetectorCore

final class AppConfigTests: XCTestCase {
    func testNormalizedClampsUserEditableValues() {
        let config = AppConfig(
            accounts: [
                IMAPAccountConfig(
                    username: " user@example.com ",
                    host: " imap.example.com ",
                    port: 70_000,
                    mailboxes: [" INBOX ", " inbox ", " Codes ", " ", "Bad\nMailbox"]
                )
            ],
            pollingIntervalSeconds: 1,
            startupLookbackSeconds: 1,
            maximumStartupMessages: -1,
            allowlistedSenders: [" security@example.com ", " "],
            minimumNotificationScore: 120,
            minimumAutoCopyScore: -10
        ).normalized()

        XCTAssertEqual(config.accounts, [
            IMAPAccountConfig(username: "user@example.com", host: "imap.example.com", port: 65_535, security: .implicitTLS, mailboxes: ["INBOX", "Codes"])
        ])
        XCTAssertEqual(config.pollingIntervalSeconds, 10)
        XCTAssertEqual(config.startupLookbackSeconds, 30 * 60)
        XCTAssertEqual(config.maximumStartupMessages, 0)
        XCTAssertEqual(config.allowlistedSenders, ["security@example.com"])
        XCTAssertEqual(config.minimumNotificationScore, 100)
        XCTAssertEqual(config.minimumAutoCopyScore, 0)
    }

    func testNormalizedAddsEmptyFirstAccount() {
        let config = AppConfig(accounts: []).normalized()

        XCTAssertEqual(config.accounts, [IMAPAccountConfig()])
    }

    func testPortNormalizationUpdatesWellKnownSecurityMode() {
        let implicit = IMAPAccountConfig(port: 993).normalized()
        let startTLS = IMAPAccountConfig(port: 143).normalized()

        XCTAssertEqual(implicit.security, .implicitTLS)
        XCTAssertEqual(startTLS.security, .startTLS)
    }

    func testTopLevelUsernameDecodesAsFirstAccountUsername() throws {
        let data = Data("""
        {
          "emailAddress": " user@example.com ",
          "mailboxes": ["Codes", " INBOX "]
        }
        """.utf8)

        let config = try JSONDecoder().decode(AppConfig.self, from: data)

        XCTAssertEqual(config.accounts, [
            IMAPAccountConfig(username: "user@example.com", host: "", port: 993, security: .implicitTLS, mailboxes: ["Codes", "INBOX"])
        ])
    }

    func testTopLevelHostPortConfigDecodesAsFirstAccount() throws {
        let data = Data("""
        {
          "username": " user ",
          "host": " imap.example.com ",
          "port": 0,
          "mailboxes": []
        }
        """.utf8)

        let config = try JSONDecoder().decode(AppConfig.self, from: data)

        XCTAssertEqual(config.accounts, [
            IMAPAccountConfig(username: "user", host: "imap.example.com", port: 1, security: .implicitTLS, mailboxes: ["INBOX"])
        ])
    }

    func testModernAccountsDecodeUnchangedExceptNormalization() throws {
        let data = Data("""
        {
          "accounts": [
            {
              "username": " user ",
              "host": " imap.example.com ",
              "port": 993,
              "mailboxes": [" INBOX ", "Codes"]
            }
          ]
        }
        """.utf8)

        let config = try JSONDecoder().decode(AppConfig.self, from: data)

        XCTAssertEqual(config.accounts, [
            IMAPAccountConfig(username: "user", host: "imap.example.com", port: 993, security: .implicitTLS, mailboxes: ["INBOX", "Codes"])
        ])
    }
}

import Foundation
import XCTest
@testable import LoginCodeDetectorCore

final class IMAPClientSecurityTests: XCTestCase {
    func testConnectRejectsHostWithControlCharacters() async {
        let client = IMAPClient(
            account: IMAPAccount(
                host: "imap.example.com\nmalicious",
                port: 993,
                username: "user@example.com",
                password: "password",
                mailbox: "INBOX"
            )
        )

        do {
            try await client.connect()
            XCTFail("Expected connect() to throw")
        } catch let error as IMAPError {
            guard case .invalidInput = error else {
                XCTFail("Expected invalidInput, got \(error)")
                return
            }
        } catch {
            XCTFail("Expected IMAPError.invalidInput, got \(error)")
        }
    }

    func testSelectMailboxRejectsControlCharacters() async {
        let client = IMAPClient(
            account: IMAPAccount(
                host: "imap.example.com",
                port: 993,
                username: "user@example.com",
                password: "password",
                mailbox: "Bad\nMailbox"
            )
        )

        do {
            try await client.selectMailbox()
            XCTFail("Expected selectMailbox() to throw")
        } catch let error as IMAPError {
            guard case .invalidInput = error else {
                XCTFail("Expected invalidInput, got \(error)")
                return
            }
        } catch {
            XCTFail("Expected IMAPError.invalidInput, got \(error)")
        }
    }
}

import Foundation
import XCTest
@testable import LoginCodeDetectorCore

final class UIDStateStoreTests: XCTestCase {
    func testPersistsHighestUIDByMailbox() async throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "uid-\(UUID().uuidString).json")
        let store = UIDStateStore(fileURL: url)

        try await store.markSeen(uid: 42, mailbox: "INBOX")
        try await store.markSeen(uid: 12, mailbox: "INBOX")

        let reloaded = UIDStateStore(fileURL: url)
        let value = await reloaded.lastSeenUID(mailbox: "INBOX")

        XCTAssertEqual(value, 42)
    }

    func testPersistsUIDsByAccountIdentityAndMailbox() async throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "uid-\(UUID().uuidString).json")
        let store = UIDStateStore(fileURL: url)
        let first = MailWatcherAccount(username: "user@example.com", host: "imap.example.com", mailbox: "INBOX")
        let second = MailWatcherAccount(username: "user@example.org", host: "imap.example.org", mailbox: "INBOX")

        try await store.markSeen(uid: 9000, account: first)
        try await store.markSeen(uid: 12, account: second)

        let reloaded = UIDStateStore(fileURL: url)
        let firstValue = await reloaded.lastSeenUID(account: first)
        let secondValue = await reloaded.lastSeenUID(account: second)

        XCTAssertEqual(firstValue, 9000)
        XCTAssertEqual(secondValue, 12)
    }

    func testMailboxResetClearsScopedAndLegacyState() async throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "uid-\(UUID().uuidString).json")
        let store = UIDStateStore(fileURL: url)
        let account = MailWatcherAccount(username: "user@example.com", host: "imap.example.com", mailbox: "INBOX")

        try await store.markSeen(uid: 42, mailbox: "INBOX")
        try await store.markSeen(uid: 9000, account: account)
        try await store.reset(mailbox: "INBOX")
        let legacyValue = await store.lastSeenUID(mailbox: "INBOX")
        let scopedValue = await store.lastSeenUID(account: account)

        XCTAssertEqual(legacyValue, 0)
        XCTAssertEqual(scopedValue, 0)
    }
}

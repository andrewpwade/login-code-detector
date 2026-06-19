import Foundation
import XCTest
@testable import LoginCodeDetectorCore

final class AppEventReducerTests: XCTestCase {
    func testConnectedIdleSetsIdleStatusAndLogsIt() {
        let account = MailWatcherAccount(username: "user@example.com", host: "imap.example.com", mailbox: "INBOX")

        let result = AppEventReducer.reduce(
            state: AppRuntimeState(status: "Connecting"),
            event: .connected(account: account, mode: .idle),
            config: AppConfig(),
            now: Date(),
            recentNotificationLifetime: 60
        )

        XCTAssertEqual(result.state.status, "Connected with IMAP IDLE")
        XCTAssertEqual(result.commands, [.log("Connected with IMAP IDLE")])
    }

    func testConnectedPollingSetsPollingStatusAndLogsIt() {
        let account = MailWatcherAccount(username: "user@example.com", host: "imap.example.com", mailbox: "Codes")

        let result = AppEventReducer.reduce(
            state: AppRuntimeState(status: "Connecting"),
            event: .connected(account: account, mode: .polling),
            config: AppConfig(),
            now: Date(),
            recentNotificationLifetime: 60
        )

        XCTAssertEqual(result.state.status, "Connected with polling")
        XCTAssertEqual(result.commands, [.log("Connected with polling")])
    }

    func testCodeDetectedUpdatesStateAndReturnsDeliveryCommand() {
        let account = MailWatcherAccount(username: "user@example.com", host: "imap.example.com", mailbox: "INBOX")
        let notification = CodeNotification(code: "123456", sender: "security@example.com", subject: "Code", receivedAt: Date(timeIntervalSince1970: 100), score: 95)
        let result = AppEventReducer.reduce(
            state: AppRuntimeState(status: "Connecting"),
            event: .codeDetected(account: account, notification: notification),
            config: AppConfig(autoCopyToClipboard: true, minimumAutoCopyScore: 90),
            now: Date(timeIntervalSince1970: 120),
            recentNotificationLifetime: 60
        )

        XCTAssertEqual(result.state.lastNotification, notification)
        XCTAssertEqual(result.state.recentNotifications, [notification])
        XCTAssertEqual(
            result.commands,
            [
                .log("Notification ready with score 95"),
                .deliverNotification(notification, autoCopy: true)
            ]
        )
    }

    func testTransientFailureSetsErrorStatusAndLogsGenericMessage() {
        let account = MailWatcherAccount(username: "user@example.com", host: "imap.example.com", mailbox: "Codes")
        let result = AppEventReducer.reduce(
            state: AppRuntimeState(status: "Connected"),
            event: .transientFailure(account: account, message: "Timed out"),
            config: AppConfig(),
            now: Date(),
            recentNotificationLifetime: 60
        )

        XCTAssertEqual(result.state.status, "Error: Timed out")
        XCTAssertEqual(result.commands, [.log("Watcher transient failure: Timed out")])
    }

    func testStatusEventUpdatesStatusAndLogsGenericMessage() {
        let account = MailWatcherAccount(username: "user@example.com", host: "imap.example.com", mailbox: "Alerts")

        let result = AppEventReducer.reduce(
            state: AppRuntimeState(status: "Connecting"),
            event: .status(account: account, message: "Reconnecting"),
            config: AppConfig(),
            now: Date(),
            recentNotificationLifetime: 60
        )

        XCTAssertEqual(result.state.status, "Reconnecting")
        XCTAssertEqual(result.commands, [.log("Watcher status updated")])
    }

    func testStoppedEventPreservesStatusAndLogsGenericStopMessage() {
        let account = MailWatcherAccount(username: "user@example.com", host: "imap.example.com", mailbox: "Alerts")

        let result = AppEventReducer.reduce(
            state: AppRuntimeState(status: "Monitoring"),
            event: .stopped(account: account),
            config: AppConfig(),
            now: Date(),
            recentNotificationLifetime: 60
        )

        XCTAssertEqual(result.state.status, "Monitoring")
        XCTAssertEqual(result.commands, [.log("Watcher stopped")])
    }
}

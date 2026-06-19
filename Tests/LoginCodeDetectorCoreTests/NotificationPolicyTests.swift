import Foundation
import XCTest
@testable import LoginCodeDetectorCore

final class NotificationPolicyTests: XCTestCase {
    func testShouldAutoCopyRequiresOptInAndMinimumScore() {
        let notification = CodeNotification(code: "123456", sender: "sender", subject: "subject", score: 89)
        let config = AppConfig(autoCopyToClipboard: true, minimumAutoCopyScore: 90)

        XCTAssertFalse(NotificationPolicy.shouldAutoCopy(notification: notification, config: config))
        XCTAssertFalse(NotificationPolicy.shouldAutoCopy(notification: notification, config: AppConfig(autoCopyToClipboard: false, minimumAutoCopyScore: 80)))
        XCTAssertTrue(NotificationPolicy.shouldAutoCopy(notification: CodeNotification(code: "123456", sender: "sender", subject: "subject", score: 95), config: config))
    }

    func testPrunedNotificationsRemovesExpiredItems() {
        let now = Date(timeIntervalSince1970: 1_000)
        let fresh = CodeNotification(code: "111111", sender: "sender", subject: "subject", receivedAt: now.addingTimeInterval(-30), score: 90)
        let stale = CodeNotification(code: "222222", sender: "sender", subject: "subject", receivedAt: now.addingTimeInterval(-120), score: 90)

        XCTAssertEqual(
            NotificationPolicy.prunedNotifications(from: [fresh, stale], now: now, lifetime: 60),
            [fresh]
        )
    }
}

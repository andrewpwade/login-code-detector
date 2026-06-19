import Foundation
import XCTest
@testable import LoginCodeDetectorCore

final class MIMEMessageTests: XCTestCase {
    func testParsesReceivedAtFromDateHeaderWithTimezoneComment() throws {
        let raw = """
        From: Example <noreply@example.com>
        Date: Mon, 22 Jun 2026 12:00:00 +0000 (UTC)
        Subject: Your code

        123456
        """

        let message = MIMEMessage(raw: raw)
        let receivedAt = try XCTUnwrap(message.receivedAt)

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, d MMM yyyy HH:mm:ss Z"

        let expected = try XCTUnwrap(formatter.date(from: "Mon, 22 Jun 2026 12:00:00 +0000"))
        XCTAssertEqual(receivedAt.timeIntervalSince(expected), 0, accuracy: 0.5)
    }
}

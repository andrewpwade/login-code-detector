import Foundation
import XCTest
@testable import LoginCodeDetectorCore

final class MessageEvaluatorTests: XCTestCase {
    func testEvaluateReturnsDetectedForHighConfidenceCode() {
        let evaluator = MessageEvaluator()
        let config = AppConfig(minimumNotificationScore: 70)
        let event = MailEvent(
            uid: 1,
            sender: "security@example.com",
            subject: "Your verification code",
            receivedAt: Date(),
            plainTextBody: "Use verification code 123456 to sign in."
        )

        let result = evaluator.evaluate(event: event, config: config)

        guard case let .detected(notification) = result else {
            return XCTFail("Expected detected, got \(result)")
        }
        XCTAssertEqual(notification.code, "123456")
    }

    func testEvaluateReturnsIgnoredLowScoreWhenBelowThreshold() {
        let evaluator = MessageEvaluator()
        let config = AppConfig(minimumNotificationScore: 95)
        let event = MailEvent(
            uid: 1,
            sender: "alerts@example.com",
            subject: "Code",
            receivedAt: Date(),
            plainTextBody: "Code 123456"
        )

        let result = evaluator.evaluate(event: event, config: config)

        guard case let .ignoredLowScore(detected) = result else {
            return XCTFail("Expected ignoredLowScore, got \(result)")
        }
        XCTAssertEqual(detected.code, "123456")
    }

    func testEvaluateReturnsNoCandidateWhenNoCodePresent() {
        let evaluator = MessageEvaluator()
        let config = AppConfig()
        let event = MailEvent(
            uid: 1,
            sender: "news@example.com",
            subject: "Weekly update",
            receivedAt: Date(),
            plainTextBody: "No login code is present here."
        )

        let result = evaluator.evaluate(event: event, config: config)

        XCTAssertEqual(result, .noCandidate)
    }

    func testEvaluateUsesAllowlistedSenderToPushBorderlineCodeOverThreshold() {
        let evaluator = MessageEvaluator()
        let config = AppConfig(
            allowlistedSenders: ["openai.com"],
            minimumNotificationScore: 80
        )
        let event = MailEvent(
            uid: 1,
            sender: "noreply@tm.openai.com",
            subject: "Temporary login",
            receivedAt: Date(),
            plainTextBody: "841576"
        )

        let result = evaluator.evaluate(event: event, config: config)
        let baseline = evaluator.evaluate(
            event: event,
            config: AppConfig(minimumNotificationScore: 80)
        )

        guard case let .detected(notification) = result else {
            return XCTFail("Expected detected, got \(result)")
        }
        guard case let .ignoredLowScore(ignored) = baseline else {
            return XCTFail("Expected ignoredLowScore without allowlist, got \(baseline)")
        }
        XCTAssertEqual(notification.code, "841576")
        XCTAssertGreaterThanOrEqual(notification.score, 80)
        XCTAssertLessThan(ignored.score, 80)
    }
}

import Foundation
import XCTest
@testable import LoginCodeDetectorCore

final class MailWatcherScanPolicyTests: XCTestCase {
    func testNextPlanUsesStartupPolicyBeforeFirstScan() {
        let config = AppConfig(startupLookbackSeconds: 30, maximumStartupMessages: 5)
        let plan = MailWatcherScanPolicy.nextPlan(
            didInitialScan: false,
            lastSeen: 42,
            mailbox: "INBOX",
            config: config
        )

        XCTAssertEqual(
            plan,
            MailWatcherScanPlan(
                request: .startup(lookbackSeconds: 60, maximumMessages: 5),
                statusMessages: ["Startup scan: searching only the last 1 minute(s)"]
            )
        )
    }

    func testResolveStartupScanFiltersCapsAndSortsUIDs() {
        let config = AppConfig(maximumStartupMessages: 2)
        let result = MailWatcherScanPolicy.resolveStartupScan(
            uids: [9, 12, 8, 15],
            baseline: 12,
            config: config,
            lastSeen: 4
        )

        XCTAssertEqual(result.uids, [12, 9])
        XCTAssertEqual(result.startupBaseline, 12)
        XCTAssertEqual(
            result.statusMessages,
            [
                "Stored UID was 4; startup baseline is UID 12",
                "Startup scan capped at 2 newest recent message(s)"
            ]
        )
    }

    func testResolveStartupScanDoesNotReplayAlreadySeenUIDs() {
        let config = AppConfig(maximumStartupMessages: 25)
        let result = MailWatcherScanPolicy.resolveStartupScan(
            uids: [9, 10, 11, 12],
            baseline: 12,
            config: config,
            lastSeen: 10
        )

        XCTAssertEqual(result.uids, [12, 11])
        XCTAssertEqual(result.startupBaseline, 12)
    }

    func testScanStatusMessageDescribesUIDs() {
        XCTAssertEqual(MailWatcherScanPolicy.scanStatusMessage(for: []), "No new messages")
        XCTAssertEqual(MailWatcherScanPolicy.scanStatusMessage(for: [9, 8]), "Found 2 new message(s): 9, 8")
    }
}

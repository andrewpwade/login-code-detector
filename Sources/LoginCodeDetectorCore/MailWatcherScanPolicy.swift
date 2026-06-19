import Foundation

/// Scan modes the watcher can use depending on whether it is starting fresh or continuing from stored UID state.
public enum MailWatcherScanRequest: Equatable, Sendable {
    case afterUID(UInt64)
    case startup(lookbackSeconds: Int, maximumMessages: Int)
}

/// Concrete scan request plus the user-facing status text that explains what the watcher is about to do.
public struct MailWatcherScanPlan: Equatable, Sendable {
    public let request: MailWatcherScanRequest
    public let statusMessages: [String]

    public init(request: MailWatcherScanRequest, statusMessages: [String]) {
        self.request = request
        self.statusMessages = statusMessages
    }
}

/// Outcome of the startup-only scan logic, including any baseline updates and status messaging.
public struct StartupScanResult: Equatable, Sendable {
    public let uids: [UInt64]
    public let startupBaseline: UInt64?
    public let statusMessages: [String]

    public init(uids: [UInt64], startupBaseline: UInt64?, statusMessages: [String]) {
        self.uids = uids
        self.startupBaseline = startupBaseline
        self.statusMessages = statusMessages
    }
}

/// Centralizes the rules for startup lookback scans and steady-state incremental scans.
public enum MailWatcherScanPolicy {
    public static func nextPlan(
        didInitialScan: Bool,
        lastSeen: UInt64,
        mailbox: String,
        config: AppConfig
    ) -> MailWatcherScanPlan {
        if didInitialScan {
            return MailWatcherScanPlan(
                request: .afterUID(lastSeen),
                statusMessages: ["Searching \(mailbox) after UID \(lastSeen)"]
            )
        }

        let lookback = max(AppConfigDefaults.minimumStartupSearchWindowSeconds, Int(config.startupLookbackSeconds))
        return MailWatcherScanPlan(
            request: .startup(
                lookbackSeconds: lookback,
                maximumMessages: max(0, config.maximumStartupMessages)
            ),
            statusMessages: ["Startup scan: searching only the last \(lookback / 60) minute(s)"]
        )
    }

    public static func resolveStartupScan(
        uids: [UInt64],
        baseline: UInt64,
        config: AppConfig,
        lastSeen: UInt64
    ) -> StartupScanResult {
        let filteredUIDs = Array(
            uids
                .filter { $0 > lastSeen && $0 <= baseline }
                .sorted(by: >)
                .prefix(max(0, config.maximumStartupMessages))
        )

        var messages = ["Stored UID was \(lastSeen); startup baseline is UID \(baseline)"]
        if config.maximumStartupMessages > 0 {
            messages.append("Startup scan capped at \(config.maximumStartupMessages) newest recent message(s)")
        }

        return StartupScanResult(
            uids: filteredUIDs,
            startupBaseline: baseline,
            statusMessages: messages
        )
    }

    public static func startupFailure(
        baseline _: UInt64,
        errorDescription: String
    ) -> StartupScanResult {
        StartupScanResult(
            uids: [],
            startupBaseline: nil,
            statusMessages: ["Recent startup search failed; setting baseline without scanning history: \(errorDescription)"]
        )
    }

    public static func scanStatusMessage(for uids: [UInt64]) -> String {
        uids.isEmpty
            ? "No new messages"
            : "Found \(uids.count) new message(s): \(uids.map(String.init).joined(separator: ", "))"
    }
}

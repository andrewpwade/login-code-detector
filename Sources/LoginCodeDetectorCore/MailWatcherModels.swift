import Foundation

/// Stable account identity attached to watcher events for UI and logging.
public struct MailWatcherAccount: Sendable, Equatable {
    public let username: String
    public let host: String
    public let mailbox: String

    public init(username: String, host: String, mailbox: String) {
        self.username = username
        self.host = host
        self.mailbox = mailbox
    }
}

/// Connection mode chosen for a watcher after capability negotiation.
public enum MailWatcherConnectionMode: Sendable, Equatable {
    case idle
    case polling
}

import Foundation

/// Common IMAP constants shared by setup and runtime code.
public enum IMAPDefaults {
    public static let mailbox = "INBOX"
    public static let implicitTLSPort = 993
    public static let startTLSPort = 143
}

/// Connection details for one mailbox watcher or setup session.
public struct IMAPAccount: Sendable, Equatable {
    /// Supported transport security modes for the IMAP session.
    public enum Security: String, Codable, Sendable, Equatable {
        case implicitTLS
        case startTLS
    }

    public var host: String
    public var port: Int
    public var security: Security
    public var username: String
    public var password: String
    public var mailbox: String

    public init(
        host: String,
        port: Int,
        security: Security = .implicitTLS,
        username: String,
        password: String,
        mailbox: String = IMAPDefaults.mailbox
    ) {
        self.host = host
        self.port = port
        self.security = security
        self.username = username
        self.password = password
        self.mailbox = mailbox
    }
}

/// High-level events emitted by a watcher and consumed by app state reducers.
public enum MailWatcherEvent: Sendable, Equatable {
    case connected(account: MailWatcherAccount, mode: MailWatcherConnectionMode)
    case codeDetected(account: MailWatcherAccount, notification: CodeNotification)
    case status(account: MailWatcherAccount, message: String)
    case transientFailure(account: MailWatcherAccount, message: String)
    case stopped(account: MailWatcherAccount)
}

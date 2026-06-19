import Foundation

/// Shared defaults chosen to balance fast 2FA detection against mailbox safety and false positives.
public enum AppConfigDefaults {
    public static let pollingIntervalSeconds: TimeInterval = 30
    public static let minimumPollingIntervalSeconds: TimeInterval = 10
    public static let startupLookbackSeconds: TimeInterval = 30 * 60
    public static let legacyStartupLookbackSeconds: TimeInterval = 10 * 60
    public static let minimumStartupLookbackSeconds: TimeInterval = 30 * 60
    public static let minimumStartupSearchWindowSeconds = 60
    public static let maximumStartupMessages = 25
    public static let minimumNotificationScore = 70
    public static let minimumAutoCopyScore = 90
    public static let minimumScore = 0
    public static let maximumScore = 100
}

/// User-editable IMAP account settings persisted in app configuration.
/// Normalization is intentionally opinionated so partially edited or migrated configs are coerced into a shape
/// the runtime can use without spreading validation logic across the app.
public struct IMAPAccountConfig: Codable, Equatable, Sendable {
    /// Stored keys for the persisted account configuration schema.
    private enum CodingKeys: String, CodingKey {
        case username
        case host
        case port
        case security
        case mailboxes
    }

    public var username: String
    public var host: String
    public var port: Int
    public var security: IMAPAccount.Security
    public var mailboxes: [String]

    public init(
        username: String = "",
        host: String = "",
        port: Int = IMAPDefaults.implicitTLSPort,
        security: IMAPAccount.Security = .implicitTLS,
        mailboxes: [String] = [IMAPDefaults.mailbox]
    ) {
        self.username = username
        self.host = host
        self.port = port
        self.security = security
        self.mailboxes = mailboxes
    }

    public func normalized() -> IMAPAccountConfig {
        var account = self
        account.username = account.username.trimmingCharacters(in: .whitespacesAndNewlines)
        account.host = account.host.trimmingCharacters(in: .whitespacesAndNewlines)
        account.mailboxes = uniqueMailboxes(account.mailboxes)
        if account.mailboxes.isEmpty {
            account.mailboxes = [IMAPDefaults.mailbox]
        }
        account.port = min(65_535, max(1, account.port))
        // Infer security from the standard ports so edited legacy configs stay internally consistent even if they
        // only persisted the port value.
        if account.port == IMAPDefaults.startTLSPort {
            account.security = .startTLS
        } else if account.port == IMAPDefaults.implicitTLSPort {
            account.security = .implicitTLS
        }
        return account
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.username = try container.decodeIfPresent(String.self, forKey: .username) ?? ""
        self.host = try container.decodeIfPresent(String.self, forKey: .host) ?? ""
        self.port = try container.decodeIfPresent(Int.self, forKey: .port) ?? IMAPDefaults.implicitTLSPort
        self.security = try container.decodeIfPresent(IMAPAccount.Security.self, forKey: .security) ?? .implicitTLS
        self.mailboxes = try container.decodeIfPresent([String].self, forKey: .mailboxes) ?? [IMAPDefaults.mailbox]
        self = self.normalized()
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(username, forKey: .username)
        try container.encode(host, forKey: .host)
        try container.encode(port, forKey: .port)
        try container.encode(security, forKey: .security)
        try container.encode(mailboxes, forKey: .mailboxes)
    }

    private func uniqueMailboxes(_ mailboxes: [String]) -> [String] {
        let sanitized = IMAPInputValidation.sanitizeMailboxes(mailboxes)
        return sanitized.isEmpty ? [IMAPDefaults.mailbox] : sanitized
    }
}

/// Top-level persisted app settings, including account definitions and detection thresholds.
/// The decoding path also handles schema migration so older installs can move forward without a separate
/// one-time upgrader.
public struct AppConfig: Codable, Equatable, Sendable {
    public var accounts: [IMAPAccountConfig]
    public var autoCopyToClipboard: Bool
    public var preferIMAPIdle: Bool
    public var pollingIntervalSeconds: TimeInterval
    public var startupLookbackSeconds: TimeInterval
    public var maximumStartupMessages: Int
    public var allowlistedSenders: [String]
    public var minimumNotificationScore: Int
    public var minimumAutoCopyScore: Int

    public init(
        accounts: [IMAPAccountConfig] = [IMAPAccountConfig()],
        autoCopyToClipboard: Bool = false,
        preferIMAPIdle: Bool = true,
        pollingIntervalSeconds: TimeInterval = AppConfigDefaults.pollingIntervalSeconds,
        startupLookbackSeconds: TimeInterval = AppConfigDefaults.startupLookbackSeconds,
        maximumStartupMessages: Int = AppConfigDefaults.maximumStartupMessages,
        allowlistedSenders: [String] = [],
        minimumNotificationScore: Int = AppConfigDefaults.minimumNotificationScore,
        minimumAutoCopyScore: Int = AppConfigDefaults.minimumAutoCopyScore
    ) {
        self.accounts = accounts
        self.autoCopyToClipboard = autoCopyToClipboard
        self.preferIMAPIdle = preferIMAPIdle
        self.pollingIntervalSeconds = pollingIntervalSeconds
        self.startupLookbackSeconds = startupLookbackSeconds
        self.maximumStartupMessages = maximumStartupMessages
        self.allowlistedSenders = allowlistedSenders
        self.minimumNotificationScore = minimumNotificationScore
        self.minimumAutoCopyScore = minimumAutoCopyScore
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let accounts = try container.decodeIfPresent([IMAPAccountConfig].self, forKey: .accounts) {
            self.accounts = accounts
        } else {
            // Accept the pre-multi-account schema so existing installs migrate forward without losing settings.
            let username = try container.decodeIfPresent(String.self, forKey: .username)
                ?? container.decodeIfPresent(String.self, forKey: .emailAddress)
                ?? ""
            self.accounts = [
                IMAPAccountConfig(
                    username: username,
                    host: try container.decodeIfPresent(String.self, forKey: .host) ?? "",
                    port: try container.decodeIfPresent(Int.self, forKey: .port) ?? IMAPDefaults.implicitTLSPort,
                    security: try container.decodeIfPresent(IMAPAccount.Security.self, forKey: .security) ?? .implicitTLS,
                    mailboxes: try container.decodeIfPresent([String].self, forKey: .mailboxes) ?? [IMAPDefaults.mailbox]
                )
            ]
        }
        self.autoCopyToClipboard = try container.decodeIfPresent(Bool.self, forKey: .autoCopyToClipboard) ?? false
        self.preferIMAPIdle = try container.decodeIfPresent(Bool.self, forKey: .preferIMAPIdle) ?? true
        self.pollingIntervalSeconds = try container.decodeIfPresent(TimeInterval.self, forKey: .pollingIntervalSeconds) ?? AppConfigDefaults.pollingIntervalSeconds
        self.startupLookbackSeconds = try container.decodeIfPresent(TimeInterval.self, forKey: .startupLookbackSeconds) ?? AppConfigDefaults.legacyStartupLookbackSeconds
        self.maximumStartupMessages = try container.decodeIfPresent(Int.self, forKey: .maximumStartupMessages) ?? AppConfigDefaults.maximumStartupMessages
        self.allowlistedSenders = try container.decodeIfPresent([String].self, forKey: .allowlistedSenders) ?? []
        self.minimumNotificationScore = try container.decodeIfPresent(Int.self, forKey: .minimumNotificationScore) ?? AppConfigDefaults.minimumNotificationScore
        self.minimumAutoCopyScore = try container.decodeIfPresent(Int.self, forKey: .minimumAutoCopyScore) ?? AppConfigDefaults.minimumAutoCopyScore
        normalize()
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(accounts, forKey: .accounts)
        try container.encode(autoCopyToClipboard, forKey: .autoCopyToClipboard)
        try container.encode(preferIMAPIdle, forKey: .preferIMAPIdle)
        try container.encode(pollingIntervalSeconds, forKey: .pollingIntervalSeconds)
        try container.encode(startupLookbackSeconds, forKey: .startupLookbackSeconds)
        try container.encode(maximumStartupMessages, forKey: .maximumStartupMessages)
        try container.encode(allowlistedSenders, forKey: .allowlistedSenders)
        try container.encode(minimumNotificationScore, forKey: .minimumNotificationScore)
        try container.encode(minimumAutoCopyScore, forKey: .minimumAutoCopyScore)
    }

    public mutating func normalize() {
        self = normalized()
    }

    public func normalized() -> AppConfig {
        var config = self
        config.accounts = config.accounts.map { $0.normalized() }
        if config.accounts.isEmpty {
            config.accounts = [IMAPAccountConfig()]
        }
        config.pollingIntervalSeconds = max(AppConfigDefaults.minimumPollingIntervalSeconds, config.pollingIntervalSeconds)
        // Clamp the startup lookback to a floor large enough to catch most fresh 2FA mail after relaunch while
        // still avoiding a historical mailbox replay.
        config.startupLookbackSeconds = max(AppConfigDefaults.minimumStartupLookbackSeconds, config.startupLookbackSeconds)
        config.maximumStartupMessages = max(0, config.maximumStartupMessages)
        config.allowlistedSenders = config.allowlistedSenders
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        config.minimumNotificationScore = min(AppConfigDefaults.maximumScore, max(AppConfigDefaults.minimumScore, config.minimumNotificationScore))
        config.minimumAutoCopyScore = min(AppConfigDefaults.maximumScore, max(AppConfigDefaults.minimumScore, config.minimumAutoCopyScore))
        return config
    }

    /// Stored keys for the persisted app configuration schema, including legacy migration fields.
    private enum CodingKeys: String, CodingKey {
        case accounts
        case username
        case emailAddress
        case host
        case port
        case security
        case mailboxes
        case autoCopyToClipboard
        case preferIMAPIdle
        case pollingIntervalSeconds
        case startupLookbackSeconds
        case maximumStartupMessages
        case allowlistedSenders
        case minimumNotificationScore
        case minimumAutoCopyScore
    }
}

/// Small persistence wrapper around the app config file.
/// Keeping file IO here isolates storage details from the view model and provides one place to evolve the on-disk
/// format later.
public actor ConfigStore {
    private let fileURL: URL

    public init(fileURL: URL = ConfigStore.defaultURL()) {
        self.fileURL = fileURL
    }

    public func load() -> AppConfig {
        guard
            let data = try? Data(contentsOf: fileURL),
            let config = try? JSONDecoder().decode(AppConfig.self, from: data)
        else {
            return AppConfig()
        }
        return config
    }

    public func save(_ config: AppConfig) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder.pretty.encode(config)
        try data.write(to: fileURL, options: [.atomic])
    }

    public static func defaultURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appending(path: "LoginCodeDetector/config.json")
    }
}

private extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

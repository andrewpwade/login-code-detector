import LoginCodeDetectorCore
import Foundation

/// Translates persisted account settings into concrete watcher and discovery inputs.
enum WatcherPlan {
    static func account(
        config: IMAPAccountConfig,
        password: String,
        mailbox: String? = nil
    ) -> IMAPAccount {
        IMAPAccount(
            host: config.host,
            port: config.port,
            security: config.security,
            username: config.username,
            password: password,
            mailbox: mailbox ?? config.mailboxes.first ?? IMAPDefaults.mailbox
        )
    }

    static func accounts(entries: [AccountEntry], config: AppConfig) -> [IMAPAccount] {
        entries
            .map(\.normalized)
            .filter(\.canStart)
            .flatMap { entry in
                entry.config.mailboxes.map { mailbox in
                    account(config: entry.config, password: entry.password, mailbox: mailbox)
                }
            }
    }

    static func mailboxesIncludingDefault(_ mailboxes: [String]) -> [String] {
        var result = mailboxes
        if !result.contains(where: { $0.uppercased() == IMAPDefaults.mailbox }) {
            result.insert(IMAPDefaults.mailbox, at: 0)
        }
        return result
    }

    static func discoveryFallbackAccount(
        current: IMAPAccountConfig,
        username: String,
        domain: String?
    ) -> IMAPAccountConfig {
        var account = current
        account.username = username
        if let domain, account.host.isEmpty {
            account.host = "imap.\(domain)"
        }
        account.port = IMAPDefaults.implicitTLSPort
        return account
    }
}

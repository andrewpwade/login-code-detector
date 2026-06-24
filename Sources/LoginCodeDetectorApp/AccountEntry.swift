import LoginCodeDetectorCore
import Foundation

/// Editable account draft used by the app layer before values are persisted or turned into runtime accounts.
struct AccountEntry: Identifiable, Equatable {
    let id: UUID
    var config: IMAPAccountConfig
    var password: String

    init(id: UUID = UUID(), config: IMAPAccountConfig = IMAPAccountConfig(), password: String = "") {
        self.id = id
        self.config = config
        self.password = password
    }

    var normalized: AccountEntry {
        var entry = self
        entry.config = entry.config.normalized()
        return entry
    }

    var canStart: Bool {
        let entry = normalized
        return !entry.config.host.isEmpty
            && !entry.config.username.isEmpty
            && !entry.config.mailboxes.isEmpty
            && !entry.password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var keychainKey: String? {
        let entry = normalized
        guard !entry.config.username.isEmpty, !entry.config.host.isEmpty else {
            return nil
        }
        return "\(entry.config.username)@\(entry.config.host)"
    }
}

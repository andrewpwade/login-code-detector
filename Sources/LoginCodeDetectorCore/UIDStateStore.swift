import Foundation

/// Persists the highest seen UID per mailbox so watchers can resume without replaying entire inbox histories.
public actor UIDStateStore {
    private let fileURL: URL
    private var state: [String: UInt64] = [:]
    private var loaded = false

    public init(fileURL: URL = UIDStateStore.defaultURL()) {
        self.fileURL = fileURL
    }

    public func lastSeenUID(mailbox: String) -> UInt64 {
        loadIfNeeded()
        return state[mailbox] ?? 0
    }

    public func lastSeenUID(account: MailWatcherAccount) -> UInt64 {
        loadIfNeeded()
        return state[key(for: account)] ?? state[account.mailbox] ?? 0
    }

    public func markSeen(uid: UInt64, mailbox: String) throws {
        loadIfNeeded()
        guard uid > (state[mailbox] ?? 0) else {
            // Ignore out-of-order writes so concurrent reconnect paths cannot move a mailbox cursor backwards.
            return
        }
        state[mailbox] = uid
        try save()
    }

    public func markSeen(uid: UInt64, account: MailWatcherAccount) throws {
        loadIfNeeded()
        let key = key(for: account)
        guard uid > (state[key] ?? 0) else {
            return
        }
        state[key] = uid
        try save()
    }

    public func reset(mailbox: String) throws {
        loadIfNeeded()
        state[mailbox] = 0
        for key in Array(state.keys) where key.hasSuffix("|\(mailbox)") {
            state[key] = 0
        }
        try save()
    }

    public func reset(account: MailWatcherAccount) throws {
        loadIfNeeded()
        state[key(for: account)] = 0
        try save()
    }

    public static func defaultURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appending(path: "LoginCodeDetector/uid-state.json")
    }

    private func loadIfNeeded() {
        guard !loaded else {
            return
        }
        loaded = true
        // Treat missing or corrupt state as "scan recent mail only" instead of blocking startup on local storage.
        guard let data = try? Data(contentsOf: fileURL) else {
            return
        }
        state = (try? JSONDecoder().decode([String: UInt64].self, from: data)) ?? [:]
    }

    private func save() throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(state)
        try data.write(to: fileURL, options: [.atomic])
    }

    private func key(for account: MailWatcherAccount) -> String {
        "\(account.host.lowercased())|\(account.username.lowercased())|\(account.mailbox)"
    }
}

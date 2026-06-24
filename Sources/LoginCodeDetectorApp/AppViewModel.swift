import LoginCodeDetectorCore
import AppKit
import Foundation
import OSLog

/// App-scoped timing defaults for notification history maintenance and setup networking.
private enum AppRuntimeDefaults {
    static let recentNotificationLifetimeSeconds: TimeInterval = 30 * 60
    static let recentNotificationCleanupIntervalSeconds: TimeInterval = 60
    static let connectionTimeoutSeconds: TimeInterval = 6
}

/// Steps in the first-run setup flow shown in preferences.
enum GettingStartedStep {
    case server
    case credentials
    case folders
    case done
}

@MainActor
/// Main app-facing state container for preferences, onboarding, watcher lifecycle, and notification delivery.
/// It keeps UI code declarative by centralizing the imperative edges: persistence, IMAP verification,
/// background tasks, and translation from watcher events into user-visible state.
final class AppViewModel: ObservableObject {
    @Published var config = AppConfig()
    @Published var appPassword = ""
    @Published var status = "Not connected"
    @Published var isRunning = false
    @Published var lastNotification: CodeNotification?
    @Published var recentNotifications: [CodeNotification] = []
    @Published var isVerifyingAccount = false
    @Published var shouldShowGettingStarted = false
    @Published var gettingStartedStep: GettingStartedStep = .server
    @Published var isProbingServer = false
    @Published var isLoadingMailboxes = false
    @Published var availableMailboxes: [String] = ["INBOX"]

    private let configStore = ConfigStore()
    private let keychain = KeychainStore()
    private let notifications = NotificationCoordinator()
    private let stateStore = UIDStateStore()
    private let clipboard = ClipboardService()
    private let imapDiscovery = IMAPDiscovery()
    private let logger = Logger(subsystem: "LoginCodeDetector", category: "App")
    private var recentNotificationCleanupTask: Task<Void, Never>?
    private var watchers: [MailWatcher] = []
    private var watcherTasks: [Task<Void, Never>] = []
    private var hasLoaded = false
    private var savedKeychainAccount: String?

    deinit {
        recentNotificationCleanupTask?.cancel()
    }

    func load(autoStart: Bool = true) {
        guard !hasLoaded else {
            return
        }
        hasLoaded = true
        // Load can be triggered from multiple SwiftUI lifecycle paths; make startup side effects one-shot so we
        // do not spawn duplicate cleanup loops or watchers.
        startRecentNotificationCleanup()

        Task {
            var loadedConfig = await configStore.load()
            loadedConfig.normalize()
            config = loadedConfig
            if let keychainAccount = firstAccountKey(in: config) {
                appPassword = keychain.password(for: keychainAccount) ?? ""
                savedKeychainAccount = keychainAccount
            } else {
                appPassword = ""
                savedKeychainAccount = nil
            }
            shouldShowGettingStarted = shouldShowGettingStartedFlow
            pruneRecentNotifications()
            if await notifications.requestAuthorization() {
                logDebug("Notification permission ready")
            } else {
                log("Notifications unavailable or not authorized")
            }
            logDebug("Loaded preferences")

            if autoStart, canStart {
                log("Auto-starting watcher")
                start(saveBeforeStart: false)
            } else if autoStart {
                status = "Enter IMAP server, username, and app password"
                log("Watcher not started: missing IMAP server, username, or app password")
            }
        }
    }

    func save() {
        Task {
            do {
                try await saveCurrentConfiguration()
                status = "Saved"
                log("Saved preferences")
            } catch {
                status = error.localizedDescription
                log("Save failed: \(error.localizedDescription)")
            }
        }
    }

    func verifyAccountAndStart() {
        guard canStart else {
            status = "Enter IMAP server, username, and app password"
            log(status)
            return
        }

        let normalizedConfig = config.normalized()
        let accountConfig = normalizedConfig.accounts[0]
        let account = WatcherPlan.account(config: accountConfig, password: appPassword)

        isVerifyingAccount = true
        status = "Verifying IMAP account"
        log("Verifying IMAP account")

        Task {
            let client = IMAPClient(account: account)
            do {
                try await client.connect()
                try await client.login()
                for mailbox in accountConfig.mailboxes {
                    try await client.selectMailbox(mailbox)
                }
                await client.disconnect()
                config = normalizedConfig
                try await saveCurrentConfiguration()
                shouldShowGettingStarted = false
                isVerifyingAccount = false
                status = "Account verified"
                logDebug("IMAP account verified")
                start(saveBeforeStart: false)
            } catch {
                await client.disconnect()
                isVerifyingAccount = false
                status = "Verification failed: \(error.localizedDescription)"
                log(status)
            }
        }
    }

    func probeGettingStartedServer() {
        let normalizedUsername = config.normalized().accounts[0].username
        let password = appPassword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedUsername.isEmpty, !password.isEmpty else {
            status = "Enter email and password"
            return
        }

        isProbingServer = true
        status = "Finding IMAP server"
        log("Discovering IMAP server")

        Task {
            do {
                let result = try await imapDiscovery.discover(username: normalizedUsername, password: appPassword)
                updateFirstAccount { account in
                    account.username = normalizedUsername
                    account.host = result.candidate.host
                    account.port = result.candidate.port
                    if account.mailboxes.isEmpty {
                        account.mailboxes = [IMAPDefaults.mailbox]
                    }
                }
                availableMailboxes = WatcherPlan.mailboxesIncludingDefault(result.mailboxes)
                isProbingServer = false
                gettingStartedStep = .folders
                status = "Using \(result.candidate.host):\(result.candidate.port)"
                logDebug("Selected IMAP server")
            } catch {
                if let domain = IMAPDiscovery.domain(from: normalizedUsername) {
                    updateFirstAccount { account in
                        account = WatcherPlan.discoveryFallbackAccount(
                            current: account,
                            username: normalizedUsername,
                            domain: domain
                        )
                    }
                }
                isProbingServer = false
                gettingStartedStep = .credentials
                status = "Discovery failed. Enter server manually."
                log(status)
            }
        }
    }

    func verifyGettingStartedCredentials() {
        guard canStart else {
            status = "Enter username and password"
            return
        }

        let normalizedConfig = config.normalized()
        let accountConfig = normalizedConfig.accounts[0]
        let account = WatcherPlan.account(config: accountConfig, password: appPassword)

        isVerifyingAccount = true
        status = "Verifying login"
        log("Verifying IMAP login")

        Task {
            let client = IMAPClient(account: account)
            do {
                try await connectWithTimeout(client)
                try await client.login()
                let mailboxes = try await client.listMailboxes()
                await client.disconnect()
                availableMailboxes = WatcherPlan.mailboxesIncludingDefault(mailboxes)
                updateFirstAccount { account in
                    if account.mailboxes.isEmpty {
                        account.mailboxes = [IMAPDefaults.mailbox]
                    }
                }
                isVerifyingAccount = false
                gettingStartedStep = .folders
                status = "Login verified"
                logDebug("IMAP login verified")
            } catch {
                await client.disconnect()
                isVerifyingAccount = false
                status = "Login failed: \(error.localizedDescription)"
                log(status)
            }
        }
    }

    func loadAvailableMailboxes() {
        guard canStart else {
            status = "Enter IMAP server, username, and app password"
            return
        }

        let normalizedConfig = config.normalized()
        let account = WatcherPlan.account(config: normalizedConfig.accounts[0], password: appPassword)

        isLoadingMailboxes = true
        status = "Loading mailboxes"
        log("Loading IMAP mailboxes")

        Task {
            let client = IMAPClient(account: account)
            do {
                try await connectWithTimeout(client)
                try await client.login()
                let mailboxes = try await client.listMailboxes()
                await client.disconnect()
                availableMailboxes = WatcherPlan.mailboxesIncludingDefault(mailboxes)
                isLoadingMailboxes = false
                status = "Mailboxes loaded"
                logDebug("Loaded IMAP mailboxes")
            } catch {
                await client.disconnect()
                isLoadingMailboxes = false
                status = "Could not load mailboxes: \(error.localizedDescription)"
                log(status)
            }
        }
    }

    func finishGettingStarted() {
        guard canStart else {
            status = "Choose at least one mailbox"
            return
        }

        Task {
            do {
                config.normalize()
                try await saveCurrentConfiguration()
                status = "Account configured"
                gettingStartedStep = .done
                logDebug("Getting started completed")
                start(saveBeforeStart: false)
            } catch {
                status = error.localizedDescription
                log("Save failed: \(error.localizedDescription)")
            }
        }
    }

    func completeGettingStarted() {
        shouldShowGettingStarted = false
        closeGettingStartedWindow()
    }

    func start() {
        start(saveBeforeStart: true)
    }

    private func start(saveBeforeStart: Bool) {
        if saveBeforeStart {
            config.normalize()
            save()
        }

        guard canStart else {
            status = "Enter IMAP server, username, and app password"
            log(status)
            return
        }
        stop()
        let normalizedConfig = config.normalized()
        let accountConfig = normalizedConfig.accounts[0]
        let entry = AccountEntry(config: accountConfig, password: appPassword)
        // Expand one logical account into one watcher per mailbox so each stream can advance its own UID cursor.
        watchers = WatcherPlan.accounts(entries: [entry], config: normalizedConfig).map { account in
            MailWatcher(account: account, config: normalizedConfig, stateStore: stateStore)
        }
        isRunning = true
        status = "Connecting"
        log("Starting watcher")

        watcherTasks = watchers.map { watcher in
            Task {
                for await event in await watcher.events() {
                    handle(event)
                }
            }
        }
    }

    private var canStart: Bool {
        guard let account = config.normalized().accounts.first else {
            return false
        }
        return !account.host.isEmpty
            && !account.username.isEmpty
            && !account.mailboxes.isEmpty
            && !appPassword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var canVerifyAccount: Bool {
        canStart && !isVerifyingAccount
    }

    var canDiscoverAccount: Bool {
        let account = config.normalized().accounts[0]
        return !account.username.isEmpty
            && !appPassword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isProbingServer
    }

    var firstAccount: IMAPAccountConfig {
        config.accounts.first ?? IMAPAccountConfig()
    }

    func updateFirstAccount(_ update: (inout IMAPAccountConfig) -> Void) {
        if config.accounts.isEmpty {
            config.accounts = [IMAPAccountConfig()]
        }
        // The UI currently edits a single account flow, so always materialize slot zero before mutating it.
        update(&config.accounts[0])
    }

    func stop() {
        watcherTasks.forEach { $0.cancel() }
        watcherTasks = []
        let activeWatchers = watchers
        if !activeWatchers.isEmpty {
            Task {
                for watcher in activeWatchers {
                    await watcher.stop()
                }
            }
        }
        watchers = []
        isRunning = false
        if status != "Not connected" {
            status = "Stopped"
            log("Watcher stopped")
        }
    }

    private func handle(_ event: MailWatcherEvent) {
        // Keep watcher event interpretation pure so the app shell can stay thin and tests can exercise runtime
        // behavior without going through notification or clipboard APIs.
        let result = AppEventReducer.reduce(
            state: AppRuntimeState(
                status: status,
                lastNotification: lastNotification,
                recentNotifications: recentNotifications
            ),
            event: event,
            config: config,
            now: Date(),
            recentNotificationLifetime: AppRuntimeDefaults.recentNotificationLifetimeSeconds
        )

        status = result.state.status
        lastNotification = result.state.lastNotification
        recentNotifications = result.state.recentNotifications

        for command in result.commands {
            switch command {
            case let .deliverNotification(notification, autoCopy):
                notifications.show(notification, autoCopy: autoCopy) { [weak self] message in
                    self?.logDebug(message)
                }
            case let .log(message):
                logDebug(message)
            }
        }
    }

    func rescanMailbox() {
        Task {
            do {
                let mailboxes = config.normalized().accounts[0].mailboxes
                for mailbox in mailboxes {
                    try await stateStore.reset(mailbox: mailbox)
                }
                logDebug("Reset UID state; restart watcher to run a recent-only startup scan")
            } catch {
                log("Could not reset UID state: \(error.localizedDescription)")
            }
        }
    }

    func copyLastCode() {
        guard let lastNotification else {
            return
        }
        clipboard.copy(lastNotification.code)
        status = "Copied code"
        logDebug("Copied last code from menu")
    }

    func copyCode(_ notification: CodeNotification) {
        clipboard.copy(notification.code)
        status = "Copied code"
        logDebug("Copied code from recent history")
    }

    func setAutoCopyToClipboard(_ isEnabled: Bool) {
        config.autoCopyToClipboard = isEnabled
        save()
    }

    private func log(_ message: String) {
        logger.info("\(message, privacy: .public)")
    }

    private func logDebug(_ message: String) {
        logger.debug("\(message, privacy: .public)")
    }

    private var hasBlankRequiredAccountSettings: Bool {
        let account = config.normalized().accounts[0]
        return account.host.isEmpty
            || account.username.isEmpty
            || appPassword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var shouldShowGettingStartedFlow: Bool {
        hasBlankRequiredAccountSettings
    }

    private func saveCurrentConfiguration() async throws {
        let normalizedConfig = config.normalized()
        try await configStore.save(normalizedConfig)
        let currentKeychainAccount = firstAccountKey(in: normalizedConfig)

        if let savedKeychainAccount, savedKeychainAccount != currentKeychainAccount {
            try keychain.deletePassword(for: savedKeychainAccount)
        }

        if let currentKeychainAccount {
            if appPassword.isEmpty {
                try keychain.deletePassword(for: currentKeychainAccount)
            } else {
                try keychain.savePassword(appPassword, for: currentKeychainAccount)
            }
        }
        savedKeychainAccount = currentKeychainAccount
    }

    private func startRecentNotificationCleanup() {
        recentNotificationCleanupTask?.cancel()
        recentNotificationCleanupTask = Task { [weak self] in
            while !Task.isCancelled {
                // Reducer pruning only runs on new detections; this periodic pass keeps stale history from lingering
                // indefinitely when the app stays open but no new mail arrives.
                try? await Task.sleep(for: .seconds(AppRuntimeDefaults.recentNotificationCleanupIntervalSeconds))
                self?.pruneRecentNotifications()
            }
        }
    }

    private func pruneRecentNotifications() {
        recentNotifications = NotificationPolicy.prunedNotifications(
            from: recentNotifications,
            now: Date(),
            lifetime: AppRuntimeDefaults.recentNotificationLifetimeSeconds
        )
    }

    private func closeGettingStartedWindow() {
        let gettingStartedWindow = NSApplication.shared.windows.first {
            $0.identifier?.rawValue == AppUIConstants.gettingStartedWindowIdentifier
        }
        gettingStartedWindow?.close()
    }

    private func connectWithTimeout(_ client: IMAPClient, seconds: UInt64 = UInt64(AppRuntimeDefaults.connectionTimeoutSeconds)) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await client.connect()
            }
            group.addTask {
                // Connection hangs are common with mistyped hosts and captive networks; race connect against a short
                // timeout so onboarding failures return quickly and predictably.
                try await Task.sleep(for: .seconds(seconds))
                throw IMAPSetupError.connectionTimedOut
            }
            try await group.next()
            group.cancelAll()
        }
    }

    private func firstAccountKey(in config: AppConfig) -> String? {
        guard let account = config.normalized().accounts.first, !account.username.isEmpty, !account.host.isEmpty else {
            return nil
        }
        return "\(account.username)@\(account.host)"
    }
}

/// Setup-only errors that map transient connection failures into short user-facing messages.
private enum IMAPSetupError: Error, LocalizedError {
    case connectionTimedOut

    var errorDescription: String? {
        switch self {
        case .connectionTimedOut:
            return "The IMAP connection timed out."
        }
    }
}

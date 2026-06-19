import Foundation

/// Watches one IMAP mailbox continuously and emits high-level app events instead of raw protocol results.
/// The actor owns reconnect, startup scan, and UID checkpoint behavior so the rest of the app can treat mail
/// watching as a single monotonic event stream.
public actor MailWatcher {
    private let account: IMAPAccount
    private let config: AppConfig
    private let stateStore: UIDStateStore
    private let evaluator: MessageEvaluator
    private var isStopped = false
    private var didInitialScan = false

    public init(
        account: IMAPAccount,
        config: AppConfig,
        stateStore: UIDStateStore = UIDStateStore(),
        evaluator: MessageEvaluator = MessageEvaluator()
    ) {
        self.account = account
        self.config = config
        self.stateStore = stateStore
        self.evaluator = evaluator
    }

    public func stop() {
        isStopped = true
    }

    public func events() -> AsyncStream<MailWatcherEvent> {
        AsyncStream { continuation in
            let task = Task {
                await run(continuation: continuation)
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private var watcherAccount: MailWatcherAccount {
        MailWatcherAccount(username: account.username, host: account.host, mailbox: account.mailbox)
    }

    private func run(continuation: AsyncStream<MailWatcherEvent>.Continuation) async {
        while !isStopped && !Task.isCancelled {
            let client = IMAPClient(account: account)
            do {
                try Task.checkCancellation()
                continuation.yield(.status(account: watcherAccount, message: "Connecting to \(account.host):\(account.port)"))
                try await client.connect()
                continuation.yield(.status(account: watcherAccount, message: "Connected; logging in as \(account.username)"))
                try await client.login()
                let capabilities = try await client.capabilities()
                let usesIdle = config.preferIMAPIdle && capabilities.contains("IDLE")
                continuation.yield(.status(account: watcherAccount, message: "Selecting mailbox \(account.mailbox)"))
                try await client.selectMailbox()
                continuation.yield(.connected(account: watcherAccount, mode: usesIdle ? .idle : .polling))
                // Always scan immediately after SELECT so startup behavior is identical for IDLE and polling accounts.
                try await scanNewMessages(client: client, continuation: continuation)

                while !isStopped && !Task.isCancelled {
                    try Task.checkCancellation()
                    if usesIdle {
                        continuation.yield(.status(account: watcherAccount, message: "Waiting for new mail with IMAP IDLE"))
                        do {
                            let wakeReason = try await client.idleUntilMailboxChanges()
                            continuation.yield(.status(account: watcherAccount, message: "IDLE woke: \(wakeReason)"))
                        } catch is CancellationError {
                            await client.disconnect()
                            return
                        } catch {
                            continuation.yield(.status(account: watcherAccount, message: "IMAP IDLE ended; reconnecting"))
                            await client.disconnect()
                            break
                        }
                    } else {
                        let pollingInterval = max(AppConfigDefaults.minimumPollingIntervalSeconds, config.pollingIntervalSeconds)
                        continuation.yield(.status(account: watcherAccount, message: "Polling again in \(Int(pollingInterval))s"))
                        try await Task.sleep(for: .seconds(pollingInterval))
                    }
                    try await scanNewMessages(client: client, continuation: continuation)
                }
            } catch is CancellationError {
                await client.disconnect()
                break
            } catch {
                continuation.yield(.transientFailure(account: watcherAccount, message: error.localizedDescription))
                await client.disconnect()
                try? await Task.sleep(for: .seconds(AppConfigDefaults.minimumPollingIntervalSeconds))
            }
        }
        continuation.yield(.stopped(account: watcherAccount))
        continuation.finish()
    }

    private func scanNewMessages(client: IMAPClient, continuation: AsyncStream<MailWatcherEvent>.Continuation) async throws {
        try Task.checkCancellation()
        let lastSeen = await stateStore.lastSeenUID(account: watcherAccount)
        let scan = try await nextScan(client: client, lastSeen: lastSeen, continuation: continuation)
        emitScanStatus(for: scan.uids, continuation: continuation)

        for uid in scan.uids {
            try await processMessage(uid: uid, client: client, continuation: continuation)
        }

        if let startupBaseline = scan.startupBaseline {
            try await stateStore.markSeen(uid: startupBaseline, account: watcherAccount)
        }
    }

    private func nextScan(
        client: IMAPClient,
        lastSeen: UInt64,
        continuation: AsyncStream<MailWatcherEvent>.Continuation
    ) async throws -> (uids: [UInt64], startupBaseline: UInt64?) {
        let plan = MailWatcherScanPolicy.nextPlan(
            didInitialScan: didInitialScan,
            lastSeen: lastSeen,
            mailbox: account.mailbox,
            config: config
        )
        emitStatusMessages(plan.statusMessages, continuation: continuation)

        switch plan.request {
        case let .afterUID(uid):
            return (try await client.searchUIDs(after: uid), nil)
        case .startup:
            didInitialScan = true
            return try await startupScan(client: client, lastSeen: lastSeen, continuation: continuation)
        }
    }

    private func startupScan(
        client: IMAPClient,
        lastSeen: UInt64,
        continuation: AsyncStream<MailWatcherEvent>.Continuation
    ) async throws -> (uids: [UInt64], startupBaseline: UInt64?) {
        let plan = MailWatcherScanPolicy.nextPlan(
            didInitialScan: false,
            lastSeen: lastSeen,
            mailbox: account.mailbox,
            config: config
        )
        let baseline = try await client.highestKnownUID()

        do {
            guard case let .startup(lookbackSeconds, _) = plan.request else {
                return ([], nil)
            }
            // Capture the mailbox baseline before the recent-message search so messages arriving during startup
            // are deferred to the normal incremental pass instead of being double-processed.
            let resolution = MailWatcherScanPolicy.resolveStartupScan(
                uids: try await client.searchUIDsYoungerThan(seconds: lookbackSeconds),
                baseline: baseline,
                config: config,
                lastSeen: lastSeen
            )
            emitStatusMessages(resolution.statusMessages, continuation: continuation)
            return (resolution.uids, resolution.startupBaseline)
        } catch {
            let failure = MailWatcherScanPolicy.startupFailure(
                baseline: baseline,
                errorDescription: error.localizedDescription
            )
            emitStatusMessages(failure.statusMessages, continuation: continuation)
            // On startup-search failure we still advance the baseline to "now" so a bad YOUNGER query does not
            // cause the next reconnect to walk arbitrarily old mail.
            try await stateStore.markSeen(uid: baseline, account: watcherAccount)
            return ([], nil)
        }
    }

    private func emitScanStatus(
        for uids: [UInt64],
        continuation: AsyncStream<MailWatcherEvent>.Continuation
    ) {
        continuation.yield(.status(account: watcherAccount, message: MailWatcherScanPolicy.scanStatusMessage(for: uids)))
    }

    private func processMessage(
        uid: UInt64,
        client: IMAPClient,
        continuation: AsyncStream<MailWatcherEvent>.Continuation
    ) async throws {
        try Task.checkCancellation()
        continuation.yield(.status(account: watcherAccount, message: "Fetching UID \(uid)"))
        if let event = try await client.fetchMessage(uid: uid) {
            let subject = event.subject.isEmpty ? "(no subject)" : event.subject
            continuation.yield(.status(account: watcherAccount, message: "Scoring UID \(uid): \(subject)"))
            emitEvaluation(evaluator.evaluate(event: event, config: config), uid: uid, continuation: continuation)
        } else {
            continuation.yield(.status(account: watcherAccount, message: "Could not fetch UID \(uid)"))
        }

        // Mark every fetched UID as seen even when it yields no code so reconnects remain monotonic.
        try await stateStore.markSeen(uid: uid, account: watcherAccount)
    }

    private func emitEvaluation(
        _ evaluation: MessageEvaluation,
        uid: UInt64,
        continuation: AsyncStream<MailWatcherEvent>.Continuation
    ) {
        switch evaluation {
        case .noCandidate:
            continuation.yield(.status(account: watcherAccount, message: "No code candidate in UID \(uid)"))
        case let .ignoredLowScore(detected):
            continuation.yield(.status(account: watcherAccount, message: "Ignored candidate in UID \(uid) with low score \(detected.score)"))
        case let .detected(notification):
            continuation.yield(.status(account: watcherAccount, message: "Detected code in UID \(uid) with score \(notification.score)"))
            continuation.yield(.codeDetected(account: watcherAccount, notification: notification))
        }
    }

    private func emitStatusMessages(
        _ messages: [String],
        continuation: AsyncStream<MailWatcherEvent>.Continuation
    ) {
        for message in messages {
            continuation.yield(.status(account: watcherAccount, message: message))
        }
    }
}

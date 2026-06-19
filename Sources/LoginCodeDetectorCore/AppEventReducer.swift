import Foundation

/// Runtime state derived from watcher events and consumed by the app UI.
public struct AppRuntimeState: Equatable, Sendable {
    public var status: String
    public var lastNotification: CodeNotification?
    public var recentNotifications: [CodeNotification]

    public init(
        status: String,
        lastNotification: CodeNotification? = nil,
        recentNotifications: [CodeNotification] = []
    ) {
        self.status = status
        self.lastNotification = lastNotification
        self.recentNotifications = recentNotifications
    }
}

/// Side effects requested by the reducer after state transitions are computed.
public enum AppRuntimeCommand: Equatable, Sendable {
    case deliverNotification(CodeNotification, autoCopy: Bool)
    case log(String)
}

/// Combined reducer output containing the next state and any side effects to perform.
public struct AppEventReducerResult: Equatable, Sendable {
    public var state: AppRuntimeState
    public var commands: [AppRuntimeCommand]

    public init(state: AppRuntimeState, commands: [AppRuntimeCommand]) {
        self.state = state
        self.commands = commands
    }
}

/// Pure event reducer that translates watcher events into app runtime state and commands.
public enum AppEventReducer {
    public static func reduce(
        state: AppRuntimeState,
        event: MailWatcherEvent,
        config: AppConfig,
        now: Date,
        recentNotificationLifetime: TimeInterval
    ) -> AppEventReducerResult {
        var nextState = state
        var commands: [AppRuntimeCommand] = []

        switch event {
        case let .connected(_, mode):
            nextState.status = mode == .idle
                ? "Connected with IMAP IDLE"
                : "Connected with polling"
            commands.append(.log(nextState.status))

        case let .codeDetected(_, notification):
            nextState.lastNotification = notification
            nextState.recentNotifications.insert(notification, at: 0)
            // Prune only when new notifications arrive so the UI keeps enough short-term history for user context
            // without needing a background cleanup timer.
            nextState.recentNotifications = NotificationPolicy.prunedNotifications(
                from: nextState.recentNotifications,
                now: now,
                lifetime: recentNotificationLifetime
            )
            commands.append(.log("Notification ready with score \(notification.score)"))
            commands.append(.deliverNotification(notification, autoCopy: NotificationPolicy.shouldAutoCopy(notification: notification, config: config)))

        case let .status(_, message):
            nextState.status = message
            commands.append(.log("Watcher status updated"))

        case let .transientFailure(_, message):
            nextState.status = "Error: \(message)"
            commands.append(.log("Watcher transient failure: \(message)"))

        case .stopped:
            commands.append(.log("Watcher stopped"))
        }

        return AppEventReducerResult(state: nextState, commands: commands)
    }
}

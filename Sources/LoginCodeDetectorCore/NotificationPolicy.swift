import Foundation

/// Encapsulates the rules for when detections should notify, auto-copy, or remain in recent history.
public enum NotificationPolicy {
    public static func shouldAutoCopy(notification: CodeNotification, config: AppConfig) -> Bool {
        // Gate auto-copy on both user opt-in and a higher confidence threshold so low-signal matches still notify
        // without silently overwriting the clipboard.
        config.autoCopyToClipboard && notification.score >= config.minimumAutoCopyScore
    }

    public static func prunedNotifications(
        from notifications: [CodeNotification],
        now: Date,
        lifetime: TimeInterval
    ) -> [CodeNotification] {
        let cutoff = now.addingTimeInterval(-lifetime)
        return notifications.filter { $0.receivedAt >= cutoff }
    }
}

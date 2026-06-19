import LoginCodeDetectorCore
import Foundation
import UserNotifications

@MainActor
/// Bridges app notifications into `UNUserNotificationCenter` and handles copy actions from delivered alerts.
/// It also provides a safe fallback path when the app is running in environments that cannot present notifications.
final class NotificationCoordinator: NSObject, UNUserNotificationCenterDelegate {
    private enum Defaults {
        static let pendingCodeLifetime: Duration = .seconds(60)
    }

    /// Notification category identifiers registered with the system notification center.
    private enum Category {
        static let codeDetected = "CODE_DETECTED"
        static let codeCopied = "CODE_COPIED"
    }

    /// Interactive action identifiers attached to delivered notifications.
    private enum Action {
        static let copyCode = "COPY_CODE"
    }

    private let clipboard = ClipboardService()
    private var pendingCodes: [String: String] = [:]
    private var pendingCodeExpiryTasks: [String: Task<Void, Never>] = [:]
    private let supportsUserNotifications: Bool

    override init() {
        self.supportsUserNotifications = Bundle.main.bundleURL.pathExtension == "app"
        super.init()
        guard supportsUserNotifications else {
            return
        }
        let copy = UNNotificationAction(
            identifier: Action.copyCode,
            title: "Copy Code",
            options: [.foreground]
        )
        let needsCopy = UNNotificationCategory(
            identifier: Category.codeDetected,
            actions: [copy],
            intentIdentifiers: []
        )
        let alreadyCopied = UNNotificationCategory(
            identifier: Category.codeCopied,
            actions: [],
            intentIdentifiers: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([needsCopy, alreadyCopied])
        UNUserNotificationCenter.current().delegate = self
    }

    func requestAuthorization() async -> Bool {
        guard supportsUserNotifications else {
            return false
        }
        return (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    func show(
        _ notification: CodeNotification,
        autoCopy: Bool,
        completion: @escaping @MainActor (String) -> Void = { _ in }
    ) {
        guard supportsUserNotifications else {
            if autoCopy {
                clipboard.copy(notification.code)
            }
            // Running under tests or as a plain executable cannot present user notifications on macOS, but we still
            // allow the rest of the pipeline to execute so behavior stays observable.
            completion("Notification skipped: run as a signed .app bundle to use macOS notifications")
            return
        }

        if autoCopy {
            clipboard.copy(notification.code)
        } else {
            storePendingCode(notification.code, for: notification.id)
        }

        let content = UNMutableNotificationContent()
        content.title = autoCopy ? "2FA code copied" : "2FA code found"
        content.subtitle = notification.sender
        content.body = [
            "Code: \(notification.code)",
            notification.subject
        ]
        .filter { !$0.isEmpty }
        .joined(separator: "\n")
        content.sound = .default
        content.categoryIdentifier = autoCopy ? Category.codeCopied : Category.codeDetected
        content.userInfo = ["id": notification.id]

        let request = UNNotificationRequest(identifier: notification.id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            Task { @MainActor in
                if let error {
                    self.clearPendingCode(for: notification.id)
                    completion("Notification failed: \(error.localizedDescription)")
                } else if autoCopy {
                    completion("Notification delivered; code copied automatically")
                } else {
                    completion("Notification delivered with Copy Code action for 60 seconds")
                }
            }
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard response.actionIdentifier == Action.copyCode else {
            return
        }
        let id = response.notification.request.content.userInfo["id"] as? String
        await MainActor.run {
            guard
                let id,
                let code = pendingCodes[id]
            else {
                return
            }
            clearPendingCode(for: id)
            clipboard.copy(code)
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        // Present banners even in the foreground so menu-bar usage still surfaces newly detected codes.
        [.banner, .sound]
    }

    private func storePendingCode(_ code: String, for id: String) {
        clearPendingCode(for: id)
        pendingCodes[id] = code
        pendingCodeExpiryTasks[id] = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Defaults.pendingCodeLifetime)
            self?.clearPendingCode(for: id)
        }
    }

    private func clearPendingCode(for id: String) {
        pendingCodes.removeValue(forKey: id)
        pendingCodeExpiryTasks.removeValue(forKey: id)?.cancel()
    }
}

import AppKit

@MainActor
/// Brings the app to the foreground when the menu bar UI opens settings or needs user attention.
enum AppActivation {
    static func activate() {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
        NSApplication.shared.windows
            .filter { $0.isVisible }
            .last?
            .makeKeyAndOrderFront(nil)
    }
}

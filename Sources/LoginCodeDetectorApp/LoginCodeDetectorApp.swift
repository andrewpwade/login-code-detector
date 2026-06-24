import Combine
import SwiftUI

/// Shared window sizing constants for the menu bar popover and settings scene.
enum AppUIConstants {
    static let menuWidth: CGFloat = 390
    static let menuHeight: CGFloat = 520
    static let settingsMinWidth: CGFloat = 560
    static let settingsIdealWidth: CGFloat = 620
    static let settingsMinHeight: CGFloat = 480
    static let settingsIdealHeight: CGFloat = 560
    static let gettingStartedWindowIdentifier = "getting-started"
    static let gettingStartedWindowTitle = "Getting Started"
    static let gettingStartedWindowWidth: CGFloat = 620
    static let gettingStartedWindowHeight: CGFloat = 500
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let viewModel = AppViewModel()
    private var gettingStartedWindowController: NSWindowController?
    private var cancellables: Set<AnyCancellable> = []

    override init() {
        super.init()
        viewModel.$shouldShowGettingStarted
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.presentGettingStartedWindowIfNeeded()
            }
            .store(in: &cancellables)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        viewModel.load()
    }

    func applicationWillTerminate(_ notification: Notification) {
        viewModel.stop()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        presentGettingStartedWindowIfNeeded()
    }

    private func presentGettingStartedWindowIfNeeded() {
        guard viewModel.shouldShowGettingStarted else {
            closeGettingStartedWindow()
            return
        }

        if let window = gettingStartedWindowController?.window {
            AppActivation.activate()
            window.makeKeyAndOrderFront(nil)
            return
        }

        let rootView = GettingStartedWindowView()
            .environmentObject(viewModel)
        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: hostingController)
        window.identifier = NSUserInterfaceItemIdentifier(AppUIConstants.gettingStartedWindowIdentifier)
        window.title = AppUIConstants.gettingStartedWindowTitle
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.setContentSize(NSSize(width: AppUIConstants.gettingStartedWindowWidth, height: AppUIConstants.gettingStartedWindowHeight))
        window.center()
        window.isReleasedWhenClosed = false
        let controller = NSWindowController(window: window)
        gettingStartedWindowController = controller
        AppActivation.activate()
        controller.showWindow(nil)
    }

    private func closeGettingStartedWindow() {
        gettingStartedWindowController?.close()
        gettingStartedWindowController = nil
    }
}

@main
/// SwiftUI app entry point for the menu bar utility.
struct LoginCodeDetectorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Login Code Detector", systemImage: "key.viewfinder") {
            MenuContentView()
                .environmentObject(appDelegate.viewModel)
                .frame(width: AppUIConstants.menuWidth, height: AppUIConstants.menuHeight)
        }
        .menuBarExtraStyle(.window)

        Settings {
            PreferencesView()
                .environmentObject(appDelegate.viewModel)
                .frame(
                    minWidth: AppUIConstants.settingsMinWidth,
                    idealWidth: AppUIConstants.settingsIdealWidth,
                    minHeight: AppUIConstants.settingsMinHeight,
                    idealHeight: AppUIConstants.settingsIdealHeight
                )
        }
        .defaultSize(width: AppUIConstants.settingsIdealWidth, height: AppUIConstants.settingsIdealHeight)
    }
}

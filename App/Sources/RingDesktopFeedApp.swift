import SwiftUI

@main
struct RingDesktopFeedApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate

    var body: some Scene {
        // Everything lives in the status item's panel (see PanelController);
        // SwiftUI needs at least one scene.
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var helper: Helper?
    private var panel: PanelController?
    private var notifier: DoorbellNotifier?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Start at launch, not when the panel first opens: the helper has to
        // be running to receive Ring events.
        let helper = Helper()
        let panel = PanelController(viewer: Viewer(helper: helper))
        let notifier = DoorbellNotifier { [weak panel] id in panel?.showLive(cameraId: id) }
        helper.onActivity = { [weak panel, weak notifier] activity in
            panel?.noteActivity(activity)
            if case .ding(let id, let name) = activity { notifier?.ding(cameraId: id, cameraName: name) }
        }
        helper.onSignInExpired = { [weak panel, weak notifier] in
            notifier?.signInExpired()
            panel?.showSignIn()
        }
        helper.start()
        self.helper = helper
        self.panel = panel
        self.notifier = notifier
    }
}

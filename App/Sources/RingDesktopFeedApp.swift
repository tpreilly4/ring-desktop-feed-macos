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

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Start at launch, not when the panel first opens: the helper has to
        // be running to receive Ring events.
        let helper = Helper()
        helper.start()
        self.helper = helper
        panel = PanelController(viewer: Viewer(helper: helper))
    }
}

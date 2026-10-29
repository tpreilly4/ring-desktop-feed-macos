import SwiftUI

@main
struct RingDesktopFeedApp: App {
    @State private var helper: Helper

    init() {
        // Start at launch, not when the popover first opens: the helper has
        // to be running to receive Ring events.
        let helper = Helper()
        helper.start()
        _helper = State(initialValue: helper)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(helper: helper)
        } label: {
            Text("🏠").accessibilityLabel("Ring Desktop Feed")
        }
        .menuBarExtraStyle(.window)

        Window("Sign In to Ring", id: SignInWindow.id) {
            SignInWindow(helper: helper)
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)
    }
}

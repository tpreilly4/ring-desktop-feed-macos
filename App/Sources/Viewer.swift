import Foundation
import Observation

/// What's being watched: the camera list, the selected camera and mute state.
@MainActor
@Observable
final class Viewer {
    let helper: Helper

    private(set) var signedIn: Bool?
    private(set) var cameras: [Camera] = []
    private(set) var error: String?
    var selectedId: Int?
    var muted = true

    var alwaysOnTop: Bool {
        didSet { UserDefaults.standard.set(alwaysOnTop, forKey: Self.alwaysOnTopKey) }
    }

    private static let alwaysOnTopKey = "miniPlayerAlwaysOnTop"

    init(helper: Helper) {
        self.helper = helper
        UserDefaults.standard.register(defaults: [Self.alwaysOnTopKey: true])
        alwaysOnTop = UserDefaults.standard.bool(forKey: Self.alwaysOnTopKey)
    }

    var selected: Camera? { cameras.first { $0.id == selectedId } }

    /// Identifies when cameras need refetching: a new helper, a sign-in/out,
    /// or Ring coming back.
    var refreshKey: RefreshKey { RefreshKey(port: helper.client?.port, account: helper.accountChanges, reachable: helper.ringReachable) }

    func refresh() async {
        guard let client = helper.client else { return }
        do {
            signedIn = try await client.isSignedIn()
            guard signedIn == true else {
                cameras = []
                return
            }
            cameras = try await client.cameras()
            error = nil
            if selected == nil {
                // Default to a wired camera, so opening a view doesn't wake
                // the doorbell's battery.
                selectedId = (cameras.first { !$0.hasBattery } ?? cameras.first)?.id
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func signOut() async {
        try? await helper.client?.signOut()
        helper.noteAccountChanged()
    }
}

struct RefreshKey: Equatable {
    let port: Int?
    let account: Int
    let reachable: Bool
}

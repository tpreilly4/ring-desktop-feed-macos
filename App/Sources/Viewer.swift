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
    /// Streams every camera side by side. The panel always opens this way;
    /// picking one camera lasts until it closes.
    var showAll = true
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

    /// The cameras on screen right now.
    var shown: [Camera] {
        if showAll { return cameras }
        return selected.map { [$0] } ?? []
    }

    var columns: Int { max(shown.count, 1) }

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
                // Used if "Both" is ever off without a camera picked. Prefer
                // a wired one, which doesn't use the doorbell's battery.
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

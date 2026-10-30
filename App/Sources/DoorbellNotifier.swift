import Foundation
import UserNotifications

/// Posts a notification when someone rings the doorbell; clicking it opens
/// live view of that camera. Motion stays quiet (the phone already buzzes).
@MainActor
final class DoorbellNotifier: NSObject, UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()
    private let openLive: (Int) -> Void

    init(openLive: @escaping (Int) -> Void) {
        self.openLive = openLive
        super.init()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func ding(cameraId: Int, cameraName: String) {
        let content = UNMutableNotificationContent()
        content.title = cameraName
        content.body = "Someone's at the door. Click to watch live."
        content.sound = .default
        content.userInfo = ["cameraId": cameraId]
        center.add(UNNotificationRequest(identifier: "ding-\(cameraId)", content: content, trigger: nil))
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard let id = response.notification.request.content.userInfo["cameraId"] as? Int else { return }
        await MainActor.run { openLive(id) }
    }

    // A menu bar app is always "in the foreground"; show the banner anyway.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

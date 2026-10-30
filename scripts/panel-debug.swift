// Debug builds only: drive the feed panel from the terminal.
//   swift scripts/panel-debug.swift open|detach|reattach|hide|settings|both|single
// Then read where it landed:
//   log show --last 1m --predicate 'subsystem == "com.tompreilly.ringdesktopfeed" && category == "panel"'
import Foundation

let command = CommandLine.arguments.dropFirst().first ?? "open"
DistributedNotificationCenter.default().postNotificationName(
    Notification.Name("com.tompreilly.ringdesktopfeed.debug"),
    object: command, userInfo: nil, deliverImmediately: true
)

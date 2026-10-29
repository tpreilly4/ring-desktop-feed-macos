import AppKit
import SwiftUI

/// Keeps the menu bar popover hanging from its icon, but has it extend to
/// the right (toward the top-right corner) instead of centering under the
/// icon. Clamped so it never runs off the right edge of the screen.
/// Re-applied whenever the window is shown or resized, since MenuBarExtra
/// re-centers it each time.
struct ExtendFromMenuBarIcon: NSViewRepresentable {
    var margin: CGFloat = 8

    func makeNSView(context: Context) -> NSView { PlacementView(margin: margin) }
    func updateNSView(_ view: NSView, context: Context) {}

    private final class PlacementView: NSView {
        let margin: CGFloat
        // nonisolated(unsafe): only touched on the main thread, plus deinit.
        nonisolated(unsafe) private var observers: [NSObjectProtocol] = []

        init(margin: CGFloat) {
            self.margin = margin
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { fatalError() }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
            guard let window else { return }

            let names: [Notification.Name] = [
                NSWindow.didBecomeKeyNotification,
                NSWindow.didResizeNotification,
                NSWindow.didMoveNotification,
            ]
            observers = names.map { name in
                NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.place() }
                }
            }
            DispatchQueue.main.async { [weak self] in self?.place() }
        }

        private func place() {
            guard let window, let icon = Self.iconFrame(),
                  let screen = window.screen ?? NSScreen.main
            else { return }
            let visible = screen.visibleFrame
            // Left edge lines up with the icon; only x changes, so the
            // popover stays right under the menu bar where the system put it.
            let x = min(max(icon.minX, visible.minX + margin), visible.maxX - window.frame.width - margin)
            // Setting the same origin again doesn't re-post didMove, so no loop.
            if window.frame.origin.x != x {
                window.setFrameOrigin(NSPoint(x: x, y: window.frame.origin.y))
            }
        }

        /// The status item's own window, which MenuBarExtra creates for the icon.
        private static func iconFrame() -> NSRect? {
            NSApp.windows
                .first { String(describing: type(of: $0)).contains("StatusBarWindow") }?
                .frame
        }

        deinit {
            observers.forEach(NotificationCenter.default.removeObserver)
        }
    }
}

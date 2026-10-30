import AppKit
import SwiftUI
import os

/// Owns the 🏠 status item and the single feed panel. The panel either hangs
/// from the menu bar (closes when you click away) or floats as a mini-player.
/// Switching modes animates the same window, so the stream keeps playing.
@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    private let viewer: Viewer
    private let state = PanelState()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let panel: FeedPanel
    private var attachedSize = CGSize(width: 360, height: 120)
    private var lastHidden = Date.distantPast
    private var animating = false
    private var signInWindow: NSWindow?
    private var dragMonitor: Any?
    private var motionUntil = Date.distantPast
    private var dingUntil = Date.distantPast
    private var iconTimer: Timer?
    private var drag: (start: NSPoint, origin: NSPoint, moving: Bool)?

    /// Gap between the menu bar and the attached panel.
    private let menuBarGap: CGFloat = 4
    private let screenMargin: CGFloat = 8

    init(viewer: Viewer) {
        self.viewer = viewer
        panel = FeedPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 120),
            // Borderless: a hidden title bar still reserves space that SwiftUI
            // and AppKit fight over while resizing, which crashed on pop out.
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init()

        if let button = statusItem.button {
            button.setAccessibilityLabel("Ring Desktop Feed")
            button.target = self
            button.action = #selector(statusItemClicked)
        }

        // Clear window; FeedPanelView draws the rounded shape and AppKit
        // casts the shadow from it.
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.minSize = NSSize(width: 320, height: 320 * 9 / 16 + FeedPanelView.barHeight)
        panel.delegate = self

        let actions = PanelActions(
            detach: { [weak self] in self?.detach() },
            reattach: { [weak self] in self?.reattach() },
            close: { [weak self] in self?.hide() },
            toggleOnTop: { [weak self] in self?.toggleOnTop() },
            signIn: { [weak self] in self?.showSignIn() }
        )
        let root = FeedPanelView(viewer: viewer, panel: state, actions: actions) { [weak self] size in
            self?.attachedSizeChanged(size)
        }
        panel.contentViewController = NSHostingController(rootView: root)
        applyMode()
        watchForWindowDrags()
        updateIcon()
        // Expire the motion dot / doorbell icon, and notice lost contact.
        iconTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateIcon() }
        }
        #if DEBUG
        listenForDebugCommands()
        #endif
    }

    // MARK: Menu bar icon

    /// Motion shows a dot for 5 minutes; a doorbell press swaps in 🔔 for a
    /// minute.
    func noteActivity(_ activity: Helper.Activity) {
        switch activity {
        case .motion: motionUntil = Date().addingTimeInterval(5 * 60)
        case .ding:
            motionUntil = Date().addingTimeInterval(5 * 60)
            dingUntil = Date().addingTimeInterval(60)
        }
        updateIcon()
    }

    private func updateIcon() {
        guard let button = statusItem.button else { return }
        let now = Date()
        let lostContact: Bool = switch viewer.helper.state {
        case .failed: true
        case .ready: viewer.error != nil
        case .starting: false
        }
        let title = NSMutableAttributedString(string: now < dingUntil ? "🔔" : "🏠")
        let badge: (String, NSColor)? =
            if lostContact { ("⚠︎", .systemOrange) }
            else if now < motionUntil { ("●", .systemRed) }
            else { nil }
        if let (symbol, color) = badge {
            title.append(NSAttributedString(string: symbol, attributes: [
                .font: NSFont.systemFont(ofSize: 8, weight: .bold),
                .foregroundColor: color,
                .baselineOffset: 6,
            ]))
        }
        button.attributedTitle = title
        button.toolTip = lostContact ? "Ring Desktop Feed: can't reach Ring" : "Ring Desktop Feed"
    }

    // MARK: Showing and hiding

    /// Opens the floating mini-player on one camera (from a doorbell
    /// notification).
    func showLive(cameraId: Int) {
        viewer.selectedId = cameraId
        switch (state.visible, state.mode) {
        case (true, .detached):
            break
        case (true, .attached):
            detach()
        case (false, _):
            state.mode = .detached
            applyMode()
            var frame = attachedFrame(for: attachedSize)
            frame.origin.y -= 28
            panel.setFrame(frame, display: true)
            state.visible = true
        }
        panel.makeKeyAndOrderFront(nil)
    }

    @objc private func statusItemClicked() {
        switch (state.visible, state.mode) {
        case (true, .attached):
            hide()
        case (true, .detached):
            reattach()
        case (false, _):
            // Clicking the icon while the panel is open first takes focus away
            // (which hides it), then lands here; don't reopen it.
            if Date().timeIntervalSince(lastHidden) > 0.3 { showAttached() }
        }
    }

    private func showAttached() {
        state.mode = .attached
        applyMode()
        panel.setFrame(attachedFrame(for: attachedSize), display: true)
        state.visible = true
        panel.makeKeyAndOrderFront(nil)
    }

    private func hide() {
        guard state.visible else { return }
        state.visible = false
        lastHidden = Date()
        panel.orderOut(nil)
        state.mode = .attached
        applyMode()
    }

    func windowDidResignKey(_ notification: Notification) {
        // Like a menu: the attached panel goes away when you click elsewhere.
        if state.mode == .attached, !animating { hide() }
    }

    // MARK: Detaching and snapping back

    /// Pop the panel off the menu bar: it drops a little and gives a short
    /// shake, then stays put as a mini-player.
    private func detach() {
        guard state.mode == .attached, !animating else { return }
        state.mode = .detached
        applyMode()

        animating = true
        var dropped = panel.frame
        dropped.origin.y -= 28
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(dropped, display: true)
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                self?.shake {
                    self?.animating = false
                }
            }
        }
    }

    /// Fly back under the menu bar icon with a little overshoot, then become
    /// the attached panel again.
    private func reattach() {
        guard state.mode == .detached, !animating else { return }
        animating = true
        panel.styleMask.remove(.resizable)
        let target = attachedFrame(for: attachedSize)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.38
            // Overshoots slightly past the target, then settles: a "snap".
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.34, 1.45, 0.64, 1)
            panel.animator().setFrame(target, display: true)
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.state.mode = .attached
                self.applyMode()
                self.panel.setFrame(self.attachedFrame(for: self.attachedSize), display: true)
                self.animating = false
                self.panel.makeKeyAndOrderFront(nil)
            }
        }
    }

    private func shake(completion: @escaping @MainActor () -> Void) {
        let origin = panel.frame.origin
        let path = CGMutablePath()
        path.move(to: origin)
        for offset: CGFloat in [-7, 6, -4, 3, -1.5, 0] {
            path.addLine(to: CGPoint(x: origin.x + offset, y: origin.y))
        }
        let animation = CAKeyframeAnimation()
        animation.path = path
        animation.duration = 0.32
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        panel.animations = ["frameOrigin": animation]
        NSAnimationContext.runAnimationGroup { _ in
            panel.animator().setFrameOrigin(origin)
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                self?.panel.animations = [:]
                completion()
            }
        }
    }

    // MARK: Dragging the mini-player

    /// The web player swallows mouse events, so dragging the video wouldn't
    /// move the window. Watch the mouse ourselves: a drag that starts
    /// anywhere in the mini-player (except the resize edges) moves it, while
    /// a plain click still reaches the player and the bar's buttons.
    private func watchForWindowDrags() {
        dragMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
        ) { [weak self] event in
            // Local monitors run on the main thread; NSEvent just isn't Sendable.
            nonisolated(unsafe) let event = event
            nonisolated(unsafe) var result: NSEvent? = event
            MainActor.assumeIsolated { result = self?.handleDrag(event) ?? event }
            return result
        }
    }

    private func handleDrag(_ event: NSEvent) -> NSEvent? {
        guard event.window === panel, state.mode == .detached, !animating else {
            drag = nil
            return event
        }
        let mouse = NSEvent.mouseLocation
        switch event.type {
        case .leftMouseDown:
            // Leave the edges to AppKit's resizing.
            let edge: CGFloat = 8
            let inside = panel.frame.insetBy(dx: edge, dy: edge).contains(mouse)
            drag = inside ? (mouse, panel.frame.origin, false) : nil
            return event
        case .leftMouseDragged:
            guard var current = drag else { return event }
            let dx = mouse.x - current.start.x
            let dy = mouse.y - current.start.y
            // A few points of slack, so a slightly shaky click is still a click.
            if !current.moving, hypot(dx, dy) < 3 { return event }
            current.moving = true
            drag = current
            panel.setFrameOrigin(NSPoint(x: current.origin.x + dx, y: current.origin.y + dy))
            return nil
        case .leftMouseUp:
            let wasMoving = drag?.moving == true
            drag = nil
            // Swallow the mouse-up after a drag, so it doesn't click whatever
            // is under the pointer.
            return wasMoving ? nil : event
        default:
            return event
        }
    }

    // MARK: Modes and sizing

    private func applyMode() {
        switch state.mode {
        case .attached:
            panel.styleMask.remove(.resizable)
            panel.isMovable = false
            panel.isMovableByWindowBackground = false
            panel.level = .statusBar
            panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        case .detached:
            panel.styleMask.insert(.resizable)
            panel.isMovable = true
            panel.isMovableByWindowBackground = true
            applyOnTop()
        }
    }

    private func toggleOnTop() {
        viewer.alwaysOnTop.toggle()
        applyOnTop()
    }

    private func applyOnTop() {
        guard state.mode == .detached else { return }
        panel.level = viewer.alwaysOnTop ? .floating : .normal
        // Kept on top, it also follows you across Spaces.
        panel.collectionBehavior = viewer.alwaysOnTop ? [.canJoinAllSpaces, .fullScreenAuxiliary] : []
    }

    private func attachedSizeChanged(_ size: CGSize) {
        guard size.width > 0, size.height > 0, state.mode == .attached else { return }
        attachedSize = size
        if state.mode == .attached, !animating, state.visible {
            panel.setFrame(attachedFrame(for: size), display: true)
        }
    }

    /// Right under the menu bar, left edge at the 🏠 icon so the panel extends
    /// toward the top-right corner, kept on screen.
    private func attachedFrame(for size: CGSize) -> NSRect {
        let screen = statusItem.button?.window?.screen ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let iconX = statusItem.button?.window?.frame.minX ?? visible.maxX
        let x = min(max(iconX, visible.minX + screenMargin), visible.maxX - size.width - screenMargin)
        return NSRect(x: x, y: visible.maxY - menuBarGap - size.height, width: size.width, height: size.height)
    }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        // The mini-player keeps the video at 16:9 above the control bar.
        guard state.mode == .detached, !animating else { return frameSize }
        let width = max(frameSize.width, sender.minSize.width)
        return NSSize(width: width, height: (width * 9 / 16 + FeedPanelView.barHeight).rounded())
    }

    // MARK: Sign-in

    private func showSignIn() {
        hide()
        if signInWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 340, height: 200),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "Sign In to Ring"
            window.isReleasedWhenClosed = false
            window.contentViewController = NSHostingController(
                rootView: SignInWindow(helper: viewer.helper) { [weak self] in
                    self?.signInWindow?.close()
                }
            )
            window.center()
            signInWindow = window
        }
        NSApp.activate()
        signInWindow?.makeKeyAndOrderFront(nil)
    }
}

#if DEBUG
/// Lets a terminal drive the panel and see where it lands, for debugging
/// layout without clicking:
///   swift scripts/panel-debug.swift open|detach|reattach|hide
/// Frames are logged under the "panel" category.
extension PanelController {
    private static let logger = Logger(subsystem: "com.tompreilly.ringdesktopfeed", category: "panel")

    fileprivate func listenForDebugCommands() {
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.tompreilly.ringdesktopfeed.debug"), object: nil, queue: .main
        ) { [weak self] note in
            let command = note.object as? String
            MainActor.assumeIsolated { self?.runDebug(command) }
        }
    }

    private func runDebug(_ command: String?) {
        switch command {
        case "open": showAttached()
        case "detach": detach()
        case "reattach": reattach()
        case "hide": hide()
        default: break
        }
        logFrame("after \(command ?? "?")")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            MainActor.assumeIsolated { self?.logFrame("1s after \(command ?? "?")") }
        }
    }

    func logFrame(_ label: String) {
        let icon = statusItem.button?.window?.frame ?? .zero
        Self.logger.notice("\(label, privacy: .public): panel=\(NSStringFromRect(self.panel.frame), privacy: .public) icon=\(NSStringFromRect(icon), privacy: .public) attachedSize=\(NSStringFromSize(self.attachedSize), privacy: .public)")
    }
}
#endif

/// A panel that can take keyboard focus (for buttons and Esc) without a
/// visible title bar.
final class FeedPanel: NSPanel {
    override var canBecomeKey: Bool { true }

    // AppKit nudges windows when they're ordered front (it moved the
    // attached panel ~190 pt left of the icon). We place it ourselves.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

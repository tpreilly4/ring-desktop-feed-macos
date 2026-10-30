import SwiftUI

/// Whether the feed panel hangs from the menu bar or floats on its own.
@MainActor
@Observable
final class PanelState {
    enum Mode { case attached, detached }

    var mode: Mode = .attached
    /// The stream only runs while the panel is on screen.
    var visible = false
}

/// What the panel's buttons ask the controller to do.
struct PanelActions {
    var detach: () -> Void
    var reattach: () -> Void
    var close: () -> Void
    var toggleOnTop: () -> Void
    var signIn: () -> Void
    var settings: () -> Void
    var layoutChanged: () -> Void
}

/// The one view behind both the menu bar popover and the floating
/// mini-player. It's the same view (and the same web player) in both modes,
/// so detaching and snapping back never restart the stream.
struct FeedPanelView: View {
    let viewer: Viewer
    let panel: PanelState
    let actions: PanelActions
    /// Reports the attached size, so the controller can size the window.
    let onAttachedSize: (CGSize) -> Void

    static let barHeight: CGFloat = 34

    private var helper: Helper { viewer.helper }
    private var attached: Bool { panel.mode == .attached }

    var body: some View {
        // One view tree for both modes, only the modifiers change. An
        // if/else here would give each mode its own web player, and the
        // stream would restart on every switch.
        content
            .background(.regularMaterial)
            .clipShape(.rect(cornerRadius: 12))
            .fixedSize(horizontal: attached, vertical: attached)
            .onGeometryChange(for: CGSize.self, of: \.size) { size in
                if attached { onAttachedSize(size) }
            }
            .task(id: viewer.refreshKey) { await viewer.refresh() }
        // Refetch on every open, so the battery level is current.
        .onChange(of: panel.visible) { _, visible in
            if visible { Task { await viewer.refresh() } }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch (helper.state, helper.client, viewer.signedIn) {
        case (.ready, let client?, true?):
            live(client: client)
        case (.ready, _, false?):
            message { signedOut }
        case (.failed(let text), _, _):
            message {
                Label(text, systemImage: "exclamationmark.triangle").foregroundStyle(.secondary)
                HStack {
                    quitButton
                    Button("Try Again") { helper.retry() }
                        .keyboardShortcut(.defaultAction)
                }
            }
        case (.ready, _, nil) where viewer.error != nil:
            message { cantLoad }
        default:
            message { ProgressView() }
        }
    }

    /// Small states (starting, signed out, errors) get a compact panel.
    private func message(@ViewBuilder _ content: () -> some View) -> some View {
        VStack(spacing: 10, content: content)
            .padding(16)
            .frame(width: 360)
            .frame(minHeight: 120)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func live(client: HelperClient) -> some View {
        VStack(spacing: 0) {
            ZStack {
                Color.black
                if viewer.cameras.isEmpty {
                    cantLoad
                } else {
                    // Keyed by camera, so going to or from "Both" leaves the
                    // stream that's already playing alone.
                    HStack(spacing: 2) {
                        ForEach(viewer.shown) { camera in
                            tile(camera, client: client)
                        }
                    }
                }
            }
            .frame(
                width: attached ? Self.attachedVideoSize(columns: viewer.columns).width : nil,
                height: attached ? Self.attachedVideoSize(columns: viewer.columns).height : nil
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            bar
                .frame(height: Self.barHeight)
        }
    }

    @ViewBuilder
    private func tile(_ camera: Camera, client: HelperClient) -> some View {
        ZStack(alignment: .bottomLeading) {
            if camera.isOffline {
                Label("\(camera.name) is offline", systemImage: "video.slash")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if panel.visible {
                PlayerView(client: client, camera: camera, muted: viewer.muted)
            }
            if viewer.showAll {
                Text(camera.name)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.black.opacity(0.55), in: .rect(cornerRadius: 4))
                    .padding(6)
                    .allowsHitTesting(false)
            }
        }
    }

    private var bar: some View {
        HStack(spacing: 8) {
            if !attached {
                Button("Close", systemImage: "xmark", action: actions.close)
                    .keyboardShortcut(.cancelAction)
            }

            cameraPicker

            ForEach(viewer.shown.filter(\.hasBattery)) { camera in
                BatteryLabel(level: camera.batteryLevel)
            }

            if !helper.ringReachable {
                Label("Can't reach Ring", systemImage: "exclamationmark.triangle.fill")
                    .labelStyle(.titleAndIcon)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize()
            }

            // Empty bar space: in the mini-player, this is what you drag.
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(.rect)
                .gesture(WindowDragGesture(), isEnabled: !attached)

            Button(viewer.muted ? "Unmute" : "Mute",
                   systemImage: viewer.muted ? "speaker.slash.fill" : "speaker.wave.2.fill") {
                viewer.muted.toggle()
            }

            if attached {
                Button("Pop Out", systemImage: "pip.exit", action: actions.detach)
                    .help("Pop out into a floating mini-player")
                Menu("More", systemImage: "ellipsis.circle") {
                    Button("Settings…", action: actions.settings)
                        .keyboardShortcut(",")
                    Divider()
                    Button("Quit Ring Desktop Feed") { NSApplication.shared.terminate(nil) }
                }
                .menuIndicator(.hidden)
                .fixedSize()
            } else {
                Button(viewer.alwaysOnTop ? "Don't Keep on Top" : "Keep on Top",
                       systemImage: viewer.alwaysOnTop ? "pin.fill" : "pin",
                       action: actions.toggleOnTop)
                    .help(viewer.alwaysOnTop ? "Stop keeping on top" : "Keep on top of other windows")
                Button("Back to Menu Bar", systemImage: "pip.enter", action: actions.reattach)
                    .help("Snap back to the menu bar")
            }
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .padding(.horizontal, 10)
    }

    @ViewBuilder
    private var cameraPicker: some View {
        if viewer.cameras.count > 1 {
            Picker("Camera", selection: choice) {
                ForEach(viewer.cameras) { camera in
                    Text(camera.name).tag(Optional(camera.id))
                }
                Text("Both").tag(Int?.none)
            }
            .help("Both streams every camera, which uses the doorbell's battery while open")
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
        }
    }

    /// The picker's value: a camera's id, or nil for "Both".
    private var choice: Binding<Int?> {
        Binding(
            get: { viewer.showAll ? nil : viewer.selectedId },
            set: { id in
                viewer.showAll = id == nil
                if let id { viewer.selectedId = id }
                actions.layoutChanged()
            }
        )
    }

    /// Capped so it still fits on smaller screens.
    static func attachedVideoSize(columns: Int) -> CGSize {
        let screen = NSScreen.main?.visibleFrame.width ?? 1440
        let width = columns > 1 ? min(1040, (screen * 0.85).rounded()) : min(600, (screen * 0.6).rounded())
        return CGSize(width: width, height: videoHeight(width: width, columns: columns))
    }

    /// Each camera keeps 16:9, side by side.
    static func videoHeight(width: CGFloat, columns: Int) -> CGFloat {
        (width / CGFloat(columns) * 9 / 16).rounded()
    }

    // Sign-in lives in a real window: a panel hanging from the menu bar loses
    // focus to the Passwords AutoFill sheet and can't get it back.
    private var signedOut: some View {
        VStack(spacing: 10) {
            Image(systemName: "video.badge.ellipsis").font(.largeTitle).foregroundStyle(.secondary)
            Text("Sign in to Ring to see your cameras.")
            HStack {
                quitButton
                Button("Sign In…", action: actions.signIn)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 120)
    }

    /// Couldn't get the camera list: why, and a way to ask again.
    private var cantLoad: some View {
        VStack(spacing: 8) {
            Text(viewer.error ?? "No cameras found")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Try Again") { Task { await viewer.refresh() } }
        }
        .padding()
    }

    private var quitButton: some View {
        Button("Quit") { NSApplication.shared.terminate(nil) }
    }
}

/// "Battery 72%", with an icon that matches the level.
private struct BatteryLabel: View {
    let level: Double?

    var body: some View {
        Label(text, systemImage: symbol)
            .labelStyle(.titleAndIcon)
            .font(.caption)
            .monospacedDigit()
            .foregroundStyle(isLow ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
            .fixedSize()
    }

    private var text: String {
        guard let level else { return "Battery" }
        return "Battery \(Int(level.rounded()))%"
    }

    private var isLow: Bool { (level ?? 100) < 20 }

    private var symbol: String {
        switch level ?? 75 {
        case ..<13: "battery.0percent"
        case ..<38: "battery.25percent"
        case ..<63: "battery.50percent"
        case ..<88: "battery.75percent"
        default: "battery.100percent"
        }
    }
}

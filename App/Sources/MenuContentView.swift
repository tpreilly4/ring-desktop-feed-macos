import SwiftUI

/// The menu bar popover. Live view runs only while this is on screen.
struct MenuContentView: View {
    let helper: Helper
    @Environment(\.openWindow) private var openWindow

    @State private var signedIn: Bool?
    @State private var cameras: [Camera] = []
    @State private var selected: Camera?
    @State private var muted = true
    @State private var playerState: PlayerState = .idle
    @State private var error: String?
    @State private var visible = false

    var body: some View {
        content
            .background(ExtendFromMenuBarIcon())
            .onAppear { visible = true }
            .onDisappear { visible = false }
            .task(id: RefreshKey(port: helper.client?.port, account: helper.accountChanges)) { await refresh() }
    }

    @ViewBuilder
    private var content: some View {
        switch (helper.state, helper.client, signedIn) {
        case (.ready, let client?, true?):
            liveView(client: client)
        case (.ready, _, false?):
            message { signedOut }
        case (.failed(let text), _, _):
            message {
                Label(text, systemImage: "exclamationmark.triangle").foregroundStyle(.secondary)
                quitButton
            }
        default:
            message { ProgressView() }
        }
    }

    /// Small states (starting, signed out, errors) get a compact popover.
    private func message(@ViewBuilder _ content: () -> some View) -> some View {
        VStack(spacing: 10, content: content)
            .padding(16)
            .frame(width: 360)
            .frame(minHeight: 120)
    }

    /// Edge-to-edge video with one slim control bar underneath.
    private func liveView(client: HelperClient) -> some View {
        VStack(spacing: 0) {
            ZStack {
                Color.black
                if visible, let camera = selected {
                    PlayerView(client: client, camera: camera, muted: muted) { playerState = $0 }
                        .id(camera.id)
                } else if cameras.isEmpty {
                    Text(error ?? "No cameras found").foregroundStyle(.secondary)
                }
            }
            .frame(width: Self.videoWidth, height: Self.videoWidth * 9 / 16)

            HStack(spacing: 8) {
                if cameras.count > 1 {
                    Picker("Camera", selection: $selected) {
                        ForEach(cameras) { camera in
                            Text(camera.name).tag(Optional(camera))
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
                if let selected, selected.hasBattery {
                    Label("Battery", systemImage: "battery.75percent")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(muted ? "Unmute" : "Mute", systemImage: muted ? "speaker.slash.fill" : "speaker.wave.2.fill") {
                    muted.toggle()
                }
                .labelStyle(.iconOnly)
                Menu("More", systemImage: "ellipsis.circle") {
                    Button("Sign Out") {
                        Task {
                            try? await client.signOut()
                            helper.noteAccountChanged()
                        }
                    }
                    Divider()
                    Button("Quit Ring Desktop Feed") { NSApplication.shared.terminate(nil) }
                }
                .labelStyle(.iconOnly)
                .menuIndicator(.hidden)
                .fixedSize()
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
    }

    /// Capped so it still fits on smaller screens.
    private static var videoWidth: CGFloat {
        let screen = NSScreen.main?.visibleFrame.width ?? 1440
        return min(600, (screen * 0.6).rounded())
    }

    // Sign-in lives in a real window: the popover is a transient panel that
    // loses focus to the Passwords AutoFill sheet and can't get it back.
    private var signedOut: some View {
        VStack(spacing: 10) {
            Image(systemName: "video.badge.ellipsis").font(.largeTitle).foregroundStyle(.secondary)
            Text("Sign in to Ring to see your cameras.")
            HStack {
                quitButton
                Button("Sign In…") {
                    openWindow(id: SignInWindow.id)
                    NSApplication.shared.activate()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 120)
    }

    private var quitButton: some View {
        Button("Quit") { NSApplication.shared.terminate(nil) }
    }

    private func refresh() async {
        guard let client = helper.client else { return }
        do {
            signedIn = try await client.isSignedIn()
            guard signedIn == true else { return }
            cameras = try await client.cameras()
            error = nil
            if selected == nil || !cameras.contains(where: { $0.id == selected?.id }) {
                // Default to a wired camera, so opening the popover doesn't
                // wake the doorbell's battery.
                selected = cameras.first { !$0.hasBattery } ?? cameras.first
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private struct RefreshKey: Equatable {
    let port: Int?
    let account: Int
}

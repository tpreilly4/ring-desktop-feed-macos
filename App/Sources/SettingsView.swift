import ServiceManagement
import SwiftUI

struct SettingsView: View {
    let viewer: Viewer
    let toggleOnTop: () -> Void
    let signIn: () -> Void

    @State private var loginStatus = SMAppService.mainApp.status
    @State private var loginError: String?
    @State private var confirmingSignOut = false

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: Binding(
                    get: { loginStatus == .enabled || loginStatus == .requiresApproval },
                    set: setLaunchAtLogin
                ))
                if loginStatus == .requiresApproval {
                    HStack {
                        Text("Needs your approval in System Settings.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Open…") { SMAppService.openSystemSettingsLoginItems() }
                    }
                }
                if let loginError {
                    Text(loginError).font(.callout).foregroundStyle(.red)
                }
                Toggle("Keep mini-player on top", isOn: Binding(
                    get: { viewer.alwaysOnTop },
                    set: { _ in toggleOnTop() }
                ))
            }

            Section("Ring account") {
                if viewer.signedIn == false {
                    LabeledContent("Signed out") {
                        Button("Sign In…", action: signIn)
                    }
                } else {
                    LabeledContent("Signed in") {
                        Button("Sign Out…") { confirmingSignOut = true }
                    }
                }
            }

            Section {
                LabeledContent("Logs") {
                    Button("Show in Finder") { NSWorkspace.shared.open(Helper.logDirectory) }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 380)
        .fixedSize(horizontal: false, vertical: true)
        .confirmationDialog("Sign out of Ring?", isPresented: $confirmingSignOut) {
            Button("Sign Out", role: .destructive) { Task { await viewer.signOut() } }
        } message: {
            Text("Camera alerts stop until you sign in again.")
        }
        .task(id: viewer.refreshKey) { await viewer.refresh() }
        // Approval happens in System Settings, so look again when we come back.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            loginStatus = SMAppService.mainApp.status
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        loginError = nil
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            loginError = error.localizedDescription
        }
        loginStatus = SMAppService.mainApp.status
    }
}

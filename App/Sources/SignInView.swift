import SwiftUI

/// One-time Ring sign-in: email + password, then the 2FA code. The helper
/// keeps the refresh token; the password is never stored.
struct SignInView: View {
    let client: HelperClient
    let onSignedIn: () -> Void

    @State private var email = ""
    @State private var password = ""
    @State private var code = ""
    @State private var codePrompt: String?
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Sign in to Ring").font(.headline)

            if let codePrompt {
                Text(codePrompt).font(.callout).foregroundStyle(.secondary)
                TextField("Code", text: $code)
                    .textContentType(.oneTimeCode)
                    .onSubmit(submit)
            } else {
                TextField("Email", text: $email).textContentType(.username)
                SecureField("Password", text: $password)
                    .textContentType(.password)
                    .onSubmit(submit)
            }

            if let error {
                Text(error).font(.callout).foregroundStyle(.red)
            }

            HStack {
                Spacer()
                if busy { ProgressView().controlSize(.small) }
                Button(codePrompt == nil ? "Sign In" : "Verify", action: submit)
                    .keyboardShortcut(.defaultAction)
                    .disabled(busy || (codePrompt == nil ? email.isEmpty || password.isEmpty : code.isEmpty))
            }

            Text("Uses Ring's unofficial API. Not affiliated with Ring.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .textFieldStyle(.roundedBorder)
    }

    private func submit() {
        busy = true
        error = nil
        Task {
            defer { busy = false }
            do {
                let step = codePrompt == nil
                    ? try await client.signIn(email: email, password: password)
                    : try await client.submitCode(code)
                switch step {
                case .signedIn:
                    password = ""
                    onSignedIn()
                case .needsCode(let prompt):
                    if codePrompt != nil { error = prompt }
                    codePrompt = prompt
                    code = ""
                }
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

/// Hosts the sign-in form in a normal window, where AutoFill works.
struct SignInWindow: View {
    let helper: Helper
    let onDone: () -> Void

    var body: some View {
        Group {
            if let client = helper.client {
                SignInView(client: client) {
                    helper.noteAccountChanged()
                    onDone()
                }
            } else {
                ProgressView("Starting…")
            }
        }
        .padding(20)
        .frame(width: 340)
    }
}

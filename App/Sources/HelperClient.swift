import Foundation

struct Camera: Decodable, Identifiable, Hashable {
    let id: Int
    let name: String
    let model: String
    let hasBattery: Bool
    /// 0–100, nil when Ring doesn't report one.
    let batteryLevel: Double?
    let isOffline: Bool
}

enum SignInStep: Decodable, Equatable {
    case signedIn
    case needsCode(prompt: String)

    private enum CodingKeys: String, CodingKey { case status, prompt }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .status) {
        case "needsCode": self = .needsCode(prompt: try c.decode(String.self, forKey: .prompt))
        default: self = .signedIn
        }
    }
}

struct HelperError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// The helper's local HTTP API.
struct HelperClient: Sendable {
    let port: Int
    let authToken: String

    var baseURL: URL { URL(string: "http://127.0.0.1:\(port)")! }

    /// The player page for one camera. The token rides in the fragment, so it
    /// never appears in a request line or log.
    func playerURL(camera: Camera, muted: Bool) -> URL {
        var components = URLComponents(url: baseURL.appending(path: "player"), resolvingAgainstBaseURL: false)!
        components.fragment = [
            "token=\(authToken)",
            "camera=\(camera.id)",
            // Wired cameras reconnect silently; battery ones wait for "Resume live".
            "autoReconnect=\(camera.hasBattery ? 0 : 1)",
            "muted=\(muted ? 1 : 0)",
        ].joined(separator: "&")
        return components.url!
    }

    func isSignedIn() async throws -> Bool {
        struct Status: Decodable { let signedIn: Bool }
        let status: Status = try await request("GET", "/api/status")
        return status.signedIn
    }

    func cameras() async throws -> [Camera] {
        try await request("GET", "/api/cameras")
    }

    func signIn(email: String, password: String) async throws -> SignInStep {
        try await request("POST", "/api/auth/sign-in", body: ["email": email, "password": password])
    }

    func submitCode(_ code: String) async throws -> SignInStep {
        try await request("POST", "/api/auth/code", body: ["code": code])
    }

    func endLiveView(sessionId: String) async throws {
        struct Ignored: Decodable {}
        let _: Ignored = try await request("DELETE", "/api/live/\(sessionId)")
    }

    func signOut() async throws {
        struct Ignored: Decodable {}
        let _: Ignored = try await request("POST", "/api/auth/sign-out")
    }

    private func request<T: Decodable>(_ method: String, _ path: String, body: [String: String]? = nil) async throws -> T {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = method
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let message = (try? JSONDecoder().decode(ErrorBody.self, from: data))?.error
            throw HelperError(message: message ?? "Helper returned HTTP \(http.statusCode)")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

private struct ErrorBody: Decodable {
    let error: String
}

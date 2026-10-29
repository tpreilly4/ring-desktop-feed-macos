import SwiftUI
import WebKit
import os

private let playerLog = Logger(subsystem: "com.tompreilly.ringdesktopfeed", category: "player")

/// The helper's web player in a WKWebView. Unloading the page ends the Ring
/// session, so this view going away stops the stream.
struct PlayerView: NSViewRepresentable {
    let client: HelperClient
    let camera: Camera
    var muted: Bool
    var onStateChange: (PlayerState) -> Void = { _ in }

    private var url: URL { client.playerURL(camera: camera, muted: muted) }

    func makeCoordinator() -> Coordinator { Coordinator(client: client) }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.mediaTypesRequiringUserActionForPlayback = []
        config.userContentController.add(context.coordinator, name: "rdf")
        let webView = WKWebView(frame: .zero, configuration: config)
        playerLog.notice("make web view for camera \(camera.id)")
        webView.setValue(false, forKey: "drawsBackground")
        webView.load(URLRequest(url: url))
        context.coordinator.loadedCamera = camera.id
        context.coordinator.onStateChange = onStateChange
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.onStateChange = onStateChange
        if context.coordinator.loadedCamera != camera.id {
            context.coordinator.endSession()
            context.coordinator.loadedCamera = camera.id
            webView.load(URLRequest(url: url))
        }
        webView.evaluateJavaScript("window.rdf?.setMuted(\(muted))")
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        playerLog.notice("dismantle web view")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "rdf")
        webView.load(URLRequest(url: URL(string: "about:blank")!))
        // The page may not get to say goodbye, so end the Ring session here too.
        coordinator.endSession()
    }

    final class Coordinator: NSObject, WKScriptMessageHandler {
        let client: HelperClient
        var loadedCamera: Int?
        var sessionId: String?
        var onStateChange: (PlayerState) -> Void = { _ in }

        init(client: HelperClient) { self.client = client }

        func endSession() {
            guard let id = sessionId else { return }
            sessionId = nil
            let client = client
            Task { try? await client.endLiveView(sessionId: id) }
        }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any], let raw = body["state"] as? String else { return }
            if let id = body["sessionId"] as? String { sessionId = id }
            let detail = body["detail"] as? String ?? ""
            playerLog.notice("player state \(raw, privacy: .public) \(detail, privacy: .public)")
            onStateChange(PlayerState(raw: raw, detail: detail))
        }
    }
}

enum PlayerState: Equatable {
    case idle, connecting, live
    case ended(String)
    case error(String)

    init(raw: String, detail: String) {
        switch raw {
        case "connecting": self = .connecting
        case "live": self = .live
        case "ended": self = .ended(detail)
        case "error": self = .error(detail)
        default: self = .idle
        }
    }
}

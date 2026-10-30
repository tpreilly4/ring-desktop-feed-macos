import Foundation
import Observation
import os

/// Runs the bundled Node helper, restarts it if it dies, and relays the
/// events it prints on stdout (port, rotated tokens, sign-out).
@MainActor
@Observable
final class Helper {
    enum State: Equatable {
        case starting
        case ready(port: Int)
        case failed(String)
    }

    /// Camera activity the helper reports.
    enum Activity {
        case motion(cameraId: Int, cameraName: String)
        case ding(cameraId: Int, cameraName: String)
    }

    /// Called on the main actor for every activity event.
    var onActivity: ((Activity) -> Void)?

    private(set) var state: State = .starting
    /// Bumped whenever the Ring account signs in or out, so views refetch.
    private(set) var accountChanges = 0

    /// Random per launch; every API call and the player must present it.
    let authToken = UUID().uuidString + UUID().uuidString

    private var process: Process?
    private var stdin: FileHandle?
    private var restartDelay: Duration = .seconds(1)
    private let logger = Logger(subsystem: "com.tompreilly.ringdesktopfeed", category: "helper")

    var client: HelperClient? {
        guard case .ready(let port) = state else { return nil }
        return HelperClient(port: port, authToken: authToken)
    }

    func start() {
        guard process == nil else { return }
        state = .starting

        guard let dir = Bundle.main.resourceURL?.appending(path: "helper"),
              FileManager.default.isExecutableFile(atPath: dir.appending(path: "node").path)
        else {
            state = .failed("The helper isn't bundled. Run scripts/bootstrap.sh and rebuild.")
            return
        }

        let process = Process()
        process.executableURL = dir.appending(path: "node")
        process.arguments = [dir.appending(path: "dist/main.js").path]
        process.currentDirectoryURL = dir

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = Self.openLogFile() ?? FileHandle.standardError

        let lines = LineSplitter()
        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            for line in lines.feed(handle.availableData) {
                Task { @MainActor in self?.handle(line: line) }
            }
        }

        process.terminationHandler = { [weak self] p in
            Task { @MainActor in self?.didTerminate(status: p.terminationStatus) }
        }

        do {
            try process.run()
        } catch {
            state = .failed("Couldn't start the helper: \(error.localizedDescription)")
            return
        }
        self.process = process
        self.stdin = stdinPipe.fileHandleForWriting

        let config: [String: Any?] = [
            "authToken": authToken,
            "refreshToken": Keychain.readRefreshToken(),
            "port": 0,
        ]
        var data = try! JSONSerialization.data(withJSONObject: config.compactMapValues { $0 })
        data.append(UInt8(ascii: "\n"))
        // Stdin stays open: the helper exits when it closes, i.e. when we do.
        stdinPipe.fileHandleForWriting.write(data)
    }

    func noteAccountChanged() {
        accountChanges += 1
    }

    func stop() {
        process?.terminationHandler = nil
        process?.terminate()
        process = nil
    }

    private func handle(line: Data) {
        guard let event = try? JSONDecoder().decode(HelperEvent.self, from: line) else {
            logger.warning("Unparseable helper output: \(String(decoding: line, as: UTF8.self))")
            return
        }
        switch event.type {
        case "ready":
            if let port = event.port {
                state = .ready(port: port)
                restartDelay = .seconds(1)
            }
        case "refreshToken":
            if let value = event.value { Keychain.saveRefreshToken(value) }
        case "signedOut":
            Keychain.deleteRefreshToken()
            accountChanges += 1
        case "error":
            logger.error("Helper error: \(event.message ?? "")")
        case "motion":
            if let id = event.cameraId {
                onActivity?(.motion(cameraId: id, cameraName: event.cameraName ?? "Camera"))
            }
        case "ding":
            if let id = event.cameraId {
                onActivity?(.ding(cameraId: id, cameraName: event.cameraName ?? "Camera"))
            }
        default:
            break
        }
    }

    private func didTerminate(status: Int32) {
        logger.error("Helper exited with status \(status); restarting")
        process = nil
        state = .starting
        let delay = restartDelay
        restartDelay = min(restartDelay * 2, .seconds(30))
        Task {
            try? await Task.sleep(for: delay)
            start()
        }
    }

    private static func openLogFile() -> FileHandle? {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Logs/RingDesktopFeed")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appending(path: "helper.log")
        if !FileManager.default.fileExists(atPath: file.path) {
            FileManager.default.createFile(atPath: file.path, contents: nil)
        }
        let handle = try? FileHandle(forWritingTo: file)
        handle?.seekToEndOfFile()
        return handle
    }
}

/// Splits a byte stream into newline-terminated lines. Only ever touched from
/// the pipe's (serial) readability handler.
private final class LineSplitter: @unchecked Sendable {
    private var buffer = Data()

    func feed(_ chunk: Data) -> [Data] {
        buffer.append(chunk)
        var lines: [Data] = []
        while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
            lines.append(Data(buffer[..<newline]))
            buffer.removeSubrange(...newline)
        }
        return lines
    }
}

private struct HelperEvent: Decodable {
    let type: String
    let port: Int?
    let value: String?
    let message: String?
    let cameraId: Int?
    let cameraName: String?
}

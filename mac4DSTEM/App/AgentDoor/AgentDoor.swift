//
//  AgentDoor.swift
//  Role: The agent door: a local API through which an agent on this Mac (Claude, Codex, a script) looks at what the app's
//        windows show. Step one is read-only: which windows are open, what each holds, the result and the diffraction pattern
//        as pictures, the detected disks, the recipe and its lineage, the precipitate table.
//
//  Off until the person turns it on in Settings > Agents (`AppPreferences.agentDoorEnabled`). While it is on, the app listens
//  on this Mac's loopback address only (`AgentDoorServer.swift`) and writes one small file, readable by this user's account
//  only, that says where: the port the system picked and a token made new each time the door opens. The MCP bridge
//  (`AgentBridge/`, a separate tool outside the app) reads that file; a request without the token is refused
//  (`AgentDoorGate`). Nothing leaves the Mac and the app sends nothing by itself.
//
//  One door for the process, like `OpenDatasetRegistry`: every dataset window enrols its state when it appears and withdraws
//  it when it closes; windows are held weakly and named `w1`, `w2`, ... in the order they appeared.
//

import Foundation
import Observation
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif

@Observable
final class AgentDoor {
    /// The app's door. Tests make their own, with their own file.
    static let shared = AgentDoor()

    /// The API's version: the `/v1` in every path, and `api` in the door's file.
    static let apiVersion = 1

    enum Status: Equatable {
        case off
        case starting
        case listening(port: UInt16)
        case failed(String)
    }

    private(set) var status: Status = .off
    /// Requests answered since the door last opened (Settings shows it, so the person sees an agent is there).
    private(set) var requestCount = 0

    /// Where the door's file goes; nil writes none (a test that only talks to the port).
    let discoveryURL: URL?
    @ObservationIgnored private var server: AgentDoorServer?
    @ObservationIgnored private(set) var token = ""

    private struct Window {
        let id: String
        weak var state: AppState?
    }
    @ObservationIgnored private var windows: [Window] = []
    @ObservationIgnored private var nextWindowNumber = 1

    init(discoveryURL: URL? = AgentDoor.defaultDiscoveryURL) {
        self.discoveryURL = discoveryURL
    }

    /// `Application Support/mac4DSTEM/agent-door.json`: inside the app's container for the sandboxed app.
    static var defaultDiscoveryURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("mac4DSTEM", isDirectory: true)
            .appendingPathComponent("agent-door.json", isDirectory: false)
    }

    // MARK: Open and close

    /// Opens or closes the door. Asking for the state it already has does nothing, so every window may ask.
    func setEnabled(_ enabled: Bool) {
        if enabled { open() } else { close() }
    }

    private func open() {
        guard server == nil else { return }
        token = Self.makeToken()
        requestCount = 0
        let made = AgentDoorServer { [weak self] request in
            self?.respond(to: request) ?? .error(503, "The agent door is closed.")
        }
        made.onStateChange = { [weak self] new in self?.serverChanged(new) }
        server = made
        made.start()
    }

    private func close() {
        // Only a door that opened takes the file away: another running copy of the app may own the one that is there.
        guard let running = server else { status = .off; return }
        removeDiscoveryFile()
        running.onStateChange = nil
        server = nil
        running.stop()
        token = ""
        status = .off
    }

    private func serverChanged(_ new: AgentDoorServer.State) {
        switch new {
        case .stopped:
            status = .off
        case .starting:
            status = .starting
        case .listening(let port):
            status = .listening(port: port)
            writeDiscoveryFile(port: port)
        case .failed(let why):
            removeDiscoveryFile()
            server?.onStateChange = nil
            server = nil
            status = .failed(why)
        }
    }

    /// 32 random bytes as hex, from the system's generator.
    static func makeToken() -> String {
        var generator = SystemRandomNumberGenerator()
        return (0..<32).map { _ in String(format: "%02x", UInt8.random(in: 0...255, using: &generator)) }.joined()
    }

    // MARK: The door's file

    /// What the bridge reads: the API version, the port, the token, this process. Written whole, then closed to other accounts.
    private func writeDiscoveryFile(port: UInt16) {
        guard let url = discoveryURL else { return }
        let record: [String: Any] = [
            "api": Self.apiVersion,
            "port": Int(port),
            "token": token,
            "pid": Int(ProcessInfo.processInfo.processIdentifier),
            "app": "mac4DSTEM",
            "app_version": FeedbackLinks.appVersion,
        ]
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys, .prettyPrinted])
            try data.write(to: url, options: [.atomic])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            // A door nobody can find is not open: say why instead of listening unseen.
            server?.onStateChange = nil
            server?.stop()
            server = nil
            status = .failed("The door's file could not be written: \(error.localizedDescription)")
        }
    }

    private func removeDiscoveryFile() {
        guard let url = discoveryURL else { return }
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: Windows

    /// A dataset window appeared. A second call for the same window keeps its name.
    func enroll(_ state: AppState) {
        windows.removeAll { $0.state == nil }
        guard !windows.contains(where: { $0.state === state }) else { return }
        windows.append(Window(id: "w\(nextWindowNumber)", state: state))
        nextWindowNumber += 1
    }

    /// A dataset window closed.
    func withdraw(_ state: AppState) {
        windows.removeAll { $0.state == nil || $0.state === state }
    }

    /// The open windows, oldest first.
    var liveWindows: [AgentDoorRouter.Window] {
        windows.compactMap { window in window.state.map { AgentDoorRouter.Window(id: window.id, state: $0) } }
    }

    // MARK: Requests

    /// Answers one request: the gate first, then the router.
    func respond(to request: AgentHTTPRequest) -> AgentHTTPResponse {
        guard case .listening(let port) = status else { return .error(503, "The agent door is closed.") }
        if let refusal = AgentDoorGate.refusal(for: request, token: token, port: port) { return refusal }
        requestCount += 1
        return AgentDoorRouter.respond(to: request, windows: liveWindows)
    }
}

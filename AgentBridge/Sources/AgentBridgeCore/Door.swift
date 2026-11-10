// SPDX-License-Identifier: GPL-3.0-only
//
//  Door.swift
//  Role: The bridge's side of mac4DSTEM's agent door: where the door is (the file the app writes when the door opens, or two
//        environment variables) and one GET to it. The door answers on this Mac's loopback address only and wants its token.
//

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// One answer from the door.
public struct DoorAnswer {
    public var status: Int
    public var contentType: String
    public var body: Data

    public init(status: Int, contentType: String, body: Data) {
        self.status = status
        self.contentType = contentType
        self.body = body
    }
}

/// Why the door could not be asked. `message` is a sentence for the agent to pass on.
public struct DoorError: Error, Equatable {
    public var message: String

    public init(_ message: String) { self.message = message }

    /// The door is closed or the app is not running: what the person does about it.
    public static let closed = DoorError(
        "mac4DSTEM's agent door is not open. Start mac4DSTEM, open Settings > Agents and turn on \"Let agents on this Mac look at open windows\".")
}

/// Asks the door. A protocol so the server is tested without a port.
public protocol Door {
    func get(_ path: String) throws -> DoorAnswer
}

/// Where the door is: its port and its token.
public struct DoorAddress: Equatable {
    public var port: Int
    public var token: String

    public init(port: Int, token: String) {
        self.port = port
        self.token = token
    }

    /// The files the app may have written, most likely first: inside the sandboxed app's container, then the plain
    /// Application Support folder (a build that is not sandboxed).
    public static func candidateFiles(home: URL) -> [URL] {
        [
            home.appendingPathComponent("Library/Containers/com.mac4dstem.mac4DSTEM/Data/Library/Application Support/mac4DSTEM/agent-door.json"),
            home.appendingPathComponent("Library/Application Support/mac4DSTEM/agent-door.json"),
        ]
    }

    /// The door's address from `MAC4DSTEM_AGENT_PORT` and `MAC4DSTEM_AGENT_TOKEN` when both are set, else from the file named by
    /// `MAC4DSTEM_AGENT_DOOR`, else from the first candidate file that reads. Throws `DoorError.closed` when there is none.
    public static func find(environment: [String: String], home: URL) throws -> DoorAddress {
        if let port = environment["MAC4DSTEM_AGENT_PORT"].flatMap({ Int($0) }), let token = environment["MAC4DSTEM_AGENT_TOKEN"], !token.isEmpty {
            return DoorAddress(port: port, token: token)
        }
        let files = environment["MAC4DSTEM_AGENT_DOOR"].map { [URL(fileURLWithPath: $0)] } ?? candidateFiles(home: home)
        for file in files {
            if let data = try? Data(contentsOf: file), let address = parse(data) { return address }
        }
        throw DoorError.closed
    }

    /// The door's file: `{"port": ..., "token": ...}`. nil for anything else.
    public static func parse(_ data: Data) -> DoorAddress? {
        guard let record = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let port = record["port"] as? Int, (1...65535).contains(port),
              let token = record["token"] as? String, !token.isEmpty else { return nil }
        return DoorAddress(port: port, token: token)
    }
}

/// The real door: finds the address on every call (the token is new each time the door opens) and asks over HTTP.
public struct LocalDoor: Door {
    var environment: [String: String]
    var home: URL

    public init(environment: [String: String] = ProcessInfo.processInfo.environment,
                home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.environment = environment
        self.home = home
    }

    public func get(_ path: String) throws -> DoorAnswer {
        let address = try DoorAddress.find(environment: environment, home: home)
        guard let url = URL(string: "http://127.0.0.1:\(address.port)\(path)") else { throw DoorError("Not a path: \(path)") }
        var request = URLRequest(url: url, timeoutInterval: 60)
        request.setValue("Bearer \(address.token)", forHTTPHeaderField: "Authorization")

        final class Box: @unchecked Sendable {
            var data: Data?
            var response: URLResponse?
            var error: Error?
        }
        let box = Box()
        let done = DispatchSemaphore(value: 0)
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            box.data = data
            box.response = response
            box.error = error
            done.signal()
        }
        task.resume()
        done.wait()
        guard box.error == nil, let http = box.response as? HTTPURLResponse else {
            // A file from a door that has since closed (the app quit) names a port nobody listens on.
            throw DoorError.closed
        }
        return DoorAnswer(status: http.statusCode, contentType: http.value(forHTTPHeaderField: "Content-Type") ?? "",
                          body: box.data ?? Data())
    }
}

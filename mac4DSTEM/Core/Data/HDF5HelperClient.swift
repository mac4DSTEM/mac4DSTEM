//
//  HDF5HelperClient.swift
//  Role: the app side of `HDF5HelperXPC`. Every call answers: with the helper's value, with the helper's own sentence,
//        or with `HDF5HelperError` when the helper crashed, hung or could not be reached. Nothing the helper does can
//        end the app (docs/hdf5-helper.md).
//        Off by default (`isEnabled`); slice 2 routes the HDF5 open path through it when the flag is on.
//

import Darwin
import Foundation

package nonisolated enum HDF5HelperError: LocalizedError, Equatable {
    /// The helper ended (a crash, the watchdog, or the connection was lost) before it answered.
    case helperStopped(operation: String)
    /// No answer within the client's limit; the helper is ended so the next call starts a fresh one.
    case timedOut(operation: String, seconds: Double)
    /// The helper answered with its own sentence (a file that is not HDF5, no datacube, a restarted helper).
    case refused(String)
    /// The answer could not be decoded.
    case malformedReply(operation: String)
    /// The helper could not be reached at all (missing from the app, or refused by code signing): a packaging fault.
    case unavailable

    /// The error a proxy reports: an interrupted connection is a helper that ended; any other is one never reached.
    static func connection(_ error: Error, operation: String) -> HDF5HelperError {
        let code = (error as NSError).code
        return code == NSXPCConnectionInterrupted ? .helperStopped(operation: operation) : .unavailable
    }

    package var errorDescription: String? {
        switch self {
        case .helperStopped(let operation):
            return "The HDF5 reader stopped while it was \(operation). The file may be damaged; mac4DSTEM is unaffected."
        case .timedOut(let operation, let seconds):
            return "The HDF5 reader took longer than \(Int(seconds.rounded())) s \(operation) and was stopped. "
                + "The file may be damaged; mac4DSTEM is unaffected."
        case .refused(let sentence):
            return sentence
        case .malformedReply(let operation):
            return "The HDF5 reader gave an unreadable answer while it was \(operation)."
        case .unavailable:
            return "The HDF5 reader could not be started. Reinstall mac4DSTEM."
        }
    }
}

package nonisolated final class HDF5HelperClient: @unchecked Sendable {
    /// The XPC service's bundle identifier (`HDF5Helper.xpc` in Contents/XPCServices).
    package static let serviceName = "com.mac4dstem.mac4DSTEM.HDF5Helper"
    /// The user default that turns the helper on. Off by default: the in-process path is unchanged.
    package static let defaultsKey = "HDF5ReadsInHelper"
    package static var isEnabled: Bool { UserDefaults.standard.bool(forKey: defaultsKey) }

    /// Seconds the helper's watchdog allows one call. The client waits `grace` longer before it gives up itself.
    package let seconds: Double
    private let grace: Double = 2
    private let makeConnection: @Sendable () -> NSXPCConnection
    private let lock = NSLock()
    private var connection: NSXPCConnection?

    /// The embedded XPC service.
    package convenience init(seconds: Double = 30) {
        self.init(seconds: seconds) { NSXPCConnection(serviceName: HDF5HelperClient.serviceName) }
    }

    /// Any connection to an `HDF5HelperXPC` listener (tests: an anonymous listener in process).
    package init(seconds: Double, makeConnection: @escaping @Sendable () -> NSXPCConnection) {
        self.seconds = seconds
        self.makeConnection = makeConnection
    }

    deinit { connection?.invalidate() }

    /// The helper process serving this client right now, 0 when none is connected (tests: it ends after a hang).
    package var helperProcessIdentifier: pid_t { lock.withLock { connection?.processIdentifier ?? 0 } }

    private func liveConnection() -> NSXPCConnection {
        lock.withLock {
            if let connection { return connection }
            let fresh = makeConnection()
            fresh.remoteObjectInterface = NSXPCInterface(with: HDF5HelperXPC.self)
            // A crash interrupts the connection: pending calls fail through their error handlers, and the next message
            // starts the service again. An invalidated connection is replaced at the next call.
            fresh.invalidationHandler = { [weak self, weak fresh] in
                guard let self, let fresh else { return }
                self.drop(fresh)
            }
            fresh.resume()
            connection = fresh
            return fresh
        }
    }

    private func drop(_ stale: NSXPCConnection) {
        lock.withLock { if connection === stale { connection = nil } }
    }

    /// Past the client's limit, which is longer than the helper's own: the helper's watchdog should have ended it
    /// and did not. The helper is sent SIGKILL and the connection dropped. The watchdog is the real line: a sandboxed
    /// app may be refused the signal (EPERM, logged), and then the next connection reaches the same stuck process
    /// until the app quits. The pid is read from this connection only, never a remembered one, so a reused pid is not
    /// signalled.
    private func endHelper(_ stale: NSXPCConnection) {
        let pid = stale.processIdentifier
        if pid > 0, pid != getpid(), kill(pid, SIGKILL) != 0 {
            NSLog("HDF5 helper %d could not be ended: errno %d", pid, errno)
        }
        stale.invalidate()
        drop(stale)
    }

    /// One call: the first of reply, connection error and timeout wins; the others are ignored.
    private func call<T: Sendable>(
        _ operation: String,
        _ body: @escaping @Sendable (HDF5HelperXPC, @escaping @Sendable (Result<T, HDF5HelperError>) -> Void) -> Void
    ) async throws -> T {
        let link = liveConnection()
        let limit = seconds + grace
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, Error>) in
            let once = Once(continuation)
            let proxy = link.remoteObjectProxyWithErrorHandler { error in
                once.finish(.failure(.connection(error, operation: operation)))
            }
            guard let helper = proxy as? HDF5HelperXPC else {
                once.finish(.failure(.unavailable))
                return
            }
            let reported = seconds
            let stale = ConnectionBox(link)   // NSXPCConnection is thread-safe but not marked Sendable
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + limit) { [weak self] in
                if once.finish(.failure(.timedOut(operation: operation, seconds: reported))) { self?.endHelper(stale.connection) }
            }
            body(helper) { once.finish($0) }
        }
    }

    /// Opens `url` in the helper; the handle names it in later calls. The file crosses as a bookmark
    /// (`HDF5HelperBookmark`), made here while the app can read the file: call it while accessing a security-scoped URL.
    package func open(_ url: URL) async throws -> Int {
        let seconds = seconds
        let bookmark: Data
        do {
            bookmark = try HDF5HelperBookmark.make(url)
        } catch {
            throw HDF5HelperError.refused("The file could not be passed to the HDF5 reader: \(error.localizedDescription)")
        }
        return try await call("opening the file") { helper, done in
            helper.open(bookmark: bookmark, seconds: seconds) { handle, sentence in
                if handle > 0 { done(.success(handle)) } else { done(.failure(.refused(sentence ?? "The file could not be opened."))) }
            }
        }
    }

    /// The primary datacube as the in-process `H5Reader` would describe it, named by the app's `filePath`.
    package func describePrimaryDataset(handle: Int, filePath: String) async throws -> DatasetDescriptor {
        let seconds = seconds
        let dataset: HDF5HelperDataset = try await call("reading the file structure") { helper, done in
            helper.describePrimaryDataset(handle: handle, seconds: seconds) { json, sentence in
                guard let json else { done(.failure(.refused(sentence ?? "The file has no readable datacube."))); return }
                guard let value = try? JSONDecoder().decode(HDF5HelperDataset.self, from: json) else {
                    done(.failure(.malformedReply(operation: "reading the file structure")))
                    return
                }
                done(.success(value))
            }
        }
        return dataset.descriptor(filePath: filePath)
    }

    /// Releases the handle. A helper that is gone has released it already, so failures are ignored.
    package func close(handle: Int) async {
        _ = try? await call("closing the file") { (helper, done: @escaping @Sendable (Result<Bool, HDF5HelperError>) -> Void) in
            helper.close(handle: handle) { done(.success(true)) }
        }
    }

    /// Tests only: asks a Debug helper to crash or hang (`HDF5HelperFault`). Throws what any call would throw then;
    /// returns false when the helper does not honour faults (a Release build, or the service in process).
    @discardableResult
    package func injectFault(_ fault: HDF5HelperFault) async throws -> Bool {
        let seconds = seconds
        return try await call("running a test fault") { (helper, done: @escaping @Sendable (Result<Bool, HDF5HelperError>) -> Void) in
            helper.injectFault(fault.rawValue, seconds: seconds) { done(.success($0)) }
        }
    }

    /// Ends the connection; the helper exits when no client holds one.
    package func invalidate() {
        let current = lock.withLock { () -> NSXPCConnection? in
            defer { connection = nil }
            return connection
        }
        current?.invalidate()
    }
}

private nonisolated struct ConnectionBox: @unchecked Sendable {
    let connection: NSXPCConnection
    init(_ connection: NSXPCConnection) { self.connection = connection }
}

/// Resumes a continuation once; later results are dropped. `finish` returns whether this result was the one taken.
private nonisolated final class Once<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Error>?

    init(_ continuation: CheckedContinuation<T, Error>) { self.continuation = continuation }

    @discardableResult
    func finish(_ result: Result<T, HDF5HelperError>) -> Bool {
        guard let taken = lock.withLock({ () -> CheckedContinuation<T, Error>? in
            defer { continuation = nil }
            return continuation
        }) else { return false }
        taken.resume(with: result.mapError { $0 as Error })
        return true
    }
}

//
//  HDF5HelperService.swift
//  Role: the helper side of `HDF5HelperXPC`: the app's own `H5Reader` (FormatoKit's `HDF5Reader` under `HDF5Serial`)
//        driven from XPC messages. `HDF5Helper/main.swift` vends it from the XPC service; tests also vend it in process
//        over an anonymous listener (`isolated: false`), where nothing may end the process.
//

import Darwin
import Foundation

package nonisolated final class HDF5HelperService: NSObject, HDF5HelperXPC, @unchecked Sendable {
    /// True in the helper process: a watchdog that fires and an injected fault end the process. False in process.
    private let isolated: Bool
    private let lock = NSLock()
    private var readers: [Int: OpenFile] = [:]

    /// A file the helper holds: the reader, and the security scope it opened the file under.
    private struct OpenFile {
        let reader: H5Reader
        let url: URL
        let scoped: Bool
    }
    /// Every libhdf5 call of this process, one at a time in arrival order (libhdf5 is serial anyway). The watchdog of
    /// a call starts when its turn comes, so waiting behind another client's long read never counts against it.
    private let work = DispatchQueue(label: "HDF5HelperService.work", qos: .userInitiated)

    package init(isolated: Bool) {
        self.isolated = isolated
    }

    /// A handle no other helper process hands out: random, so a handle kept from a helper that crashed can never name
    /// a file the restarted helper opened since (it is refused as unknown instead).
    private func newHandle() -> Int {
        lock.withLock {
            var handle = Int.random(in: 1...Int.max)
            while readers[handle] != nil { handle = Int.random(in: 1...Int.max) }
            return handle
        }
    }

    /// Runs `body` on the work queue under a watchdog armed when it starts. Past `seconds` the helper process ends
    /// with exit code 70: a libhdf5 call that does not return cannot be cancelled. The watchdog is disarmed before
    /// `reply` runs, so it can never end the process after an answer was sent. In process it never ends anything;
    /// the client's own timeout answers.
    private func watched(_ seconds: Double, _ body: @escaping @Sendable () async -> Void, reply: @escaping @Sendable () -> Void) {
        let isolated = isolated
        work.async {
            let timer = DispatchSource.makeTimerSource(queue: .global(qos: .userInitiated))
            timer.schedule(deadline: .now() + max(0.05, seconds))
            timer.setEventHandler { if isolated { _exit(70) } }
            timer.resume()
            // The reader is an actor; this queue waits for it, so libhdf5 work stays one call at a time.
            let finished = DispatchSemaphore(value: 0)
            Task.detached(priority: .userInitiated) {   // the queue's own QoS: no priority inversion while it waits
                await body()
                finished.signal()
            }
            finished.wait()
            timer.cancel()
            reply()
        }
    }

    package func open(bookmark: Data, seconds: Double, reply: @escaping @Sendable (Int, String?) -> Void) {
        let outcome = Outcome<(Int, String?)>((0, "The file could not be opened."))
        watched(seconds, { [self] in
            let url: URL
            do {
                url = try HDF5HelperBookmark.resolve(bookmark)
            } catch {
                outcome.set((0, "The HDF5 reader could not reach the file: \(error.localizedDescription)"))
                return
            }
            // Held for as long as the file is open; released by `close` (false when the URL needs no scope, as in
            // process or for a file the helper may read anyway).
            let scoped = url.startAccessingSecurityScopedResource()
            do {
                let reader = try H5Reader(path: url.path)
                let handle = newHandle()
                lock.withLock { readers[handle] = OpenFile(reader: reader, url: url, scoped: scoped) }
                outcome.set((handle, nil))
            } catch {
                if scoped { url.stopAccessingSecurityScopedResource() }
                outcome.set((0, error.localizedDescription))
            }
        }, reply: { let (handle, sentence) = outcome.value; reply(handle, sentence) })
    }

    package func describePrimaryDataset(handle: Int, seconds: Double, reply: @escaping @Sendable (Data?, String?) -> Void) {
        guard let reader = lock.withLock({ readers[handle]?.reader }) else {
            reply(nil, Self.unknownHandle)
            return
        }
        let outcome = Outcome<(Data?, String?)>((nil, "The file structure could not be read."))
        watched(seconds, {
            do {
                let descriptor = try await reader.discoverPrimaryDataset()
                outcome.set((try JSONEncoder().encode(HDF5HelperDataset(descriptor)), nil))
            } catch {
                outcome.set((nil, error.localizedDescription))
            }
        }, reply: { let (json, sentence) = outcome.value; reply(json, sentence) })
    }

    /// Releases the handle on the work queue, under the watchdog: the reader's last reference closes the file in
    /// libhdf5, which can hang like any other call.
    package func close(handle: Int, reply: @escaping @Sendable () -> Void) {
        watched(5, { [self] in
            var file = lock.withLock { readers.removeValue(forKey: handle) }
            let access = file.map { ($0.url, $0.scoped) }
            file = nil   // usually the reader's last reference; a finishing describe task may hold it a moment longer,
                         // which is harmless: ending the scope does not close a file libhdf5 already has open
            if let (url, scoped) = access, scoped { url.stopAccessingSecurityScopedResource() }
        }, reply: reply)
    }

    /// Replies whether the fault is honoured: only a Debug build of the helper process does. A crash ends the process
    /// before it replies; a hang never replies and the watchdog ends the process.
    package func injectFault(_ kind: Int, seconds: Double, reply: @escaping @Sendable (Bool) -> Void) {
        #if DEBUG
        guard isolated, let fault = HDF5HelperFault(rawValue: kind) else { reply(false); return }
        switch fault {
        case .crash:
            _exit(71)   // as a libhdf5 crash ends the process; `_exit`, so no crash report is written on every test run
        case .hang:
            watched(seconds, {
                // Never returns, as a libhdf5 call stuck on a crafted file would.
                while true { pause() }
            }, reply: { reply(true) })
        }
        #else
        reply(false)
        #endif
    }

    /// The sentence for a handle the helper does not hold: the helper was restarted after a crash or a hang, so the
    /// file must be opened again.
    package static let unknownHandle = "The HDF5 helper no longer holds this file (it was restarted). Open the file again."
}

/// A value written by the work and read by the reply, which the work queue orders after it.
private nonisolated final class Outcome<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: T
    init(_ initial: T) { stored = initial }
    func set(_ value: T) { lock.withLock { stored = value } }
    var value: T { lock.withLock { stored } }
}

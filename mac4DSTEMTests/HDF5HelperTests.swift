//
//  HDF5HelperTests.swift
//  The HDF5 helper, slice 1 (docs/hdf5-helper.md): open, describe and close over XPC give what the in-process reader
//  gives, and a helper that crashes or hangs is an error the app receives, never the end of the app.
//  The in-process cases vend `HDF5HelperService` on an anonymous listener; the isolation cases talk to the embedded
//  `HDF5Helper.xpc` (the test host is the app, so its Contents/XPCServices is where the service is found).
//

import XCTest
import DSTEMCore

nonisolated final class AnonymousHelperListener: NSObject, NSXPCListenerDelegate, @unchecked Sendable {
    let listener = NSXPCListener.anonymous()
    let service = HDF5HelperService(isolated: false)

    override init() {
        super.init()
        listener.delegate = self
        listener.resume()
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: HDF5HelperXPC.self)
        connection.exportedObject = service
        connection.resume()
        return true
    }

    func client(seconds: Double = 10) -> HDF5HelperClient {
        let endpoint = listener.endpoint
        return HDF5HelperClient(seconds: seconds) { NSXPCConnection(listenerEndpoint: endpoint) }
    }
}

final class HDF5HelperTests: XCTestCase {
    private static let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("Fixtures/H5Reader")
    private let cube = HDF5HelperTests.fixtures.appendingPathComponent("emd_dims_f32.h5")
    private let notHDF5 = HDF5HelperTests.fixtures.appendingPathComponent("odd_not_hdf5.h5")

    // MARK: The protocol, in process

    /// The helper describes the datacube exactly as the in-process reader does (readers are tested exact).
    func testDescribeMatchesTheInProcessReader() async throws {
        let host = AnonymousHelperListener()
        let client = host.client()
        defer { client.invalidate() }
        let expected = try await H5Reader(path: cube.path).discoverPrimaryDataset()
        let handle = try await client.open(cube)
        let described = try await client.describePrimaryDataset(handle: handle, filePath: cube.path)
        XCTAssertEqual(HDF5HelperDataset(described), HDF5HelperDataset(expected))
        XCTAssertEqual(described.filePath, cube.path)
        await client.close(handle: handle)
    }

    /// A file that is not HDF5 is refused with the in-process reader's own sentence.
    func testAFileThatIsNotHDF5IsRefusedWithTheReadersSentence() async throws {
        let host = AnonymousHelperListener()
        let client = host.client()
        defer { client.invalidate() }
        var inProcess = ""
        do { _ = try H5Reader(path: notHDF5.path) } catch { inProcess = error.localizedDescription }
        XCTAssertFalse(inProcess.isEmpty, "precondition: the in-process reader refuses the file")
        do {
            _ = try await client.open(notHDF5)
            XCTFail("the helper opened a file that is not HDF5")
        } catch let error as HDF5HelperError {
            XCTAssertEqual(error, .refused(inProcess))
        }
    }

    /// A closed (or never opened) handle is refused with a sentence, not a crash.
    func testAClosedHandleIsRefused() async throws {
        let host = AnonymousHelperListener()
        let client = host.client()
        defer { client.invalidate() }
        let handle = try await client.open(cube)
        await client.close(handle: handle)
        do {
            _ = try await client.describePrimaryDataset(handle: handle, filePath: cube.path)
            XCTFail("a closed handle was described")
        } catch let error as HDF5HelperError {
            XCTAssertEqual(error, .refused(HDF5HelperService.unknownHandle))
        }
    }

    /// In process the service refuses every fault: nothing may end the app.
    func testFaultsAreRefusedInProcess() async throws {
        let host = AnonymousHelperListener()
        let client = host.client()
        defer { client.invalidate() }
        let crashed = try await client.injectFault(.crash)
        let hung = try await client.injectFault(.hang)
        XCTAssertFalse(crashed)
        XCTAssertFalse(hung)
    }

    // MARK: Isolation, in the embedded XPC service

    private func embeddedServiceOrSkip() throws {
        let services = Bundle.main.bundleURL.appendingPathComponent("Contents/XPCServices/HDF5Helper.xpc")
        guard FileManager.default.fileExists(atPath: services.path) else {
            throw XCTSkip("HDF5Helper.xpc is not embedded in the test host \(Bundle.main.bundleURL.lastPathComponent)")
        }
    }

    /// The real helper process gives the same description as the in-process reader.
    func testTheEmbeddedHelperDescribesTheCube() async throws {
        try embeddedServiceOrSkip()
        let client = HDF5HelperClient(seconds: 20)
        defer { client.invalidate() }
        let expected = try await H5Reader(path: cube.path).discoverPrimaryDataset()
        let handle = try await client.open(cube)
        XCTAssertGreaterThan(client.helperProcessIdentifier, 0, "no helper process is connected")
        XCTAssertNotEqual(client.helperProcessIdentifier, getpid(), "the helper ran in the app process")
        let described = try await client.describePrimaryDataset(handle: handle, filePath: cube.path)
        XCTAssertEqual(HDF5HelperDataset(described), HDF5HelperDataset(expected))
        await client.close(handle: handle)
    }

    /// A Debug helper honours faults; anything else answers false at once, and the fault tests skip.
    private func injectOrSkip(_ client: HDF5HelperClient, _ fault: HDF5HelperFault) async throws {
        if try await client.injectFault(fault) {
            XCTFail("the helper answered after the \(fault) fault")
        } else {
            throw XCTSkip("the helper does not honour test faults (not a Debug build)")
        }
    }

    /// The helper crashes: the app gets `helperStopped` and lives; the next call reaches a fresh helper, which no
    /// longer holds the old handle, even after it opened another file (handles are never reused across restarts).
    func testAHelperCrashIsAnErrorAndTheNextCallWorks() async throws {
        try embeddedServiceOrSkip()
        let client = HDF5HelperClient(seconds: 20)
        defer { client.invalidate() }
        let handle = try await client.open(cube)
        do {
            try await injectOrSkip(client, .crash)
        } catch let error as HDF5HelperError {
            XCTAssertEqual(error, .helperStopped(operation: "running a test fault"))
        }
        let other = HDF5HelperTests.fixtures.appendingPathComponent("emd_dims_f64.h5")
        _ = try await client.open(other)
        do {
            _ = try await client.describePrimaryDataset(handle: handle, filePath: cube.path)
            XCTFail("a restarted helper described a handle of the old one")
        } catch let error as HDF5HelperError {
            XCTAssertEqual(error, .refused(HDF5HelperService.unknownHandle))
        }
        let reopened = try await client.open(cube)
        _ = try await client.describePrimaryDataset(handle: reopened, filePath: cube.path)
    }

    /// The helper hangs: the watchdog ends it within its limit, the app gets an error in bounded time, and the next
    /// call reaches a fresh helper.
    func testAHelperHangIsCutAndTheNextCallWorks() async throws {
        try embeddedServiceOrSkip()
        // A generous client to reach the helper (a relaunch after the crash test can take seconds while the crash is
        // reported) and a one-second one for the hang: both talk to the one helper process of this app.
        let client = HDF5HelperClient(seconds: 20)
        let impatient = HDF5HelperClient(seconds: 1)
        defer { client.invalidate(); impatient.invalidate() }
        _ = try await client.open(cube)
        let hungPID = client.helperProcessIdentifier
        let start = Date()
        do {
            try await injectOrSkip(impatient, .hang)
        } catch let error as HDF5HelperError {
            switch error {
            case .helperStopped, .timedOut: break
            default: XCTFail("unexpected \(error)")
            }
        }
        let cut = Date()
        XCTAssertLessThan(cut.timeIntervalSince(start), 6, "the hang was not cut")
        // launchd starts a service again no sooner than 10 s after its previous launch (measured: cut after 1.0 s,
        // helper back after 10.0 s), so the next call may wait that long; it must not wait for ever.
        let handle = try await client.open(cube)
        XCTAssertLessThan(Date().timeIntervalSince(cut), 15, "the helper did not come back")
        _ = try await client.describePrimaryDataset(handle: handle, filePath: cube.path)
        XCTAssertNotEqual(client.helperProcessIdentifier, hungPID, "the hung helper still serves")
    }
}

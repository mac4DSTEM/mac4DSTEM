//
//  MainActorOffloadTests.swift
//  Lane B of the 2026-10-07 SwiftUI review: concurrency hygiene.
//

import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM
import FormatoHDF5
import SpectroCore

@MainActor
final class MainActorOffloadTests: XCTestCase {

    /// B1: closing a window cancels the operation it is running and the load it has in flight.
    func testWindowClosedCancelsTheActiveOperationAndTheLoad() {
        let state = AppState()
        let operation = state.beginCancellableOperation("Test run", status: "Running")
        let load = state.beginDatasetLoading("Opening…")
        XCTAssertFalse(operation.isCancelled)
        XCTAssertFalse(load.isCancelled)

        state.windowClosed()

        XCTAssertTrue(operation.isCancelled, "a closed window must not keep its operation running")
        XCTAssertTrue(load.isCancelled, "a closed window must ask its dataset load to unwind")
        XCTAssertFalse(state.operationCenter.isCurrent(operation),
                       "the cancelled operation is no longer the current one")
    }

    func testWindowClosedWithNothingRunningIsHarmless() {
        let state = AppState()
        state.windowClosed()
        XCTAssertFalse(state.isBusy)
        XCTAssertFalse(state.datasetSession.isLoading)
    }

    /// B2: opening a file must not block the main actor behind the global HDF5 lock. Another thread holds the
    /// lock and gives it up only once the MAIN ACTOR has proved it still runs: a main-actor sleep started after the
    /// open began wakes, and then signals the holder. If `makeReader` ran on the main thread it would sit in the
    /// lock's `acquire` with the main thread blocked, the sleep could never wake, and the holder would give up on
    /// its own timeout without the signal (no timing threshold: only the 60 s backstops, long enough for a busy CI runner,
    /// where the test process's main actor and the lock can still be held by an earlier test's tail).
    func testMakeReaderWaitsForTheHDF5LockOffTheMainActor() async throws {
        // A real, readable HDF5 cube (written before the lock is taken): the route accepts it, so the open goes on
        // past the sniff into `H5Reader(path:)`, which takes the lock again. A file the sniff refused would never
        // reach the reader, and the test would prove only the sniff.
        let url = try await writeSmallCube()
        defer { try? FileManager.default.removeItem(at: url) }

        let held = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        let signalled = Flag()
        let holder = Thread {
            HDF5Serial.acquire()
            held.signal()
            signalled.set(release.wait(timeout: .now() + 60) == .success)
            HDF5Serial.release()
        }
        holder.start()
        XCTAssertEqual(held.wait(timeout: .now() + 60), .success)

        // The route sniffs the file (under the lock) and the HDF5 reader opens it (under the lock), both off the main actor.
        let open = Task { try? await AppState.makeReader(for: url) }
        try await Task.sleep(nanoseconds: 200_000_000)   // the main actor is alive while the open waits on the lock
        release.signal()
        let reader = await open.value
        XCTAssertTrue(signalled.value, "the main actor was blocked behind the HDF5 lock while the file opened")
        XCTAssertTrue(reader is H5Reader, "the open must reach the HDF5 reader, not stop at the sniff")
    }

    /// B2, the reader itself: building the reader is file I/O (a DM4 map, a MIB or EMPAD header, the HDF5 open), so
    /// `makeReader` must finish while the main thread is busy. The main thread blocks on a semaphore that only the
    /// finished open signals. A main-actor `makeReader` (the project's default isolation without `@concurrent`) could
    /// not start until the wait gave up, and the test fails; the lock test above cannot see that, because
    /// `H5Reader(path:)` takes no HDF5 lock once libhdf5 is loaded.
    func testMakeReaderFinishesWhileTheMainThreadIsBlocked() async throws {
        let url = try await writeSmallCube()
        defer { try? FileManager.default.removeItem(at: url) }
        let done = DispatchSemaphore(value: 0)
        let reachedReader = Flag()
        let open = Task.detached {
            let reader = try? await AppState.makeReader(for: url)
            reachedReader.set(reader is H5Reader)
            done.signal()
        }
        let finished = done.wait(timeout: .now() + 30) == .success   // blocks the main thread on purpose
        await open.value
        XCTAssertTrue(finished, "makeReader needed the main thread to build the reader")
        XCTAssertTrue(reachedReader.value, "the open must reach the HDF5 reader")
    }

    /// A real, readable 2 x 2-position HDF5 cube of the demo patterns, written as py4DSTEM EMD.
    private func writeSmallCube() async throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("offload-\(UUID().uuidString).h5")
        let source = DemoFourDDataSource()
        let descriptor = try await source.discoverPrimaryDataset()
        _ = try await BraggVectorEMDWriter.writeCalibratedDataCube(
            source: source, view: LoadView(fullExtentOf: descriptor), calibration: PixelCalibration(),
            options: CalibratedDataCubeExportOptions(scanY: 0..<2, scanX: 0..<2), to: url)
        return url
    }

    private nonisolated final class Flag: @unchecked Sendable {
        private let lock = NSLock()
        private var stored = false
        nonisolated func set(_ v: Bool) { lock.lock(); stored = v; lock.unlock() }
        nonisolated var value: Bool { lock.lock(); defer { lock.unlock() }; return stored }
    }

    // MARK: B3 — heavy entry points leave the main actor on their own

    /// Where each progress callback ran: `true` for the main thread.
    private nonisolated final class ThreadLog: @unchecked Sendable {
        private let lock = NSLock()
        private var samples: [Bool] = []
        nonisolated func record() { let main = Thread.isMainThread; lock.lock(); samples.append(main); lock.unlock() }
        nonisolated var count: Int { lock.lock(); defer { lock.unlock() }; return samples.count }
        nonisolated var onMain: Int { lock.lock(); defer { lock.unlock() }; return samples.filter { $0 }.count }
    }

    private func makeCube() async throws -> (data: FourDArray, descriptor: DatasetDescriptor) {
        let source = SyntheticCubeSource()
        let descriptor = try await source.discoverPrimaryDataset()
        return (FourDArray(reader: source, descriptor: descriptor), descriptor)
    }

    /// Each of these is called straight from this `@MainActor` test with no `Task.detached`. Before they were
    /// `@concurrent`, a `nonisolated async` callee ran on the caller's actor (SE-0461) and its progress callbacks
    /// fired on the main thread: the owner's frozen run measured 847 of 847 samples there.
    func testDetectAllLeavesTheMainThread() async throws {
        let (data, d) = try await makeCube()
        let log = ThreadLog()
        var params = DiskDetectionParams()
        params.edgeBoundary = 1
        params.minPeakSpacing = 2
        let kernel = try XCTUnwrap(ProbeKernel.synthetic(radius: 2, qy: d.qy, qx: d.qx))
        let result = try await DiskDetection.detectAll(
            data: data, descriptor: d, kernel: kernel, params: params, maximumTileRows: 2,
            progress: { _ in log.record() })
        XCTAssertNotNil(result)
        XCTAssertGreaterThan(log.count, 0, "the run must report progress for this test to see a thread")
        XCTAssertEqual(log.onMain, 0, "detectAll ran on the main thread")
    }

    func testDiffractionEmbeddingLeavesTheMainThread() async throws {
        let (data, d) = try await makeCube()
        let log = ThreadLog()
        let result = try await DiffractionEmbedding.compute(
            data: data, descriptor: d, settings: .init(binnedSize: 4, components: 2, groups: 2),
            maximumTileRows: 2, cancellation: nil, progress: { _ in log.record() })
        XCTAssertNotNil(result)
        XCTAssertGreaterThan(log.count, 0)
        XCTAssertEqual(log.onMain, 0, "DiffractionEmbedding.compute ran on the main thread")
    }

    func testOriginCalibrationTiledRunLeavesTheMainThread() async throws {
        let (data, d) = try await makeCube()
        let log = ThreadLog()
        let result = try await OriginCalibration.tiledRun(
            data: data, descriptor: d, maximumTileRows: 2, progress: { _ in log.record() })
        XCTAssertNotNil(result)
        XCTAssertGreaterThan(log.count, 0)
        XCTAssertEqual(log.onMain, 0, "OriginCalibration.tiledRun ran on the main thread")
    }
}

/// An 8 x 4 scan of 16 x 16 patterns: a bright disk on a deterministic texture, different at every position.
private actor SyntheticCubeSource: FourDDataSource {
    private let shape = [8, 4, 16, 16]
    private var qy: Int { shape[2] }
    private var qx: Int { shape[3] }

    private func pattern(ry: Int, rx: Int) -> [Float] {
        var out = [Float](repeating: 0, count: qy * qx)
        for y in 0 ..< qy {
            for x in 0 ..< qx {
                let r = ((Float(y) - 8) * (Float(y) - 8) + (Float(x) - 8) * (Float(x) - 8)).squareRoot()
                let texture = Float((y * 31 + x * 17 + ry * 7 + rx * 13) % 11)
                out[y * qx + x] = (r < 3 ? 200 : 0) + texture
            }
        }
        return out
    }

    func discoverPrimaryDataset() throws -> DatasetDescriptor {
        DatasetDescriptor(filePath: "/synthetic/cube.h5", datasetPath: "/data",
                          shape: shape, dtypeDescription: "float32", chunkShape: nil)
    }
    nonisolated func loadPushdown(for view: LoadView) -> LoadPushdown { .none }
    func readPattern(_ view: LoadView, ry: Int, rx: Int) throws -> [Float] { pattern(ry: ry, rx: rx) }
    func readScanRow(_ view: LoadView, ry: Int) throws -> [Float] {
        (0 ..< view.descriptor.rx).flatMap { pattern(ry: ry, rx: $0) }
    }
    func readScanTile(_ view: LoadView, yRange: Range<Int>) throws -> FourDScanTile {
        var pixels: [Float] = []
        for ry in yRange { for rx in 0 ..< view.descriptor.rx { pixels += pattern(ry: ry, rx: rx) } }
        return FourDScanTile(yRange: yRange, scanWidth: view.descriptor.rx,
                             detectorHeight: qy, detectorWidth: qx, pixels: pixels)
    }
    func readDoubleAttribute(_ name: String, onObjectPath path: String) -> Double? { nil }
    func pixelCalibration() -> PixelCalibration? { nil }
}

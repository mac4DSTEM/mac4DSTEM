import XCTest
@testable import mac4DSTEM

/// Pins `DatasetResidency` — the state L2 adds, extracted into its own type
/// rather than added to the `AppState` facade
/// (`docs/development-process.md` §7).
///
/// The property every test here defends is the same one: **the published flags
/// describe the buffer, never the request.** A `DatasetResidency` that says
/// "Resident" about a cube being streamed would put a confident wrong claim in
/// the Performance panel, and — worse — would be believed later when someone
/// asks why two machines disagree about a number.
///
/// These force `.resident` rather than relying on `.automatic`. The development
/// machine is an 8 GB M3 MacBook Air whose Metal working set cannot hold either
/// real cube, and `.automatic` streams anyway while the admission threshold is
/// unmeasured — so an admission-gated test would assert nothing while appearing
/// to pass. Same seam, same reason, as `tools/virtual-detector-residency`.
@MainActor
final class DatasetResidencyTests: XCTestCase {

    private func demoArray() async throws -> (FourDArray, DatasetDescriptor) {
        let source = DemoFourDDataSource()
        let descriptor = try await source.discoverPrimaryDataset()
        return (FourDArray(reader: source, descriptor: descriptor), descriptor)
    }

    // MARK: What is published is what is held

    func testPreloadPublishesTheBufferItActuallyHolds() async throws {
        let (data, descriptor) = try await demoArray()
        let residency = DatasetResidency()
        await residency.request(.resident, on: data)

        let held = await residency.preload(data) { _ in }

        XCTAssertTrue(held)
        XCTAssertTrue(residency.isResident)
        XCTAssertEqual(residency.byteCount, descriptor.byteCountAsFloat32,
                       "Byte count must be the float32 working size of the cube")
        let arraySays = await data.isResident
        XCTAssertEqual(residency.isResident, arraySays,
                       "The published flag disagreed with the array it describes")

        // The half that actually discriminates. Everything above is also true
        // of an implementation that just echoes the request — verified: with
        // `sync` rewritten to publish `mode != .streamed`, every assertion above
        // still passed. Only a state where the request and the buffer DISAGREE
        // tells them apart, so force one: release the cube while the request is
        // still `.resident`.
        await residency.release(data)
        XCTAssertEqual(residency.mode, .resident,
                       "Releasing must not rewrite what was requested")
        XCTAssertFalse(
            residency.isResident,
            "isResident echoed the request instead of the buffer: the request is "
            + "still .resident but the array is streaming"
        )
        XCTAssertEqual(residency.byteCount, 0)
    }

    func testPreloadProgressIsMeasuredMonotonicAndEndsExactlyAtOne() async throws {
        let (data, _) = try await demoArray()
        let residency = DatasetResidency()
        await residency.request(.resident, on: data)

        let recorded = Box()
        await residency.preload(data) { recorded.values.append($0) }

        XCTAssertFalse(recorded.values.isEmpty, "The preload reported no progress")
        XCTAssertEqual(try XCTUnwrap(recorded.values.last), 1.0, accuracy: 1e-12,
                       "The preload must land exactly on 1.0, not near it")
        for (previous, next) in zip(recorded.values, recorded.values.dropFirst()) {
            XCTAssertGreaterThanOrEqual(
                next, previous, "Progress went backwards: \(recorded.values)"
            )
        }
        XCTAssertNil(residency.preloadFraction,
                     "preloadFraction must clear when the preload ends")
        XCTAssertFalse(residency.isPreloading)
    }

    // MARK: Refusal is silent, not a 0% flash

    /// A refused preload must publish *nothing*. Showing a determinate 0% bar
    /// for a read that is not going to happen is the fabricated-waypoint defect
    /// L1 removed, reintroduced one layer down (invariant I5).
    ///
    /// **What this does and does not pin.** It pins that no progress is
    /// *reported* and that nothing is left published afterwards. It does NOT
    /// pin the transient: a `preloadFraction = 0` set on entry and cleared by
    /// the `defer` would still pass here, because an in-process test cannot
    /// observe a value that exists only between two awaits. That gap is real
    /// and is stated rather than papered over — the transient is only visible
    /// on screen, so it belongs to the Track B pass.
    func testARefusedPreloadPublishesNoProgressAndNoResidency() async throws {
        let (data, _) = try await demoArray()
        let residency = DatasetResidency()
        await residency.request(.streamed, on: data)

        let recorded = Box()
        let held = await residency.preload(data) { recorded.values.append($0) }

        XCTAssertFalse(held)
        XCTAssertFalse(residency.isResident)
        XCTAssertEqual(residency.byteCount, 0)
        XCTAssertNil(residency.preloadFraction)
        XCTAssertTrue(recorded.values.isEmpty,
                      "A refused preload reported progress: \(recorded.values)")
    }

    /// `.automatic` is the shipped default and must stream until the residency
    /// threshold is measured — `docs/load-pipeline-plan.md` L2.3 forbids
    /// choosing it by reasoning. If the sweep has since run, this test is the
    /// one that should be rewritten to assert the measured value.
    func testAutomaticStreamsWhileTheThresholdIsUnmeasured() async throws {
        let (data, _) = try await demoArray()
        let residency = DatasetResidency()

        XCTAssertEqual(residency.mode, .automatic, "The shipped default changed")
        XCTAssertNil(ResidencyAdmission.measuredWorkingSetFraction,
                     "A measured threshold exists now — update this test to assert it")

        let held = await residency.preload(data) { _ in }
        XCTAssertFalse(held, ".automatic admitted a cube with no measured threshold")
        XCTAssertFalse(residency.isResident)
    }

    // MARK: Release, and reset on dataset replacement

    func testReleaseReturnsToStreamingAndGivesTheBytesBack() async throws {
        let (data, _) = try await demoArray()
        let residency = DatasetResidency()
        await residency.request(.resident, on: data)
        await residency.preload(data) { _ in }
        XCTAssertTrue(residency.isResident)

        await residency.release(data)

        XCTAssertFalse(residency.isResident)
        XCTAssertEqual(residency.byteCount, 0)
        let arraySays = await data.isResident
        XCTAssertFalse(arraySays, "release left the array holding its buffer")
    }

    func testResetForgetsTheReplacedDataset() async throws {
        let (data, _) = try await demoArray()
        let residency = DatasetResidency()
        await residency.request(.resident, on: data)
        await residency.preload(data) { _ in }
        XCTAssertTrue(residency.isResident)

        residency.reset()

        XCTAssertFalse(residency.isResident,
                       "Residency survived a dataset replacement and would be "
                       + "reported for a cube that is no longer open")
        XCTAssertEqual(residency.byteCount, 0)
        XCTAssertEqual(residency.mode, .automatic)
    }

    // MARK: Reentrancy — a preload suspends, and things happen in the gaps

    /// `makeResident` awaits a tile read on every iteration, and actors are
    /// **reentrant**: a release runs in those windows. Before the generation
    /// counter, the preload then re-published the cube on completion, silently
    /// undoing the release — final state "Streaming" on screen, gigabytes still
    /// held, and nothing to re-sync it.
    ///
    /// No timing is asserted. The reader is made slow only to widen the window;
    /// the assertion is on the final state, so a slower machine makes this test
    /// *more* reliable, never flakier.
    func testAReleaseDuringAPreloadIsNotUndoneWhenItFinishes() async throws {
        let source = SlowFourDDataSource()
        let descriptor = try await source.discoverPrimaryDataset()
        let data = FourDArray(reader: source, descriptor: descriptor)
        await data.setResidencyRequest(.resident)

        // Wait for a real tile to have been read before releasing. `async let`
        // only *creates* the child task — it does not guarantee it has begun, so
        // a bare `releaseResident()` here raced ahead of the preload's own
        // generation bump and the preload then legitimately succeeded. That is a
        // defect in the test, not in the array, and it is why this waits on
        // evidence of work instead of on task-creation order.
        let started = expectation(description: "preload has read a tile")
        started.assertForOverFulfill = false
        async let preload: Bool = data.makeResident(
            maximumRows: 1, progress: { _ in started.fulfill() }
        )
        await fulfillment(of: [started], timeout: 10)
        await data.releaseResident()
        let held = (try? await preload) ?? false

        XCTAssertFalse(held, "a superseded preload reported success")
        let isResident = await data.isResident
        XCTAssertFalse(
            isResident,
            "the preload re-published a cube that had been released while it ran"
        )
    }

    /// Two concurrent preloads both passed the `residentCube == nil` check and
    /// both allocated a full cube — on a machine whose admission rule had just
    /// decided that *one* fits. Reachable by double-clicking a dataset.
    func testASecondConcurrentPreloadDoesNotAllocateASecondCube() async throws {
        let source = SlowFourDDataSource()
        let descriptor = try await source.discoverPrimaryDataset()
        let data = FourDArray(reader: source, descriptor: descriptor)
        await data.setResidencyRequest(.resident)

        async let first: Bool = data.makeResident(maximumRows: 1)
        async let second: Bool = data.makeResident(maximumRows: 1)
        let results = [(try? await first) ?? false, (try? await second) ?? false]

        XCTAssertEqual(
            results.filter { $0 }.count, 1,
            "expected exactly one preload to succeed, got \(results) — two "
            + "concurrent preloads each allocate a full cube"
        )
        let isResident = await data.isResident
        XCTAssertTrue(isResident)
    }

    // MARK: The panel's one line

    func testSummaryNeverClaimsResidencyItDoesNotHave() async throws {
        let (data, _) = try await demoArray()
        let residency = DatasetResidency()
        XCTAssertEqual(residency.summary, "Streaming")

        await residency.request(.resident, on: data)
        await residency.preload(data) { _ in }
        XCTAssertTrue(residency.summary.hasPrefix("Resident"), residency.summary)

        await residency.release(data)
        XCTAssertEqual(residency.summary, "Streaming")
    }

    // MARK: Opening a dataset leaves residency in a stated condition

    func testOpeningTheDemoLeavesResidencyStreamingAndNotPreloading() async {
        let state = AppState()
        await state.openDemoFixture()

        // Not an assertion that residency is useless — an assertion that the
        // shipped default is streaming and that the open cleared its preload
        // state either way.
        XCTAssertNil(state.residency.preloadFraction)
        XCTAssertFalse(state.residency.isPreloading)
        XCTAssertFalse(state.residency.isResident)
    }
}

/// The progress callback is `@MainActor`, so a plain reference box is enough.
@MainActor
private final class Box {
    var values: [Double] = []
}

/// A reader that takes a measurable moment per tile, so a preload spends real
/// time suspended and a concurrent release or second preload is actually
/// serviced in the gap.
///
/// The blocking sleep is deliberate and is inside the *reader* actor, not the
/// array under test: it widens the window without introducing a timing
/// assertion anywhere. Every test using it asserts final state only.
private actor SlowFourDDataSource: FourDDataSource {
    static let descriptor = DatasetDescriptor(
        filePath: "/tmp/slow.h5", datasetPath: "/data",
        shape: [8, 4, 8, 8], dtypeDescription: "float32", chunkShape: nil
    )
    private let cube: [Float]

    init() {
        let d = Self.descriptor
        let count = d.ry * d.rx * d.qy * d.qx
        cube = (0..<count).map { Float($0 % 997) * 1.0009765625 }
    }

    func discoverPrimaryDataset() throws -> DatasetDescriptor { Self.descriptor }

    func readPattern(_ descriptor: DatasetDescriptor, ry: Int, rx: Int) throws -> [Float] {
        let count = descriptor.qy * descriptor.qx
        let start = (ry * descriptor.rx + rx) * count
        return Array(cube[start..<start + count])
    }

    func readScanRow(_ descriptor: DatasetDescriptor, ry: Int) throws -> [Float] {
        let count = descriptor.rx * descriptor.qy * descriptor.qx
        return Array(cube[ry * count..<(ry + 1) * count])
    }

    func readScanTile(_ descriptor: DatasetDescriptor,
                      yRange: Range<Int>) throws -> FourDScanTile {
        Thread.sleep(forTimeInterval: 0.01)
        let rowCount = descriptor.rx * descriptor.qy * descriptor.qx
        return FourDScanTile(
            yRange: yRange, scanWidth: descriptor.rx,
            detectorHeight: descriptor.qy, detectorWidth: descriptor.qx,
            pixels: Array(cube[yRange.lowerBound * rowCount..<yRange.upperBound * rowCount])
        )
    }

    func readDoubleAttribute(_ name: String, onObjectPath path: String) -> Double? { nil }
    func pixelCalibration() -> PixelCalibration? { nil }
}

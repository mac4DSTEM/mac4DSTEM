import XCTest
@testable import mac4DSTEM

/// Pins the loading-progress contract from `docs/load-pipeline-plan.md` stage
/// L1, invariant I5: **progress is measured or absent**.
///
/// The defect these replace was not a crash — the old open reported a sequence
/// of hard-coded waypoints (0.08 → 0.28 → 0.42 → 0.52 → 0.72 → 0.84 → 0.95)
/// that had no relationship to work completed, and then finished the load
/// *before* the first whole-cube pass, so the bar jumped in blocks and then
/// vanished while the app was still visibly busy. Every assertion here would
/// have passed in that broken state if it were written loosely, so each one
/// names the specific property that was wrong.
@MainActor
final class DatasetLoadingProgressTests: XCTestCase {

    // MARK: The measured phase actually measures

    /// The whole-cube pass is the only determinate phase, so its fractions must
    /// be real: one per tile, non-decreasing, and landing exactly on 1.0.
    /// `maximumTileRows: 1` forces one report per scan row so the sequence is
    /// long enough for monotonicity to mean something.
    func testWholeCubePassReportsOneRealFractionPerTileEndingExactlyAtOne() async throws {
        let source = DemoFourDDataSource()
        let descriptor = try await source.discoverPrimaryDataset()
        let data = FourDArray(reader: source, descriptor: descriptor)

        let recorded = Recorder()
        _ = try await VirtualDetector.tiledImage(
            data: data, descriptor: descriptor,
            shape: .circle(centerX: Float(descriptor.qx) / 2,
                           centerY: Float(descriptor.qy) / 2,
                           radius: Float(descriptor.qx) / 4),
            maximumTileRows: 1,
            progress: { fraction in recorded.append(fraction) }
        )
        let fractions = recorded.values

        XCTAssertEqual(
            fractions.count, descriptor.ry,
            "Expected one progress report per scan row; a coarser report is what "
            + "makes the bar step in blocks"
        )
        XCTAssertEqual(try XCTUnwrap(fractions.last), 1.0, accuracy: 1e-12,
                       "The measured phase must land exactly on 1.0, not near it")
        XCTAssertGreaterThan(fractions.first ?? 1, 0,
                             "First report must reflect completed work, not a seed value")
        for (previous, next) in zip(fractions, fractions.dropFirst()) {
            XCTAssertGreaterThan(next, previous,
                                 "Progress must strictly advance: \(fractions)")
        }
    }

    // MARK: The status line names quantities the user can check

    func testScanStatusNamesBothPatternsAndBytes() {
        let descriptor = DemoFourDDataSource.descriptor
        let status = AppState.scanProgressStatus(
            "Scanning patterns", processed: 72, total: 144, descriptor: descriptor
        )
        XCTAssertTrue(status.contains("72"), status)
        XCTAssertTrue(status.contains("144"), status)
        XCTAssertTrue(status.contains("patterns"), status)
        XCTAssertTrue(status.contains("MB") || status.contains("GB"), status)
    }

    /// The byte string beside the counts is unlocalized (`%.2f GB`), so the
    /// counts must not use a locale grouping separator: on a German system that
    /// produced "1.378 / 16.218 patterns · 3.96 GB", where "." meant grouping
    /// twice and decimal point once, in one line. Observed on the real app
    /// 2026-08-06.
    func testPatternCountsGroupIndependentlyOfTheSystemLocale() {
        XCTAssertEqual(AppState.count(1_378), "1,378")
        XCTAssertEqual(AppState.count(16_218), "16,218")
        let status = AppState.scanProgressStatus(
            "Scanning patterns", processed: 1_378, total: 16_218,
            descriptor: DemoFourDDataSource.descriptor
        )
        XCTAssertFalse(
            status.contains("1.378"),
            "A grouping period collides with the byte string's decimal period: \(status)"
        )
    }

    /// Bytes are the float32 *working* size — what is actually streamed — not
    /// the on-disk size. A uint16 cube streams at twice its file size, and
    /// reporting the file size would be the more flattering number and the
    /// wrong one.
    func testReportedBytesAreTheFloatWorkingSizeNotTheOnDiskSize() {
        let uint16Cube = DatasetDescriptor(
            filePath: "/tmp/x.h5", datasetPath: "/data",
            shape: [4, 4, 64, 64], dtypeDescription: "uint16", chunkShape: nil
        )
        // 16 patterns x 64 x 64 x 4 bytes = 256 KB working, vs 128 KB on disk.
        let status = AppState.scanProgressStatus(
            "Scanning patterns", processed: 16, total: 16, descriptor: uint16Cube
        )
        XCTAssertTrue(
            status.contains(SystemMonitor.byteString(16 * 64 * 64 * 4)),
            "Expected the float32 working size in \(status)"
        )
    }

    // MARK: The load survives past the first whole-cube pass

    /// The regression this pins: the load used to finish *before* the first
    /// virtual image, so the welcome card disappeared while the app was still
    /// scanning. While a load is in flight, the running operation's measured
    /// progress must reach the loading card.
    func testOperationProgressReachesTheLoadingCardWhileOpening() {
        let state = AppState()
        state.isLoadingDataset = true
        let token = state.beginCancellableOperation(
            "Virtual detector", status: "Scanning patterns 0 / 144", totalUnits: 144
        )
        defer { state.finishCancellableOperation(token) }

        state.updateCancellableOperation(
            token, progress: 0.25, status: "Scanning patterns 36 / 144"
        )
        XCTAssertEqual(state.datasetLoadingProgress ?? -1, 0.25, accuracy: 1e-12)
        XCTAssertEqual(state.datasetLoadingStatus, "Scanning patterns 36 / 144")
    }

    /// The mirror is one-directional and scoped: ordinary analysis work run
    /// long after a dataset opened must not resurrect the loading card.
    func testOperationProgressDoesNotLeakIntoTheCardWhenNotLoading() {
        let state = AppState()
        XCTAssertFalse(state.isLoadingDataset)
        let token = state.beginCancellableOperation(
            "Virtual detector", status: "Computing…", totalUnits: 144
        )
        defer { state.finishCancellableOperation(token) }

        state.updateCancellableOperation(token, progress: 0.5, status: "Computing…")
        XCTAssertNil(state.datasetLoadingProgress)
        XCTAssertNil(state.datasetLoadingStatus)
        XCTAssertFalse(state.isLoadingDataset)
    }

    // MARK: Opening leaves no stale loading state

    func testOpeningTheDemoRunsItsFirstPassAndClearsEveryLoadingField() async {
        let state = AppState()
        await state.openDemoFixture()

        XCTAssertNotNil(
            state.resultImage,
            "The initial analysis must run as part of opening — if it does not, "
            + "there is nothing for the measured phase to report"
        )
        XCTAssertFalse(state.isLoadingDataset)
        XCTAssertNil(state.datasetLoadingProgress)
        XCTAssertNil(state.datasetLoadingStatus)
    }
}

/// Progress callbacks arrive off the main actor, so collect them behind a lock
/// rather than assuming an isolation domain.
private nonisolated final class Recorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Double] = []

    func append(_ value: Double) {
        lock.lock(); defer { lock.unlock() }
        storage.append(value)
    }

    var values: [Double] {
        lock.lock(); defer { lock.unlock() }
        return storage
    }
}

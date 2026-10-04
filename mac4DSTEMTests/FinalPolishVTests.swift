//
//  FinalPolishVTests.swift
//  Lane V (Slot 4⅞ polish, 2026-10-04; item P10a, Gate B): a datacube the app exports carries the accelerating
//  voltage, so reopening it is not "Accelerating voltage: Not set" (which blocks DPC, parallax, ptychography, ACOM).
//  The writer stamps the root attribute only for a finite positive value; the open-view door hands it the session's
//  voltage, the raw-file door the source's own through the opener's one rule (eV above 1000 -> kV). Each test names
//  the mutation that turns it red.
//

import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

/// A small source whose root voltage attribute is whatever the test says (nil = the format has none).
actor VoltageFixtureSource: FourDDataSource {
    static let descriptor = DatasetDescriptor(
        filePath: "/synthetic/voltage-fixture.h5", datasetPath: "/data",
        shape: [2, 3, 4, 6], dtypeDescription: "float32", chunkShape: nil
    )
    private let voltage: Double?

    init(voltage: Double?) { self.voltage = voltage }

    func discoverPrimaryDataset() throws -> DatasetDescriptor { Self.descriptor }
    nonisolated func loadPushdown(for view: LoadView) -> LoadPushdown { .none }

    func readPattern(_ view: LoadView, ry: Int, rx: Int) throws -> [Float] {
        let d = view.descriptor
        var pixels = [Float](repeating: 0, count: d.qy * d.qx)
        for qy in 0..<d.qy { for qx in 0..<d.qx { pixels[qy * d.qx + qx] = Float(ry * 7 + rx * 3 + qy * 5 + qx) } }
        return pixels
    }

    func readScanRow(_ view: LoadView, ry: Int) throws -> [Float] {
        var row = [Float]()
        for x in 0..<view.descriptor.rx { row += try readPattern(view, ry: ry, rx: x) }
        return row
    }

    func readScanTile(_ view: LoadView, yRange: Range<Int>) throws -> FourDScanTile {
        var pixels = [Float]()
        for y in yRange { pixels += try readScanRow(view, ry: y) }
        return FourDScanTile(
            yRange: yRange, scanWidth: view.descriptor.rx,
            detectorHeight: view.descriptor.qy, detectorWidth: view.descriptor.qx, pixels: pixels
        )
    }

    func readDoubleAttribute(_ name: String, onObjectPath path: String) -> Double? {
        name == AcceleratingVoltage.attributeName && path == "/" ? voltage : nil
    }
    func pixelCalibration() -> PixelCalibration? { nil }
}

@MainActor
final class FinalPolishVTests: XCTestCase {

    private var descriptor: DatasetDescriptor { VoltageFixtureSource.descriptor }

    private func scratchDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("p10a-voltage-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }

    private func wholeCube() -> CalibratedDataCubeExportOptions {
        CalibratedDataCubeExportOptions(scanY: 0..<descriptor.ry, scanX: 0..<descriptor.rx)
    }

    /// What a fresh reader finds in the exported file's root: nil = the attribute is absent (or not a scalar double).
    private func storedVoltage(in url: URL) async throws -> Double? {
        try await H5Reader(path: url.path).readDoubleAttribute(AcceleratingVoltage.attributeName, onObjectPath: "/")
    }

    private func makeState() throws -> AppState {
        let suite = "mac4dstem.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: suite) }
        return AppState(sessionSidecar: SessionSidecarLocator(defaults: defaults))
    }

    private func open(_ reader: any FourDDataSource, descriptor: DatasetDescriptor, in state: AppState) async {
        let load = state.beginDatasetLoading("Opening…")
        await state.activate(descriptor: descriptor, reader: reader, runInitialAnalysis: false)
        state.finishDatasetLoading(owner: load)
    }

    /// The outcome a door reports to its sheet.
    private func finishing(_ start: (@escaping @MainActor (DataCubeWriteOutcome) -> Void) -> Void) async -> DataCubeWriteOutcome {
        await withCheckedContinuation { continuation in start { continuation.resume(returning: $0) } }
    }

    private func assertWrote(_ outcome: DataCubeWriteOutcome, file: StaticString = #filePath, line: UInt = #line) {
        guard case .wrote = outcome else { return XCTFail("the export did not write: \(outcome)", file: file, line: line) }
    }

    // MARK: The writer

    /// Mutation: delete the `writeScalarAttribute(AcceleratingVoltage.attributeName …)` line in
    /// `writeCalibratedDataCubeFile` -> the reader finds nil, not 300.5; a writer that rounds (`.rounded()`) -> 300 or 301.
    /// A non-integer kV on purpose: integer-only fixtures let a rounding writer pass (the refuter's survivor R2).
    func testTheWriterStampsTheVoltageAsARootAttributeThatReadsBack() async throws {
        let url = try scratchDirectory().appendingPathComponent("v300.h5")
        _ = try await BraggVectorEMDWriter.writeCalibratedDataCube(
            source: VoltageFixtureSource(voltage: nil), view: LoadView(fullExtentOf: descriptor),
            calibration: PixelCalibration(), acceleratingVoltageKV: 300.5, options: wholeCube(), to: url
        )
        let stored = try await storedVoltage(in: url)
        XCTAssertEqual(stored, 300.5)
        // The value is kV: what the opener (and a reader of the file) gets back is the number as written.
        XCTAssertEqual(AcceleratingVoltage.kilovolts(fromAttribute: try XCTUnwrap(stored)), 300.5)
    }

    /// No usable value, no attribute: nothing is invented. Mutation: drop `isFinite` or `> 0` from the writer's guard ->
    /// NaN / inf / 0 / -80 are written and read back as numbers.
    func testNoUsableVoltageWritesNoAttribute() async throws {
        let directory = try scratchDirectory()
        let none: [(String, Double?)] = [
            ("nil", nil), ("zero", 0), ("negative", -80), ("nan", .nan), ("infinity", .infinity),
        ]
        for (name, voltage) in none {
            let url = directory.appendingPathComponent("\(name).h5")
            _ = try await BraggVectorEMDWriter.writeCalibratedDataCube(
                source: VoltageFixtureSource(voltage: nil), view: LoadView(fullExtentOf: descriptor),
                calibration: PixelCalibration(), acceleratingVoltageKV: voltage, options: wholeCube(), to: url
            )
            let stored = try await storedVoltage(in: url)
            XCTAssertNil(stored, "\(name): the attribute must be absent")
        }
        // The default argument (every pre-existing caller) writes none either.
        let url = directory.appendingPathComponent("default.h5")
        _ = try await BraggVectorEMDWriter.writeCalibratedDataCube(
            source: VoltageFixtureSource(voltage: nil), view: LoadView(fullExtentOf: descriptor),
            calibration: PixelCalibration(), options: wholeCube(), to: url
        )
        let stored = try await storedVoltage(in: url)
        XCTAssertNil(stored)
    }

    // MARK: The one rule

    /// Mutation: the rule's threshold moved (`> 1_000_000`) or the division dropped -> 300000 stays 300000.
    func testTheOneRuleReadsEVAboveAThousandAsKilovolts() {
        XCTAssertEqual(AcceleratingVoltage.kilovolts(fromAttribute: 300_000), 300)
        XCTAssertEqual(AcceleratingVoltage.kilovolts(fromAttribute: 300), 300)
        XCTAssertEqual(AcceleratingVoltage.kilovolts(fromAttribute: 80), 80)
        XCTAssertEqual(AcceleratingVoltage.kilovolts(fromAttribute: 1_000), 1_000, "the opener's rule is strictly above 1000")
        XCTAssertEqual(AcceleratingVoltage.kilovolts(fromAttribute: 1_000.5), 1_000.5 / 1_000)
        XCTAssertEqual(AcceleratingVoltage.attributeName, "accelerating_voltage", "the py4DSTEM-era spelling the opener has always read")
    }

    /// The opener still reads a source's attribute the way it did (the rule moved, not changed): eV -> kV, kV as is, none -> nil.
    /// Mutation: the opener bypassing the rule (storing the raw number) -> 300000.
    func testTheOpenerStillTakesEVAsKilovoltsAndNoAttributeAsNotSet() async throws {
        for (raw, expected): (Double?, Double?) in [(300_000, 300), (200, 200), (nil, nil)] {
            let state = try makeState()
            await open(VoltageFixtureSource(voltage: raw), descriptor: descriptor, in: state)
            XCTAssertEqual(state.calibrationSession.acceleratingVoltage, expected, "source attribute \(String(describing: raw))")
        }
    }

    // MARK: The doors

    /// Raw-file door: a source whose own attribute is 300000 (eV) is written as 300 kV, and the app opens that file with a
    /// usable voltage. Mutation: the door passing nil (the old behaviour) -> nil; the door skipping the rule -> 300000.
    func testTheRawFileDoorCarriesTheSourcesOwnVoltageInKilovolts() async throws {
        let url = try scratchDirectory().appendingPathComponent("raw-door.h5")
        let source = VoltageFixtureSource(voltage: 300_000)
        let pending = PendingLoad(source: descriptor, reader: source, url: URL(fileURLWithPath: descriptor.filePath),
                                  accessedSecurityScope: false, fileByteCount: nil)
        pending.preprocess = PreprocessDraft(origin: .rawFile)
        let state = try makeState()
        let outcome = await finishing { done in state.writePreprocessed(pending: pending, to: url, finish: done) }
        assertWrote(outcome)
        let stored = try await storedVoltage(in: url)
        XCTAssertEqual(stored, 300, "kV, not the source's 300000 eV")

        // The point of the feature: the reopened file is not "Not set".
        let reopened = try makeState()
        let reader = try H5Reader(path: url.path)
        await open(reader, descriptor: try await reader.discoverPrimaryDataset(), in: reopened)
        XCTAssertEqual(reopened.calibrationSession.acceleratingVoltage, 300)
        XCTAssertTrue(reopened.calibrationSession.hasUsableVoltage)
    }

    /// Raw-file door, a source with no voltage (a vendor raw file, an H5 without the attribute): nothing is written and the
    /// reopened file says "Not set" honestly. Mutation: the door substituting a default (e.g. `?? 300`) -> 300.
    func testTheRawFileDoorInventsNothingForASourceWithoutAVoltage() async throws {
        let url = try scratchDirectory().appendingPathComponent("raw-door-none.h5")
        let pending = PendingLoad(source: descriptor, reader: VoltageFixtureSource(voltage: nil),
                                  url: URL(fileURLWithPath: descriptor.filePath), accessedSecurityScope: false, fileByteCount: nil)
        pending.preprocess = PreprocessDraft(origin: .rawFile)
        let state = try makeState()
        assertWrote(await finishing { done in state.writePreprocessed(pending: pending, to: url, finish: done) })
        let stored = try await storedVoltage(in: url)
        XCTAssertNil(stored)

        let reopened = try makeState()
        let reader = try H5Reader(path: url.path)
        await open(reader, descriptor: try await reader.discoverPrimaryDataset(), in: reopened)
        XCTAssertNil(reopened.calibrationSession.acceleratingVoltage)
        XCTAssertFalse(reopened.calibrationSession.hasUsableVoltage)
    }

    /// Open-view door: the session's voltage — a manual entry on a source that had none, then a file-supplied one the
    /// opener normalised — is what the file carries. Mutation: the door passing nil (the old behaviour) -> nil.
    func testTheOpenViewDoorCarriesTheSessionsVoltage() async throws {
        let directory = try scratchDirectory()
        let options = wholeCube()

        // 1. A manual entry (the drive's 80 kV) on a file that had no voltage attribute.
        let manualURL = directory.appendingPathComponent("open-manual.h5")
        let manual = try makeState()
        await open(VoltageFixtureSource(voltage: nil), descriptor: descriptor, in: manual)
        manual.calibrationSession.acceleratingVoltage = 80.5
        assertWrote(await finishing { done in
            manual.exportCalibratedDataCube(options: options, to: manualURL, progress: { _ in }, finish: done)
        })
        let manualStored = try await storedVoltage(in: manualURL)
        XCTAssertEqual(manualStored, 80.5)

        // 2. A voltage the source supplied in eV: the session holds 300 kV, the file carries 300 (not 300000).
        let fileURL = directory.appendingPathComponent("open-file.h5")
        let fromFile = try makeState()
        await open(VoltageFixtureSource(voltage: 300_000), descriptor: descriptor, in: fromFile)
        XCTAssertEqual(fromFile.calibrationSession.acceleratingVoltage, 300, "the premise")
        assertWrote(await finishing { done in
            fromFile.exportCalibratedDataCube(options: options, to: fileURL, progress: { _ in }, finish: done)
        })
        let fileStored = try await storedVoltage(in: fileURL)
        XCTAssertEqual(fileStored, 300)

        // 3. No voltage in the session: no attribute.
        let noneURL = directory.appendingPathComponent("open-none.h5")
        let none = try makeState()
        await open(VoltageFixtureSource(voltage: nil), descriptor: descriptor, in: none)
        assertWrote(await finishing { done in
            none.exportCalibratedDataCube(options: options, to: noneURL, progress: { _ in }, finish: done)
        })
        let noneStored = try await storedVoltage(in: noneURL)
        XCTAssertNil(noneStored)
    }
}

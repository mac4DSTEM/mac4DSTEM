//
//  PreprocessSheetModelTests.swift
//  X3 — "Preprocess Raw Data…": the sheet's model, host-less. Pins what the
//  sheet decides (readiness only for the open view, the writer's options from
//  the dragged crop + bin + stride + filter, the output's shape and size) and
//  the one claim the feature rests on: a raw file preprocessed with these
//  settings is, value for value, the cube "Open with Options" would have
//  loaded and then exported with the same stride and filter.
//

import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

/// Integer-valued, deterministic patterns, generated at SOURCE coordinates and
/// cut through the view like a real reader: small integers sum exactly in
/// float32 in any order, so two ways of binning them must agree bit for bit.
/// One planted hot pixel (source detector row 6, column 6) is in every pattern.
actor PreprocessFixtureSource: FourDDataSource {
    static let descriptor = DatasetDescriptor(
        filePath: "/synthetic/preprocess-fixture.h5", datasetPath: "/data",
        shape: [5, 6, 12, 16], dtypeDescription: "float32", chunkShape: nil
    )

    func discoverPrimaryDataset() throws -> DatasetDescriptor { Self.descriptor }
    nonisolated func loadPushdown(for view: LoadView) -> LoadPushdown { .none }

    private func sourcePattern(y: Int, x: Int) -> [Float] {
        let d = Self.descriptor
        var pixels = [Float](repeating: 0, count: d.qy * d.qx)
        for qy in 0..<d.qy {
            for qx in 0..<d.qx {
                pixels[qy * d.qx + qx] = Float((y * 7 + x * 3 + qy * 5 + qx * 2) % 11)
            }
        }
        pixels[6 * d.qx + 6] += 1000
        return pixels
    }

    func readPattern(_ view: LoadView, ry: Int, rx: Int) throws -> [Float] {
        view.detectorView(of: sourcePattern(y: view.sourceScanY(ry), x: view.sourceScanX(rx)))
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

    func readDoubleAttribute(_ name: String, onObjectPath path: String) -> Double? { nil }
    func pixelCalibration() -> PixelCalibration? { nil }
}

final class PreprocessSheetModelTests: XCTestCase {

    private var descriptor: DatasetDescriptor { PreprocessFixtureSource.descriptor }

    private func configuration(
        scanCrop: AxisCrop? = nil, detectorCrop: AxisCrop? = nil, bin: Int = 1
    ) -> LoadConfiguration {
        var configuration = LoadConfiguration(source: descriptor)
        configuration.scanCrop = scanCrop
        configuration.detectorCrop = detectorCrop
        configuration.detectorBin = bin
        return configuration
    }

    // MARK: State from a raw file versus the current view

    func testReadinessShowsOnlyWhenTheSourceIsTheOpenView() async throws {
        XCTAssertFalse(PreprocessDraft(origin: .rawFile).showsCalibrationReadiness,
                       "a raw file has no session calibration (owner 1a)")
        XCTAssertTrue(PreprocessDraft(origin: .currentView(name: "a.h5")).showsCalibrationReadiness)
    }

    func testRawFilePendingIsTheFileAndCurrentViewPendingIsTheViewsFrame() async throws {
        let source = PreprocessFixtureSource()
        let raw = PendingLoad(source: descriptor, reader: source,
                              url: URL(fileURLWithPath: descriptor.filePath),
                              accessedSecurityScope: false, fileByteCount: 1234)
        XCTAssertEqual(raw.source.shape, [5, 6, 12, 16])
        XCTAssertEqual(raw.fileByteCount, 1234)

        // The open view: scan 3 x 4 at offset (1, 2), detector binned by 2.
        let specification = LoadSpecification(
            scanCrop: AxisCrop(yOffset: 1, xOffset: 2, height: 3, width: 4),
            detectorCrop: nil, detectorBin: 2
        )
        let view = try LoadView(source: descriptor, specification: specification)
        let current = PendingLoad(currentView: FourDArray(reader: source, view: view),
                                  reader: source, url: URL(fileURLWithPath: descriptor.filePath))
        XCTAssertEqual(current.source.shape, [3, 4, 6, 8], "crop and drag are in the view's frame")
        XCTAssertNil(current.fileByteCount)
        XCTAssertFalse(current.accessedSecurityScope)
        XCTAssertEqual(current.configuration.source.shape, [3, 4, 6, 8])
    }

    // MARK: Options, shape, size

    func testOptionsCarryTheDraggedCropBinStrideAndFilterInTheWritersFrame() {
        let config = configuration(
            scanCrop: AxisCrop(yOffset: 1, xOffset: 2, height: 4, width: 3),
            detectorCrop: AxisCrop(yOffset: 0, xOffset: 1, height: 12, width: 14), bin: 2
        )
        var draft = PreprocessDraft(origin: .rawFile)
        draft.scanStride = 2
        draft.hotPixelsEnabled = true
        draft.hotPixelThreshold = 20
        let options = draft.options(for: config)
        XCTAssertEqual(options.scanY, 1..<5)
        XCTAssertEqual(options.scanX, 2..<5)
        XCTAssertEqual(options.qCropY, 0..<12)
        XCTAssertEqual(options.qCropX, 1..<15)
        XCTAssertEqual(options.qBin, 2)
        XCTAssertEqual(options.scanStride, 2)
        XCTAssertEqual(options.hotPixelThreshold, 20)
        // No crop dragged: the writer gets "whole axis", not a degenerate range.
        let whole = PreprocessDraft(origin: .rawFile).options(for: configuration())
        XCTAssertEqual(whole.scanY, 0..<5)
        XCTAssertEqual(whole.scanX, 0..<6)
        XCTAssertNil(whole.qCropY)
        XCTAssertNil(whole.qCropX)
        XCTAssertNil(whole.hotPixelThreshold, "the filter is off unless asked for")
        XCTAssertEqual(whole.scanStride, 1)
    }

    func testOutputShapeAndSizeFollowTheOptionsIncludingTheBinRemainder() {
        // Scan 4 x 3 at stride 2 -> 2 x 1; detector 12 x 14 binned by 4 -> 3 x 3
        // (the 2 spare columns are trimmed, as py4DSTEM bin_Q does).
        let config = configuration(
            scanCrop: AxisCrop(yOffset: 1, xOffset: 2, height: 4, width: 3),
            detectorCrop: AxisCrop(yOffset: 0, xOffset: 1, height: 12, width: 14), bin: 4
        )
        var draft = PreprocessDraft(origin: .rawFile)
        draft.scanStride = 2
        XCTAssertEqual(draft.outputShape(for: config), [2, 1, 3, 3])
        XCTAssertEqual(draft.outputBytes(for: config), 2 * 1 * 3 * 3 * 4)
        XCTAssertEqual(PreprocessDraft(origin: .rawFile).outputShape(for: configuration()),
                       [5, 6, 12, 16], "defaults write the whole cube")
    }

    func testStrideClampsWhenATighterCropShrinksTheRangeUnderIt() {
        var draft = PreprocessDraft(origin: .rawFile)
        draft.scanStride = 4
        XCTAssertEqual(draft.effectiveStride(for: configuration()), 4)
        let tight = configuration(scanCrop: AxisCrop(yOffset: 0, xOffset: 0, height: 2, width: 6))
        XCTAssertEqual(PreprocessDraft.strideLimit(for: tight), 2)
        XCTAssertEqual(draft.effectiveStride(for: tight), 2, "what is written is the clamped value")
        XCTAssertEqual(draft.options(for: tight).scanStride, 2)
    }

    func testDestinationReadsWithTheHomeAbbreviatedAndTheNameSuggestedFromTheSource() {
        XCTAssertEqual(PreprocessDraft.suggestedFileName(forSource: "sample_28GB.dm4"),
                       "sample_28GB_preprocessed.h5")
        var draft = PreprocessDraft(origin: .rawFile)
        XCTAssertNil(draft.destinationLabel)
        draft.destination = URL(fileURLWithPath: NSHomeDirectory() + "/Data/out.h5")
        XCTAssertEqual(draft.destinationLabel, "~/Data/out.h5")
    }

    // MARK: The raw-file path and the open-cube path write the same values

    /// Every value of a written datacube, through the app's own reader.
    private func values(of url: URL) async throws -> (shape: [Int], pixels: [Float]) {
        let reader = try H5Reader(path: url.path)
        let written = try await reader.discoverPrimaryDataset()
        let tile = try await reader.readScanTile(LoadView(fullExtentOf: written),
                                                  yRange: 0..<written.ry)
        return (written.shape, tile.pixels)
    }

    func testRawFilePathWritesTheSameValuesAsLoadThenExport() async throws {
        let source = PreprocessFixtureSource()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("x3-parity-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let config = configuration(
            scanCrop: AxisCrop(yOffset: 1, xOffset: 0, height: 4, width: 5),
            detectorCrop: AxisCrop(yOffset: 0, xOffset: 0, height: 12, width: 14), bin: 2
        )
        var draft = PreprocessDraft(origin: .rawFile)
        draft.scanStride = 2
        draft.hotPixelsEnabled = true
        draft.hotPixelThreshold = 20

        // Door 1: the raw file, whole, with the sheet's options.
        let rawURL = directory.appendingPathComponent("raw.h5")
        let rawSummary = try await BraggVectorEMDWriter.writeCalibratedDataCube(
            source: source, view: LoadView(fullExtentOf: descriptor),
            calibration: await source.pixelCalibration() ?? PixelCalibration(),
            options: draft.options(for: config), to: rawURL
        )

        // Door 2: "Open with Options" at the same crop and bin, then the export
        // with only the stride and the filter the open cube's sheet adds.
        let loaded = try LoadView(source: descriptor, specification: config.specification)
        let openURL = directory.appendingPathComponent("open.h5")
        let openSummary = try await BraggVectorEMDWriter.writeCalibratedDataCube(
            source: source, view: loaded, calibration: PixelCalibration(),
            options: CalibratedDataCubeExportOptions(
                scanY: 0..<loaded.descriptor.ry, scanX: 0..<loaded.descriptor.rx,
                scanStride: 2, hotPixelThreshold: 20
            ),
            to: openURL
        )

        XCTAssertEqual(rawSummary.shape, [2, 2, 6, 7])
        XCTAssertEqual(rawSummary.shape, openSummary.shape)
        XCTAssertEqual(rawSummary.hotPixels, [[3, 3]], "the planted pixel, binned: (6, 6) / 2")
        XCTAssertEqual(rawSummary.hotPixels, openSummary.hotPixels)
        let raw = try await values(of: rawURL)
        let open = try await values(of: openURL)
        XCTAssertEqual(raw.shape, open.shape)
        XCTAssertEqual(raw.pixels.count, 2 * 2 * 6 * 7)
        XCTAssertEqual(raw.pixels.map(\.bitPattern), open.pixels.map(\.bitPattern),
                       "same writer, same options frame: bit-identical values")
    }
}

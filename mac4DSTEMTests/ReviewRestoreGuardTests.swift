//
//  ReviewRestoreGuardTests.swift
//  Lane H (Slot 4¾ pre-release review, 2026-10-02, finding H1): a saved SCALAR result is checked against the
//  scan it is restored onto, as the RGBA result already was — a crop-shaped map is never shown on the full view
//  on reopen. Driven through a real `AppState.activate`, so the wiring is under test, not only a predicate.
//

import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

@MainActor
final class ReviewRestoreGuardTests: XCTestCase {

    /// The demo source is a 12 × 12 scan on a 64 × 64 detector.
    private let cropSpecification = LoadSpecification(
        scanCrop: AxisCrop(yOffset: 0, xOffset: 0, height: 6, width: 6))

    private func scalar(width: Int, height: Int, kind: String, domain: String) -> ScalarResultMap {
        ScalarResultMap(
            width: width, height: height,
            pixels: (0..<(width * height)).map { Float($0) * 0.37 + 1.5 },
            kind: kind, displayName: "Restored \(kind)", valueUnits: "arbitrary",
            provenance: ["display_domain": domain])
    }

    /// Write `map` (saved under `recorded`) into a sidecar and open the demo cube onto it under `loaded`.
    private func open(
        saving map: ScalarResultMap, recorded: LoadSpecification = .fullExtent,
        loaded: LoadSpecification = .fullExtent
    ) async throws -> AppState {
        let suite = "ReviewRestoreGuard-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: suite) }
        let locator = SessionSidecarLocator(defaults: defaults)
        let source = DemoFourDDataSource(includesCalibration: false)
        let descriptor = try await source.discoverPrimaryDataset()

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReviewRestoreGuard-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let sidecar = directory.appendingPathComponent("demo.mac4dstem.h5")
        locator.adopt(sidecar, for: descriptor)
        try BraggVectorEMDWriter.mergeResultMap(
            map, vectors: nil, qWidth: descriptor.qx, qHeight: descriptor.qy,
            calibration: PixelCalibration(), to: sidecar, loadSpecification: recorded)

        let state = AppState(sessionSidecar: locator)
        let load = state.beginDatasetLoading("Reopening demo…")
        await state.activate(descriptor: descriptor, reader: source,
                             specification: loaded, runInitialAnalysis: false)
        state.finishDatasetLoading(owner: load)
        return state
    }

    /// The finding: a map saved on a 6 × 6 crop reopened on the full 12 × 12 scan was published as the scan's result.
    func testACropShapedScanMapIsRefusedOnTheFullView() async throws {
        let state = try await open(
            saving: scalar(width: 6, height: 6, kind: "virtual_detector_bf", domain: "scan"),
            recorded: cropSpecification)
        XCTAssertNil(state.resultPresentation.product,
                     "published: \(String(describing: state.resultPresentation.product?.kind))")
        let ignored = state.activityLog.messages.filter { $0.contains("Ignored demo.mac4dstem.h5") }
        XCTAssertEqual(ignored.count, 1, "log: \(state.activityLog.messages)")
        XCTAssertTrue(ignored.first?.contains("saved scalar map is 6 × 6, expected 12 × 12") == true,
                      "log: \(ignored)")
    }

    /// The control: a scan-domain map that fits the scan is restored.
    func testAScanMapThatFitsTheScanIsRestored() async throws {
        let state = try await open(
            saving: scalar(width: 12, height: 12, kind: "virtual_detector_bf", domain: "scan"))
        let product = try XCTUnwrap(state.resultPresentation.product,
                                    "log: \(state.activityLog.messages)")
        XCTAssertEqual(product.kind, "virtual_detector_bf")
        XCTAssertEqual(product.origin, .restoredFromSidecar)
        XCTAssertFalse(state.activityLog.messages.contains { $0.hasPrefix("Ignored") },
                       "log: \(state.activityLog.messages)")
    }

    /// The same crop reopened: a 6-wide × 4-high map saved under, and loaded on, the 6 × 4 crop fits and is restored.
    /// Non-square on purpose — the demo scan is square, so a width/height swap in the guard (`width == ry`,
    /// `height == rx`) passes every other test here.
    func testANonSquareCropMapSavedOnTheSameCropIsRestored() async throws {
        let crop = LoadSpecification(scanCrop: AxisCrop(yOffset: 0, xOffset: 0, height: 4, width: 6))
        let state = try await open(
            saving: scalar(width: 6, height: 4, kind: "virtual_detector_bf", domain: "scan"),
            recorded: crop, loaded: crop)
        let product = try XCTUnwrap(state.resultPresentation.product,
                                    "log: \(state.activityLog.messages)")
        XCTAssertEqual(product.kind, "virtual_detector_bf")
        XCTAssertEqual(product.origin, .restoredFromSidecar)
        XCTAssertEqual(product.width, 6)
        XCTAssertEqual(product.height, 4)
        XCTAssertFalse(state.activityLog.messages.contains { $0.hasPrefix("Ignored") },
                       "log: \(state.activityLog.messages)")
    }

    /// The guard is scan-domain only: the Bragg vector map lives on the detector grid (64 × 64 here, not 12 × 12)
    /// and must keep coming back — a blanket shape check would refuse it on every reopen.
    func testADetectorGridMapIsNotComparedWithTheScan() async throws {
        let state = try await open(
            saving: scalar(width: 64, height: 64, kind: "bragg_vector_map", domain: "detector"))
        let product = try XCTUnwrap(state.resultPresentation.product,
                                    "log: \(state.activityLog.messages)")
        XCTAssertEqual(product.kind, "bragg_vector_map")
        XCTAssertFalse(state.activityLog.messages.contains { $0.hasPrefix("Ignored") },
                       "log: \(state.activityLog.messages)")
    }
}

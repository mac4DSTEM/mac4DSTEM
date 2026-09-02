import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

/// P2 wiring pins. The unit gate stayed green across a known-flawed
/// intermediate of `applySessionCalibration`, so the translation carries its
/// own tests: the owner's exact stale-frame case, and the refuter's
/// identity-restore regression case.
final class SessionCalibrationTranslationTests: XCTestCase {

    /// The owner's 2026-09-01 case: sidecar recorded on the whole
    /// 125×125-detector view, cube opened binned 2× (124→62 px). Raw adoption
    /// put the centre at 62.9 on a 62 px detector (the corner BF preset) and
    /// left qSize at half the binned-frame truth.
    func testFullExtentSessionOntoBinnedViewMapsTheOwnersNumbers() throws {
        let source = DatasetDescriptor(
            filePath: "/tmp/au.h5", datasetPath: "/data",
            shape: [100, 84, 125, 125], dtypeDescription: "float32", chunkShape: nil
        )
        let spec = LoadSpecification(detectorBin: 2)
        let view = try LoadView(source: source, specification: spec)
        var saved = PixelCalibration()
        saved.qSize = 0.0199
        saved.qx0Mean = 63.1
        saved.qy0Mean = 62.9
        saved.probeSemiangle = 10

        let out = try XCTUnwrap(SessionCalibrationTranslation.translate(
            saved: saved,
            policy: .decide(session: .fullExtent, loaded: spec),
            view: view, descriptor: view.descriptor
        ))
        let center = try XCTUnwrap(out.center)
        // Half-pixel bin convention: (c − (b−1)/2) / b.
        XCTAssertEqual(center.x, 31.2, accuracy: 0.01, "app x carries qy0")
        XCTAssertEqual(center.y, 31.3, accuracy: 0.01, "app y carries qx0")
        XCTAssertEqual(try XCTUnwrap(out.calibration.qPixelSize), 0.0398,
                       accuracy: 1e-9, "a binned reciprocal pixel is 2× coarser")
        XCTAssertEqual(try XCTUnwrap(out.calibration.probeRadius), 5.0,
                       accuracy: 1e-4, "the probe radius is in detector px")
        XCTAssertEqual(out.calibration.recordedOriginX ?? -1, center.x,
                       accuracy: 0.01,
                       "the recorded origin and the aperture centre must agree")
    }

    /// Refuter correction (2026-09-01): the sidecar WRITER records origin
    /// maps in the LIVE VIEW's frame, so an identity restore of a
    /// scan-cropped session must size the maps against the loaded
    /// descriptor — sizing them against the source silently downgrades
    /// fitted maps to the mean, exactly the quiet-drop class this repo
    /// forbids.
    func testIdentityRestoreOfAScanCroppedSessionKeepsItsFittedMaps() throws {
        let source = DatasetDescriptor(
            filePath: "/tmp/source.h5", datasetPath: "/data",
            shape: [4, 3, 10, 8], dtypeDescription: "float32", chunkShape: nil
        )
        let spec = LoadSpecification(
            scanCrop: AxisCrop(yOffset: 1, xOffset: 1, height: 2, width: 2)
        )
        let view = try LoadView(source: source, specification: spec)
        var saved = PixelCalibration()
        // Maps recorded on the 2×2 CROPPED scan (py4DSTEM shape [R_Nx, R_Ny]).
        saved.originMaps = PixelOriginMaps(
            shape: [2, 2],
            fittedQX: [5.0, 5.1, 5.2, 5.3],
            fittedQY: [4.0, 4.1, 4.2, 4.3]
        )

        let out = try XCTUnwrap(SessionCalibrationTranslation.translate(
            saved: saved,
            policy: .decide(session: spec, loaded: spec),
            view: view, descriptor: view.descriptor
        ))
        XCTAssertTrue(out.restoredMaps,
                      "fitted maps recorded on this very view must survive an identity restore")
        XCTAssertNotNil(out.calibration.origin)
    }
}

// MARK: - v2.5 step 3 negative controls (docs/v2.5-plan.md §9e), written 2026-09-03

@MainActor
final class ProductStatusNegativeControlTests: XCTestCase {
    func testAnUnknownResultKindIsNotReportedQuantitative() {
        let app = AppState()
        XCTAssertNotEqual(app.quantitativeStatus(for: "some_future_kind", units: "nm"), .quantitative,
                          "A kind this build has never heard of must not inherit the strongest claim")
        XCTAssertEqual(app.quantitativeStatus(for: "strain_exx", units: "1"), .quantitative)
        XCTAssertEqual(app.quantitativeStatus(for: "dpc_magnitude_mrad", units: "mrad"), .quantitative)
        XCTAssertEqual(app.quantitativeStatus(for: "virtual_detector", units: "intensity"), .relative)
        XCTAssertEqual(app.quantitativeStatus(for: "dpc_color", units: ""), .categorical)
    }

    func testAFreshPublishNeverInheritsARestoredBadge() async throws {
        // Control 1: a stale restore triple left behind (the missed-clear
        // case) must not relabel a freshly computed result.
        let app = AppState()
        await app.openDemoFixture(calibrated: true)
        app.navigation.analysisMode = .virtualDetector
        app.publishRestoredProduct(
            kind: "acom_ipf_z", displayName: "Restored IPF (stale)", valueUnits: "categorical",
            payload: .scalar(FloatImage(width: 1, height: 1, pixels: [0])),
            pixelSizeRow: nil, pixelSizeColumn: nil, pixelUnits: nil, provenance: [:])
        _ = await app.runVirtualDetector(quiet: true)
        let product = try XCTUnwrap(app.displayedProduct)
        XCTAssertTrue(product.kind.hasPrefix("virtual_"), product.kind)
        XCTAssertFalse(product.displayName.contains("Restored"), product.displayName)
        XCTAssertEqual(product.quantitativeStatus, .relative)
        XCTAssertEqual(product.valueUnits, "intensity")
        // And a write through the legacy field drops the published product.
        app.publishedProduct = nil
        XCTAssertNil(app.publishedProduct)
    }

    func testDPCDisplayModesPublishTheirOwnProduct() async throws {
        let app = AppState()
        await app.openDemoFixture(calibrated: true)
        app.navigation.analysisMode = .dpc
        _ = await app.runDPC()
        guard app.resultImage != nil || app.resultRGBA != nil else {
            throw XCTSkip("DPC produced no result on the demo fixture")
        }
        let first = try XCTUnwrap(app.publishedProduct)
        XCTAssertTrue(first.kind.hasPrefix("dpc") || first.kind.hasPrefix("idpc"), first.kind)
        app.dpcDisplay = .angle
        let angle = try XCTUnwrap(app.publishedProduct)
        XCTAssertEqual(angle.kind, "dpc_angle")
        XCTAssertEqual(angle.valueUnits, "rad")
        XCTAssertEqual(angle.quantitativeStatus, .quantitative)
        app.dpcDisplay = .colorWheel
        let wheel = try XCTUnwrap(app.publishedProduct)
        XCTAssertEqual(wheel.quantitativeStatus, .categorical)
        if case .rgba = wheel.payload {} else { XCTFail("colour wheel is an RGBA product") }
    }

    func testAMissingQUnitNeverBecomesAGuessedUnit() {
        var calibration = Calibration()
        calibration.qPixelSize = 0.0146
        calibration.qPixelUnits = nil
        XCTAssertEqual(calibration.diffractionScaleBar.unitLabel, "px",
                       "A known size with an unknown unit is not a calibrated bar")
        XCTAssertEqual(calibration.diffractionScaleBar.perPixel, 1)
        calibration.qPixelUnits = "A^-1"
        XCTAssertEqual(calibration.diffractionScaleBar.unitLabel, "A^-1")
        XCTAssertEqual(calibration.diffractionScaleBar.perPixel, 0.0146)
        calibration.qPixelSize = nil
        XCTAssertEqual(calibration.diffractionScaleBar.unitLabel, "px")
    }
}


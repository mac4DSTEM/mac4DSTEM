import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

/// Lane X4 (2026-10-01, owner card R1 a): the single-slice probe (defocus, C12a/b, higher-order terms) is part of the record.
/// The other ptychography settings travel as provenance keys: written at the publish site (export), stored with the product
/// in the sidecar, read back by `SessionControlRehydration` and applied to the settings. The probe goes the same way.
@MainActor
final class PtychographyProbeRecordTests: XCTestCase {
    private let probe = PtychographyProbeAberrations(
        defocusAngstrom: -663.6, c12aAngstrom: 12.5, c12bAngstrom: -3.25,
        higherOrder: [.init(radialOrder: 2, angularOrder: 1, component: 1, coefficientAngstrom: 8000)]
    )

    private func result(probe: PtychographyProbeAberrations) -> SingleslicePtychographyResult {
        let array = PtychographyComplexArray(width: 2, height: 2, real: [1, 1, 1, 1], imaginary: [0, 0, 0, 0])
        return SingleslicePtychographyResult(
            object: array, probe: array, positions: [], errorHistory: [0.5, 0.25],
            objectSamplingRowAngstrom: 0.25, objectSamplingColumnAngstrom: 0.30,
            options: SingleslicePtychographyOptions(), probeAberrations: probe)
    }

    private func exported(_ probe: PtychographyProbeAberrations) throws -> DisplayedProduct {
        let state = AppState()
        state.changeMode(.singleslicePtychography)
        state.phaseContrast.singleslicePtychography = result(probe: probe)
        state.showParallaxProduct(.iterativePhase)
        return try XCTUnwrap(state.resultPresentation.product)
    }

    /// Path 3, export provenance. Mutation: drop `RecordedPtychographyProbe(...)` from the provenance dictionary -> red.
    func testExportProvenanceNamesTheProbe() throws {
        let p = try exported(probe).provenance
        XCTAssertEqual(p["probe_defocus_angstrom"], "-663.6")
        XCTAssertEqual(p["probe_c12a_angstrom"], "12.5")
        XCTAssertEqual(p["probe_c12b_angstrom"], "-3.25")
        XCTAssertEqual(p["probe_higher_order_terms"], "2:1:1:8000.0")
        let focus = try exported(PtychographyProbeAberrations()).provenance
        XCTAssertEqual(focus["probe_defocus_angstrom"], "0.0", "an in-focus run says so")
        XCTAssertNil(focus["probe_higher_order_terms"])
    }

    /// Paths 1+2, sidecar and replay of saved controls: the provenance goes through JSON (the sidecar's own encoding of a
    /// string dictionary), comes back on a restored product, and "Apply" writes the probe into the settings.
    /// Mutation: drop `ptychography.setProbe(value)` from `applySelectedSavedControls` -> red; make `setProbe` copy the
    /// higher-order terms back -> red; drop the status sentence -> red.
    func testSavedProbeComesBackIntoTheSettings() throws {
        let product = try exported(probe)
        let data = try JSONEncoder().encode(product.provenance)
        let provenance = try JSONDecoder().decode([String: String].self, from: data)

        let state = AppState()
        state.changeMode(.singleslicePtychography)
        state.publishRestoredProduct(
            kind: product.kind, displayName: product.displayName, valueUnits: product.valueUnits, payload: product.payload,
            pixelSizeRow: nil, pixelSizeColumn: nil, pixelUnits: nil, provenance: provenance)
        let plan = try XCTUnwrap(state.selectedSavedControlRehydration)
        XCTAssertTrue(plan.appliedSettingNames.contains("probe aberrations"))
        state.applySelectedSavedControls()
        // The record carries a C21 term; Apply takes defocus and C12 and ignores the term, and says so (control removed 2026-10-01).
        XCTAssertEqual(state.ptychography.probeAberrations,
                       PtychographyProbeAberrations(defocusAngstrom: -663.6, c12aAngstrom: 12.5, c12bAngstrom: -3.25))
        XCTAssertTrue(state.statusText.contains("higher-order probe terms (C21, C23) were not applied"), state.statusText)
        // CR2 E: it also says the applied defocus and C12 came from a fit that held those terms. Mutation: drop the clause -> red.
        XCTAssertTrue(state.statusText.contains("matches neither fit exactly"), state.statusText)
    }

    /// An old record (no probe keys) was made in focus: it decodes to the zero probe, not to whatever the fields hold now.
    /// A malformed key applies nothing. Mutation: parse absent keys as nil -> the first block goes red.
    func testOldRecordDecodesInFocusAndMalformedIsRefused() {
        var old = ["engine": "singleslice", "iterations": "5", "method": "gradient-descent"]
        XCTAssertEqual(SessionControlRehydration.parse(kind: "ptychography_object_phase", provenance: old).ptychographyProbe,
                       RecordedPtychographyProbe())
        let settings = PtychographySettings()
        settings.defocusAngstrom = 500
        settings.c12aAngstrom = 4
        settings.setProbe(SessionControlRehydration.parse(kind: "ptychography_object_phase", provenance: old).ptychographyProbe!)
        XCTAssertEqual(settings.probeAberrations, PtychographyProbeAberrations())

        old["probe_defocus_angstrom"] = "abc"
        XCTAssertNil(SessionControlRehydration.parse(kind: "ptychography_object_phase", provenance: old).ptychographyProbe)
        old["probe_defocus_angstrom"] = "1"
        old["probe_higher_order_terms"] = "2:0:1:5"   // a sine component needs angular order > 0
        XCTAssertNil(SessionControlRehydration.parse(kind: "ptychography_object_phase", provenance: old).ptychographyProbe)
    }
}

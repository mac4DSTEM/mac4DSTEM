import SwiftUI
import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM
@testable import SpectroCore

/// v5.0 lane U: the first drive's wiring, text and presentation findings (../_archive/mac4DSTEM/docs/archive/v5/room-drive-2026-10-06.md, 3-13).
/// Each test names the mutation that must turn it red.
@MainActor
final class SpectroscopyLaneUTests: XCTestCase {

    private typealias Q = SpectroscopyQuantifyTests
    private static var demo4D: String {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("References/demo-edx/AlMgSi_4D_EDX.dm4").path
    }

    /// The simulated GMS file writes `Microscope Info.Voltage` (200000 V) on its EDS object: the opener reads it.
    /// Mutation: `voltage:` set to nil in `DM4Experiment.build` - red.
    func testTheSimulatedFilesEDSObjectStatesItsVoltage() throws {
        try XCTSkipUnless(FileManager.default.fileExists(atPath: Self.demo4D), "References/demo-edx not generated")
        let objects = try DM4Experiment.list(path: Self.demo4D)
        XCTAssertEqual(try XCTUnwrap(objects.first { $0.role == .eds }).voltage, 200_000)
        let cube = try XCTUnwrap(objects.first { $0.role == .diffraction })
        let image = try XCTUnwrap(try SpectrumImageOpener.openGMSEDS(
            path: Self.demo4D, fourD: GMSFourDIdentity(objectIndex: cube.index, scanWidth: 64, scanHeight: 48, voltageKV: 123)))
        XCTAssertEqual(image.metadata.beamEnergyKeV, 200, "the object's own value, not the cube's 123")
        XCTAssertEqual(image.metadata.beamEnergySource, .file)
    }

    /// The row is pre-filled from the source with its phrase; the same value stays the source's, a different one is typed,
    /// overrides it in the method and the provenance says "typed". Mutation: `beamEnergy == fileBeam` test removed - red.
    func testATypedBeamOverridesTheFilesAndTheProvenanceSaysSo() throws {
        let image = try Q.image()
        var meta = image.metadata; meta.beamEnergyKeV = 200; meta.beamEnergySource = .fourDCube
        let loaded = LoadedSpectrumImage(image: image.image, metadata: meta, energyAxis: image.energyAxis, scanImage: image.scanImage)
        var s = QuantifySettings(method: QuantificationMethod(), fileBeamKnown: true, fileBeam: 200, fileBeamPhrase: meta.beamEnergySource.phrase)
        XCTAssertEqual(s.shownBeam, 200); XCTAssertEqual(s.beamPhrase, "from the 4D cube, same run")
        var m = Q.method(); m.beamEnergyKeV = nil
        s.beamEnergy = 200; s.apply(to: &m); XCTAssertNil(m.beamEnergyKeV, "the file's own value is not a typed one")
        s.beamEnergy = 120; s.apply(to: &m)
        XCTAssertEqual(m.beamEnergyKeV, 120); XCTAssertEqual(s.beamPhrase, "typed")
        let r = try PooledQuantifier.run(Q.input(m, image: loaded), tables: Q.tables)
        XCTAssertTrue(r.footerLines.contains("beam 120 kV \u{00B7} typed"), r.footerLines.joined(separator: "\n"))
        XCTAssertFalse(r.footerLines.contains { $0.contains("from the 4D cube") })
    }

    // MARK: 4 - the status line clears

    /// After the joint attach the status line says what happened, never "Looking for ...". Mutation: the `looking`
    /// assignment left as the last write (the success line removed) - red.
    func testTheLookingStatusIsReplacedOnSuccessAndOnFailure() async throws {
        let dm4 = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/demo-edx-tiny.dm4")
        let state = AppState()
        let descriptor = DatasetDescriptor(filePath: dm4.path, datasetPath: "ImageList.4.ImageData.Data",
                                           shape: [4, 6, 16, 16], dtypeDescription: "float32", chunkShape: [1, 1, 16, 16])
        state.descriptor = descriptor
        state.statusText = "Loaded"
        await state.attachGMSSpectrumImage(of: dm4, descriptor: descriptor)
        XCTAssertTrue(state.hasSpectrumImage)
        XCTAssertEqual(state.statusText, "Attached the EDS spectrum image of demo-edx-tiny.dm4")

        // The cube went away while the file was read: the line goes back to what it said.
        let other = AppState()
        other.statusText = "Loaded"
        await other.attachGMSSpectrumImage(of: dm4, descriptor: descriptor)
        XCTAssertEqual(other.statusText, "Loaded")

        // A file that cannot be read: the failure replaces it.
        let missing = URL(fileURLWithPath: "/nonexistent/none.dm4")
        let bad = AppState()
        let d2 = DatasetDescriptor(filePath: missing.path, datasetPath: "ImageList.4.ImageData.Data",
                                   shape: [4, 6, 16, 16], dtypeDescription: "float32", chunkShape: [1, 1, 16, 16])
        bad.descriptor = d2
        await bad.attachGMSSpectrumImage(of: missing, descriptor: d2)
        XCTAssertTrue(bad.statusText.hasPrefix("The EDS spectrum image in none.dm4 was not attached"), bad.statusText)
    }

    // MARK: 7 - the plot footer

    /// The footer is three whole tokens: estimator, continuum form, quality. Mutation: the old
    /// `components(separatedBy: ",").first` back in `shortBackground` - red ("...Bernstein(9").
    func testThePlotFooterKeepsItsThreeTokensWhole() throws {
        let r = try PooledQuantifier.run(Q.input(Q.method(), image: try Q.image()), tables: Q.tables)
        let parts = QuantifyPresentation.plotFooter(r).components(separatedBy: " \u{00B7} ")
        XCTAssertEqual(parts.count, 3, QuantifyPresentation.plotFooter(r))
        XCTAssertEqual(parts[0], r.fit.methodLabel)
        XCTAssertTrue(parts[1].hasPrefix("continuum: Kramers") && parts[1].hasSuffix(")"), parts[1])
        XCTAssertFalse(parts[1].contains("split") || parts[1].contains(";"))
        XCTAssertEqual(parts[1].filter { $0 == "(" }.count, parts[1].filter { $0 == ")" }.count, "no open parenthesis")
        XCTAssertTrue(parts[2].hasPrefix("\u{03C7}\u{00B2}\u{1D63} ") && parts[2].hasSuffix(" (Pearson)"), parts[2])   // R7: the number sits before "(Pearson)"
        XCTAssertEqual(QuantifyPresentation.shortBackground("continuum: Kramers\u{00D7}Bernstein(9,5), no edge split; orders chosen on synthetic data"),
                       "continuum: Kramers\u{00D7}Bernstein(9,5)")
        XCTAssertEqual(QuantifyPresentation.shortBackground("background: polynomial order 6 over the fitted range, signed coefficients"), "background: polynomial order 6 over the fitted range")
    }

    // MARK: 8 - marker labels

    private func px(_ keV: Double) -> CGFloat { 46 + CGFloat(keV) * 30 }   // 600 pt across 20 keV

    /// Ti K-alpha / K-beta 0.42 keV apart overprint on one row; they are staggered. Mutation: every label on row 0 - red.
    func testCollidingNamesAreStaggeredIntoRows() {
        let r = MarkerLabelLayout.place([("Ti K\u{03B1}", px(4.51), 3), ("Ti K\u{03B2}", px(4.93), 2)], minX: 46, maxX: 646)
        XCTAssertEqual(r.placed.count, 2); XCTAssertTrue(r.left.isEmpty)
        XCTAssertNotEqual(r.placed[0].row, r.placed[1].row)
        // far apart: both on the first row
        let far = MarkerLabelLayout.place([("O K\u{03B1}", px(0.525), 3), ("Ti K\u{03B1}", px(4.51), 3)], minX: 46, maxX: 646)
        XCTAssertEqual(far.placed.map(\.row), [0, 0])
    }

    /// Mg / Al / Si K-alpha within 0.5 keV plus a fourth crowded name: the three rows hold three, the fourth is left out,
    /// and the left-out one is the lowest priority. Mutation: the sort by priority removed - red.
    func testAFullStackLeavesOutTheLowestPriorityName() {
        let r = MarkerLabelLayout.place([("Si K\u{03B1}", px(1.74), 3), ("Al K\u{03B1}", px(1.487), 3), ("Mg K\u{03B1}", px(1.254), 3),
                                         ("Al K\u{03B2}", px(1.557), 0)], minX: 46, maxX: 646)
        XCTAssertEqual(Set(r.placed.map(\.row)), [0, 1, 2])
        XCTAssertEqual(r.left, ["Al K\u{03B2}"])
        // reversed input order: still the K-beta that goes
        let rev = MarkerLabelLayout.place([("Al K\u{03B2}", px(1.557), 0), ("Mg K\u{03B1}", px(1.254), 3), ("Al K\u{03B1}", px(1.487), 3), ("Si K\u{03B1}", px(1.74), 3)], minX: 46, maxX: 646)
        XCTAssertEqual(rev.left, ["Al K\u{03B2}"])
    }

    /// A name that would run past the frame's right edge is set to the left of its line. Mutation: `leading` always true - red.
    func testANameAtTheRightEdgeFlipsToTheLeft() {
        let r = MarkerLabelLayout.place([("Cu K\u{03B1}", 640, 3)], minX: 46, maxX: 646)
        XCTAssertFalse(try! XCTUnwrap(r.placed.first).leading)
    }

    // MARK: 9 - the x axis

    /// A tick at -1e-16 reads "0", a real negative keeps its sign. Mutation: the sign strip removed - red.
    func testNegativeZeroIsNotPrinted() {
        XCTAssertEqual(AxisTicks.label(-1e-16, step: 2), "0")
        XCTAssertEqual(AxisTicks.label(-0.0, step: 0.5), "0.0")
        XCTAssertEqual(AxisTicks.label(-0.004, step: 0.01), "0.00")
        XCTAssertEqual(AxisTicks.label(-0.5, step: 0.5), "-0.5")
        XCTAssertEqual(AxisTicks.label(-1, step: 1), "-1")
    }

    /// The unit sits left of the first label's box and no kept label reaches it; a tick that would is left out.
    /// Mutation: the unit placed at the right edge (`unitTrailing: main.maxX`) - the last label ("20") is then dropped or overlaps - red.
    func testTheUnitNeverMeetsATickLabel() {
        let ticks = stride(from: 0.0, through: 20, by: 2).map { $0 }
        let x: (Double) -> CGFloat = { 46 + CGFloat($0) * 30 }
        let a = AxisTicks.xLabels(ticks: ticks, x: x, step: 2, unit: "keV", unitTrailing: 38)
        XCTAssertEqual(a.labels.map(\.text), ticks.map { String(Int($0)) }, "every label kept, including 0 and 20")
        let unitLeft = a.unit.trailing - AxisTicks.labelWidth("keV")
        for l in a.labels { XCTAssertGreaterThan(l.x - AxisTicks.labelWidth(l.text) / 2, a.unit.trailing, l.text) }
        XCTAssertLessThan(unitLeft, a.unit.trailing)
        // zoomed so the first tick sits against the unit: that label goes, not the unit
        let b = AxisTicks.xLabels(ticks: [0.1, 0.2], x: { 48 + CGFloat($0 - 0.1) * 3000 }, step: 0.1, unit: "keV", unitTrailing: 38)
        XCTAssertEqual(b.labels.map(\.text), ["0.2"])
    }

    // MARK: 10, 11 - one "no fit", no raw RSS

    /// The table's footer before a fit names what the numbers are and does not say "no fit"; the fit footer has no RSS.
    /// Mutation: the RSS pair put back into the axis line - red.
    func testNoFitIsSaidOnceAndTheAxisLineHasNoRSS() throws {
        let image = try Q.image()
        let state = AppState()
        state.openSpectrumImage(image)
        XCTAssertEqual(state.spectroscopyRoom.model.resultsFooter, "window net counts")
        let r = try PooledQuantifier.run(Q.input(Q.method(), image: image), tables: Q.tables)
        XCTAssertFalse(r.footerLines.contains { $0.contains("RSS") })
        XCTAssertTrue(r.footerLines.contains { $0.hasPrefix("energy axis:") })
        XCTAssertTrue(SpectroscopyExport.csv(r, regionName: "Whole map").contains("axis refinement residual (RSS)"), "kept in the export")
    }

    // MARK: 8 - marker priority (feeds the layout above)

    /// The marker priority: the window's own line of a quantified element ranks above its satellite and above a fit-only element.
    /// Mutation: the `+ 1` for quantified removed - red.
    func testMarkerPriorityRanksTheOwnLineThenQuantified() throws {
        let image = try Q.image()
        let windows = ElementWindows.build(elements: [("Al", nil), ("Cu", nil)], axis: image.energyAxis, beamEnergyKeV: 200)
        let marks = SpectroscopyRoomController.markers(for: windows, axis: image.energyAxis, beam: 200, quantified: ["Al"])
        let alKa = try XCTUnwrap(marks.first { $0.label == "Al K\u{03B1}" })
        let cuKa = try XCTUnwrap(marks.first { $0.label == "Cu K\u{03B1}" })
        XCTAssertEqual(alKa.priority, 3); XCTAssertEqual(cuKa.priority, 2)
        if let beta = marks.first(where: { $0.label == "Al K\u{03B2}" }) { XCTAssertEqual(beta.priority, 1) }
    }
}

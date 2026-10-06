import SwiftUI
import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

/// v5.0 lane U: the first drive's wiring, text and presentation findings (docs/archive/v5/room-drive-2026-10-06.md, 3-13).
/// Each test names the mutation that must turn it red.
@MainActor
final class SpectroscopyLaneUTests: XCTestCase {

    private typealias Q = SpectroscopyQuantifyTests
    private static var demo4D: String {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("References/demo-edx/AlMgSi_4D_EDX.dm4").path
    }

    // MARK: 3 - the beam energy and where it came from

    /// The EDS object's own voltage wins (volts -> kV); else the cube's, only when it is one run; else nothing.
    /// Mutation: `sameRun` ignored in `BeamEnergy.resolve` - red.
    func testTheBeamEnergySourceIsTheObjectsThenTheSameRunCubes() {
        XCTAssertEqual(BeamEnergy.resolve(rawObjectVoltage: 200_000, cubeKV: 300, sameRun: true)?.keV, 200)
        XCTAssertEqual(BeamEnergy.resolve(rawObjectVoltage: 200_000, cubeKV: 300, sameRun: true)?.source, .file)
        XCTAssertEqual(BeamEnergy.resolve(rawObjectVoltage: nil, cubeKV: 200, sameRun: true)?.source, .fourDCube)
        XCTAssertNil(BeamEnergy.resolve(rawObjectVoltage: nil, cubeKV: 200, sameRun: false), "another run's voltage is not this file's")
        XCTAssertNil(BeamEnergy.resolve(rawObjectVoltage: 0, cubeKV: nil, sameRun: true))
        XCTAssertEqual(BeamEnergy.resolve(rawObjectVoltage: 0, cubeKV: 200, sameRun: true)?.source, .fourDCube, "a stored 0 is no voltage")
    }

    /// The provenance line names the value and its source; a typed value overrides and says so.
    /// Mutation: `typedKeV` ignored in `provenance` - red.
    func testTheProvenanceNamesTheBeamAndItsSource() {
        var meta = SpectrumImageMetadata(fileName: "a.dm4", filePath: "", scanWidth: 1, scanHeight: 1, channelCount: 1, energyOffsetEV: 0, energyDispersionEV: 10)
        XCTAssertNil(BeamEnergy.provenance(typedKeV: nil, metadata: meta))
        meta.beamEnergyKeV = 200; meta.beamEnergySource = .fourDCube
        XCTAssertEqual(BeamEnergy.provenance(typedKeV: nil, metadata: meta), "beam 200 kV \u{00B7} from the 4D cube, same run")
        meta.beamEnergySource = .file
        XCTAssertEqual(BeamEnergy.provenance(typedKeV: nil, metadata: meta), "beam 200 kV \u{00B7} from the file")
        XCTAssertEqual(BeamEnergy.provenance(typedKeV: 120, metadata: meta), "beam 120 kV \u{00B7} typed")
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

    /// The fit's footer says where the beam came from; a typed value says "typed".
    /// Mutation: the provenance line not appended in `PooledQuantifier.run` - red.
    func testTheFitFooterCarriesTheBeamProvenance() throws {
        var image = try Q.image()
        var meta = image.metadata
        meta.beamEnergyKeV = 200; meta.beamEnergySource = .fourDCube
        image = LoadedSpectrumImage(image: image.image, metadata: meta, energyAxis: image.energyAxis, scanImage: image.scanImage)
        var m = Q.method(); m.beamEnergyKeV = nil
        let r = try PooledQuantifier.run(Q.input(m, image: image), tables: Q.tables)
        XCTAssertTrue(r.footerLines.contains("beam 200 kV \u{00B7} from the 4D cube, same run"), r.footerLines.joined(separator: "\n"))
        let typed = try PooledQuantifier.run(Q.input(Q.method(), image: image), tables: Q.tables)
        XCTAssertTrue(typed.footerLines.contains("beam 200 kV \u{00B7} typed"))
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

    // MARK: 5 - export

    /// The CSV: header lines (validation, method hash, provenance), the column row, one row per fitted element, at% empty
    /// without a k source, the reference's k-free sigma empty, the flags and the estimator on each row.
    /// Mutation: the `validation` header line removed from `SpectroscopyExport.csv` - red.
    func testTheCSVCarriesTheTableTheValidationBadgeAndTheMethodHash() throws {
        let r = try PooledQuantifier.run(Q.input(Q.method(), image: try Q.image()), tables: Q.tables)
        let csv = SpectroscopyExport.csv(r, regionName: "Whole map")
        let lines = csv.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        XCTAssertTrue(lines.contains { $0.hasPrefix("# validation: UNVALIDATED") })
        XCTAssertTrue(lines.contains("# method hash (sha256 of the method JSON): \(r.method.hash)"))
        XCTAssertTrue(lines.contains { $0.hasPrefix("# beam 200 kV") })
        let head = try XCTUnwrap(lines.firstIndex { !$0.hasPrefix("#") })
        XCTAssertEqual(lines[head], SpectroscopyExport.columns.joined(separator: ","))
        let rows = lines[(head + 1)...].filter { !$0.isEmpty }
        XCTAssertEqual(rows.count, r.rows.count)
        let al = try XCTUnwrap(rows.first { $0.hasPrefix("Al,Al_Ka,") })
        let cells = al.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        XCTAssertEqual(cells[4], "1"); XCTAssertEqual(cells[5], "", "the reference carries no k-free sigma")
        XCTAssertEqual(cells[8], "none"); XCTAssertTrue(cells[9].contains("reference element"))
        XCTAssertEqual(Double(cells[2]) ?? 0, r.rows[0].net, accuracy: abs(r.rows[0].net) * 1e-5, "six significant digits")

        var m = Q.method(); m.kFactorSource = .typed          // no k: no at%
        let none = SpectroscopyExport.csv(try PooledQuantifier.run(Q.input(m, image: try Q.image()), tables: Q.tables), regionName: "Whole map")
        XCTAssertTrue(none.contains("# validation: net counts and k-free ratios only"))
        let row = try XCTUnwrap(none.split(separator: "\n").first { $0.hasPrefix("Al,Al_Ka,") }).split(separator: ",", omittingEmptySubsequences: false)
        XCTAssertEqual(row[6], ""); XCTAssertEqual(row[7], ""); XCTAssertEqual(row[8], "")
    }

    /// The method JSON holds the method's own canonical bytes and the hash of exactly those bytes.
    /// Mutation: the hash taken of a re-encoding with spaces (not `canonicalJSON`) - red.
    func testTheMethodJSONIsTheCanonicalEncodingAndItsHash() throws {
        let m = Q.method()
        let text = SpectroscopyExport.methodJSON(m)
        XCTAssertTrue(text.contains(m.canonicalJSON))
        let o = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        XCTAssertEqual(o["sha256"] as? String, m.hash)
        XCTAssertEqual(QuantificationMethod.decode(m.canonicalJSON), m)
        XCTAssertEqual(SpectroscopyExport.fileStem(imageName: "AlMgSi 4D.dm4", regionName: "Region 1"), "AlMgSi_4D_Region_1")
    }

    // MARK: 6 - the weak-line warning

    /// Shown only with Al K-alpha fitted at a non-zero area and a quantified Mg or Si K-alpha beside it.
    /// Mutation: the Al test dropped from `weakLineBiasApplies` - red.
    func testTheWeakLineWarningNeedsAlAndAQuantifiedNeighbour() throws {
        let ids = ["Al_Ka", "Mg_Ka", "Si_Ka", "Cu_Ka"]
        XCTAssertTrue(PooledQuantifier.weakLineBiasApplies(groupIDs: ids, values: [10, 1, 1, 1], quantified: ["Mg"]))
        XCTAssertFalse(PooledQuantifier.weakLineBiasApplies(groupIDs: ids, values: [0, 1, 1, 1], quantified: ["Mg"]), "Al at 0")
        XCTAssertFalse(PooledQuantifier.weakLineBiasApplies(groupIDs: ["Mg_Ka", "Si_Ka"], values: [1, 1], quantified: ["Mg"]), "no Al in the fit")
        XCTAssertFalse(PooledQuantifier.weakLineBiasApplies(groupIDs: ids, values: [10, 1, 1, 1], quantified: ["Al", "Cu"]), "no Mg or Si quantified")
        let image = try Q.image()
        let with = try PooledQuantifier.run(Q.input(Q.method(), image: image), tables: Q.tables)
        XCTAssertTrue(with.warnings.contains(ContinuumForm.weakLineBiasNote))
        let alCu = try PooledQuantifier.run(Q.input(Q.method(elements: [("Al", .quantify), ("Cu", .quantify)]), image: image), tables: Q.tables)
        XCTAssertFalse(alCu.warnings.contains(ContinuumForm.weakLineBiasNote))
        let noAl = try PooledQuantifier.run(Q.input(Q.method(elements: [("Mg", .quantify), ("Si", .quantify)]), image: image), tables: Q.tables)
        XCTAssertFalse(noAl.warnings.contains(ContinuumForm.weakLineBiasNote))
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
        XCTAssertTrue(parts[2].hasPrefix("\u{03C7}\u{00B2}\u{1D63} (Pearson) "))
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

    // MARK: 12 - live time

    /// A file that records 0 s says "not stored", one that records a time says it. Mutation: the zero test removed - red.
    func testAZeroLiveTimeReadsNotStored() {
        var meta = SpectrumImageMetadata(fileName: "v.emd", filePath: "", scanWidth: 1, scanHeight: 1, channelCount: 1, energyOffsetEV: 0, energyDispersionEV: 10)
        let axis = EnergyAxis(offset: 0, scale: 0.01, size: 1)
        meta.detectors = [SpectrumDetectorSegment(name: "SuperXG11", liveTime: 0, realTime: 0)]
        XCTAssertEqual(SpectroscopyRoomController.imageSettings(meta, axis: axis, hasFourDCube: false).liveDead, "not read: the stream metadata records 0 s")
        meta.detectors = [SpectrumDetectorSegment(name: "SuperXG11", liveTime: 0.5, realTime: 0.75)]
        XCTAssertEqual(SpectroscopyRoomController.imageSettings(meta, axis: axis, hasFourDCube: false).liveDead,
                       "live 0.5 s \u{00B7} real 0.75 s (as stored, semantics unverified)")
        meta.detectors = [SpectrumDetectorSegment(name: "EDS")]
        XCTAssertNil(SpectroscopyRoomController.imageSettings(meta, axis: axis, hasFourDCube: false).liveDead)
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

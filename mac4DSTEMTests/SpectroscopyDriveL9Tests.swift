//
//  SpectroscopyDriveL9Tests.swift
//  Lane L9 (the owner's drive findings, build 2): "on which basis are the KLM lines preselected? this has to match Velox. In Velox
//  you can also select alpha and beta separately." The default family is Velox's own (K up to Ru, L above, read from the owner's
//  200 kV file), a person checks lines of one family per element, the maps sum the checked lines' windows, the spectrum marks them
//  and the Quantify step's lineage records them. The fit is untouched. Every test names the mutation it catches; each was broken
//  once and seen red (the lane report lists them).
//

import XCTest
@testable import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

@MainActor
final class SpectroscopyDriveL9Tests: XCTestCase {
    private let Al = 13, Cu = 29, Hf = 72

    private var keep: [AppState] = []

    private func open() -> (AppState, SpectroscopyRoomController) {
        let state = AppState()
        keep.append(state)
        state.openSpectrumImage(SpectroscopyRoomLiveRegionTests.image())
        state.spectroscopyRoom.autoIDOnOpen?.cancel()
        return (state, state.spectroscopyRoom)
    }

    private func waitFor(_ what: String, timeout: TimeInterval = 30, _ condition: () -> Bool) async throws {
        let end = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > end { return XCTFail("timed out waiting for \(what)") }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    /// Velox's own element table from the owner's SI 1339 file at 200 kV (the seam's fixture).
    private struct VeloxElement: Decodable { let Z: Int; let symbol: String?; let family: String; let quantify: Bool }
    private struct VeloxTable: Decodable { let elements: [VeloxElement] }
    private func veloxTable() throws -> [VeloxElement] {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("docs/archive/v5/velox-family-table-200kV-2026-10-07.json")
        return try JSONDecoder().decode(VeloxTable.self, from: Data(contentsOf: url)).elements
    }

    /// An 80 keV axis, as the owner's files have.
    private let wide = EnergyAxis(offset: 0, scale: 0.02, size: 4000)

    // MARK: the family rule

    /// For every element Velox lists with a line in our table, our default family is Velox's, and the default line is that family's
    /// alpha on an 80 keV axis at 200 kV.
    /// Mutations: the limit 20 changed to 25 (Rh, Pd, Ag become K) - red; `defaultFamily` returning .K always - red; the L branch
    /// returning .M - red.
    func testTheDefaultFamilyIsVeloxsForEveryElementOfItsTable() throws {
        let table = try veloxTable()
        XCTAssertEqual(table.count, 104)
        var checked = 0
        for e in table where e.quantify {
            guard let symbol = e.symbol, !XRayLines.lines(of: symbol).isEmpty else { continue }
            XCTAssertEqual(ElementWindows.defaultFamily(of: symbol).rawValue, e.family, symbol)
            let id = ElementWindows.lineID(of: symbol, family: nil, axis: wide, beamEnergyKeV: 200)
            XCTAssertEqual(id, "\(symbol)_\(e.family)a", symbol)
            checked += 1
        }
        XCTAssertGreaterThan(checked, 85, "the table's elements with a K or an L alpha in ours")
    }

    /// The boundary the table shows: Ru K (19.28 keV), Rh L (20.22 keV); and the rule is not eXSpy's: Hf takes L\u{03B1} where
    /// eXSpy's pick is K\u{03B1} (55.8 keV, below the beam energy / 2).
    /// Mutation: `<=` changed to `<` against a limit of 19 (Ru becomes L) - red; `lineID` returning `defaultLines` - Hf_Ka - red.
    func testTheBoundaryIsRuKAndRhLAndHfIsNotEXSpys() {
        XCTAssertEqual(ElementWindows.defaultFamily(of: "Ru"), .K)
        XCTAssertEqual(ElementWindows.defaultFamily(of: "Rh"), .L)
        XCTAssertEqual(ElementWindows.lineID(of: "Hf", family: nil, axis: wide, beamEnergyKeV: 200), "Hf_La")
        XCTAssertEqual(XRayLines.defaultLines(elements: ["Hf"], axis: wide, beamEnergy: 200), ["Hf_Ka"], "what the rule replaces")
        // The person's family still wins, and a family with no alpha on the axis is no line.
        XCTAssertEqual(ElementWindows.lineID(of: "Hf", family: .K, axis: wide, beamEnergyKeV: 200), "Hf_Ka")
        XCTAssertEqual(ElementWindows.lineID(of: "Hf", family: .M, axis: wide, beamEnergyKeV: 200), "Hf_Ma")
        XCTAssertNil(ElementWindows.lineID(of: "Hf", family: .K, axis: EnergyAxis(offset: 0, scale: 0.01, size: 1024), beamEnergyKeV: 200))
    }

    /// The axis-range check stays: where the default family's alpha is off the axis (Ru K on a 10 keV axis) eXSpy's pick stands in.
    /// Mutation: the fallback removed - nil - red.
    func testADefaultAlphaOffTheAxisFallsBackToEXSpysPick() {
        let ten = EnergyAxis(offset: 0, scale: 0.01, size: 1024)
        XCTAssertEqual(ElementWindows.lineID(of: "Ru", family: nil, axis: ten, beamEnergyKeV: 200), "Ru_La")
        XCTAssertEqual(ElementWindows.lineID(of: "Cu", family: nil, axis: ten, beamEnergyKeV: 200), "Cu_Ka")
    }

    // MARK: the selection

    /// A beta pick alone changes the line a map uses; a Kα + Kβ pick is two entries; the table's own default is shown checked.
    /// Mutations: `toggleLine` keeping the alpha when a beta is checked from the default - the set holds Ka - red; `checkedLines`
    /// ignoring `lines` - red.
    func testABetaPickIsTheBetaAlone() {
        var e = ElementSelection()
        XCTAssertEqual(e.checkedLines(Al), ["Al_Ka"], "the default alpha is what the menu shows checked")
        e.toggleLine(Al, "Al_Kb")
        XCTAssertEqual(e.checkedLines(Al), ["Al_Ka", "Al_Kb"], "checked from the default: alpha stays, beta joins")
        e.toggleLine(Al, "Al_Ka")
        XCTAssertEqual(e.checkedLines(Al), ["Al_Kb"], "the alpha unchecked: beta alone")
        XCTAssertEqual(e.lines[Al], ["Al_Kb"])
        e.toggleLine(Al, "Al_Kb")
        XCTAssertEqual(e.checkedLines(Al), ["Al_Ka"], "none checked is the alpha line again")
        XCTAssertNil(e.lines[Al])
        XCTAssertEqual(e, { var d = ElementSelection(); d.toggleLine(Al, "Al_Ka"); return d }(), "checking the lone default alpha changes nothing")
    }

    /// One family's lines at a time; the family row clears the lines; "Default lines" returns the rule's family and its alpha.
    /// Mutations: a line of another family joining the set (not replacing it) - red; `setFamily` leaving `lines` - red;
    /// `resetLines` leaving the family - red.
    func testOneFamilyAtATimeAndReset() {
        var e = ElementSelection()
        e.toggleLine(Cu, "Cu_Kb")
        XCTAssertEqual(e.checkedLines(Cu), ["Cu_Ka", "Cu_Kb"])
        e.toggleLine(Cu, "Cu_La")
        XCTAssertEqual(e.checkedLines(Cu), ["Cu_La"], "an L line starts the L set, the K lines go")
        XCTAssertEqual(e.family(Cu), .L)
        e.toggleLine(Cu, "Cu_Lb1")
        XCTAssertEqual(e.checkedLines(Cu), ["Cu_La", "Cu_Lb1"])
        e.setFamily(Cu, .K)
        XCTAssertNil(e.lines[Cu], "the family row is the family's alpha line")
        XCTAssertEqual(e.checkedLines(Cu), ["Cu_Ka"])
        e.toggleLine(Cu, "Cu_Kb"); e.toggleLine(Cu, "Cu_La")
        XCTAssertTrue(e.hasChosenLines(Cu))
        e.resetLines(Cu)
        XCTAssertEqual(e, ElementSelection(), "default lines is the untouched state")
        XCTAssertFalse(e.hasChosenLines(Cu))
        XCTAssertEqual(e.family(Hf), .L, "the table's default family follows the rule, not a flat K")
        XCTAssertEqual(e.family(Cu), .K)
        // A line of another element is no line of this one.
        e.toggleLine(Cu, "Al_Ka")
        XCTAssertEqual(e, ElementSelection())
    }

    // MARK: windows, maps, markers

    /// A beta pick changes the window; two picks make two windows in energy order, the beta one on the beta energy.
    /// Mutations: `build(picks:)` ignoring `lines` - red; the windows not sorted by energy - red; a line off the axis kept - red.
    func testTheWindowsFollowTheCheckedLines() throws {
        let axis = EnergyAxis(offset: 0, scale: 0.01, size: 1024)
        let def = ElementWindows.build(picks: [.init(symbol: "Al")], axis: axis, beamEnergyKeV: 200)
        XCTAssertEqual(def.map(\.id), ["Al_Ka"])
        let beta = ElementWindows.build(picks: [.init(symbol: "Al", lines: ["Al_Kb"])], axis: axis, beamEnergyKeV: 200)
        XCTAssertEqual(beta.map(\.id), ["Al_Kb"])
        XCTAssertNotEqual(beta[0].window?.signal, def[0].window?.signal, "a beta pick moves the window")
        XCTAssertEqual(beta[0].energy, 1.5596, accuracy: 1e-9)
        let both = ElementWindows.build(picks: [.init(symbol: "Al", lines: ["Al_Kb", "Al_Ka"]), .init(symbol: "Cu")], axis: axis, beamEnergyKeV: 200)
        XCTAssertEqual(both.map(\.id), ["Al_Ka", "Al_Kb", "Cu_Ka"])
        XCTAssertEqual(both.map(\.element), ["Al", "Al", "Cu"])
        // A checked line off the axis is dropped; none left is the element's own "no usable line".
        let off = ElementWindows.build(picks: [.init(symbol: "Cu", lines: ["Cu_Ka", "Cu_Kb"])], axis: EnergyAxis(offset: 0, scale: 0.01, size: 850), beamEnergyKeV: 200)
        XCTAssertEqual(off.map(\.id), ["Cu_Ka"], "Cu K\u{03B2} 8.905 keV is past an 8.5 keV axis")
        let none = ElementWindows.build(picks: [.init(symbol: "Cu", lines: ["Cu_Kb"])], axis: EnergyAxis(offset: 0, scale: 0.01, size: 850), beamEnergyKeV: 200)
        XCTAssertEqual(none.map(\.id), ["Cu"])
        XCTAssertNil(none[0].window)
        XCTAssertEqual(ElementWindows.build(elements: [("Al", nil)], axis: axis, beamEnergyKeV: 200).map(\.id), ["Al_Ka"], "the old entry point is the default")
    }

    /// The map of two lines is the pixel-wise sum of the two windows' net maps; one map is itself.
    /// Mutation: `summed` returning the first map - red; returning the last - red.
    func testSummedIsPixelwise() {
        XCTAssertNil(SpectroscopyRoomController.summed([]))
        XCTAssertEqual(SpectroscopyRoomController.summed([[1, -2, 3]]), [1, -2, 3])
        XCTAssertEqual(SpectroscopyRoomController.summed([[1, -2, 3], [10, 20, 30], [100, 100, 100]]), [111, 118, 133])
    }

    /// The spectrum marks exactly the checked lines of an element that has any; an element with none keeps its family's markers.
    /// Mutations: `picked` ignored (the family's markers stay) - red; the checked lines marked without the `own` priority - red.
    func testMarkersFollowTheCheckedLines() throws {
        let axis = EnergyAxis(offset: 0, scale: 0.01, size: 1024)
        let windows = ElementWindows.build(picks: [.init(symbol: "Cu", lines: ["Cu_Kb"]), .init(symbol: "Al", lines: ["Al_Ka", "Al_Kb"]), .init(symbol: "Mg")],
                                           axis: axis, beamEnergyKeV: 200)
        let marks = SpectroscopyRoomController.markers(for: windows, axis: axis, beam: 200, quantified: ["Cu", "Al", "Mg"],
                                                       picked: ["Cu_Kb", "Al_Ka", "Al_Kb"])
        XCTAssertEqual(marks.filter { $0.elementZ == Cu }.map(\.label), ["Cu K\u{03B2}"], "a beta pick marks the beta alone")
        XCTAssertEqual(marks.filter { $0.elementZ == Al }.map(\.label), ["Al K\u{03B1}", "Al K\u{03B2}"], "one marker per checked line")
        XCTAssertEqual(marks.first { $0.label == "Cu K\u{03B2}" }?.priority, 3)
        let mg = marks.filter { $0.elementZ == 12 }.map(\.label)
        XCTAssertTrue(mg.contains("Mg K\u{03B1}"), "an element without a pick marks its family: \(mg)")
        // Without picks Cu marks its K family (K\u{03B1} and the K\u{03B2} line above 5 % of it).
        let plain = SpectroscopyRoomController.markers(for: ElementWindows.build(picks: [.init(symbol: "Cu")], axis: axis, beamEnergyKeV: 200), axis: axis, beam: 200)
        XCTAssertEqual(plain.map(\.label), ["Cu K\u{03B1}", "Cu K\u{03B2}"])
    }

    /// "Al K\u{03B1}+K\u{03B2}": the element named once, the lines in energy order.
    /// Mutation: the element repeated ("Al K\u{03B1}+Al K\u{03B2}") - red; the short label keeping the element - red.
    func testTheSummaryNamesTheElementOnce() {
        XCTAssertEqual(ElementWindows.summary(ofLineIDs: ["Al_Ka", "Al_Kb"]), "Al K\u{03B1}+K\u{03B2}")
        XCTAssertEqual(ElementWindows.summary(ofLineIDs: ["Cu_La"]), "Cu L\u{03B1}")
        XCTAssertEqual(ElementWindows.shortLabel(ofLineID: "Cu_Lb1"), "L\u{03B2}1")
        XCTAssertNil(ElementWindows.summary(ofLineIDs: []))
    }

    /// The menu's energies are the person's locale's: a decimal comma in German, and the line's own name in front.
    /// Mutation: `String(format:)` for the energy (a period) - red.
    func testTheMenuEnergiesFollowTheLocale() {
        let de = ElementLines.items(family: .K, z: Al, locale: Locale(identifier: "de_DE"))
        XCTAssertEqual(de.map(\.title), ["K\u{03B1} 1,486 keV", "K\u{03B2} 1,560 keV"])   // the table's 1.4865 and 1.5596
    }

    // MARK: the live room

    /// In the room: Al with Kα and Kβ checked has a tile that is the sum of the two lines' net maps, the Cu tile is as before,
    /// the tile and the Quantify lineage say which lines (`map_lines`), the spectrum marks both, and the default says nothing.
    /// Mutations: the controller keeping the first window's map (no sum) - red; `mapLinesParameters` empty - red; `tileLineLabels`
    /// naming the default lines too - red (Cu); `picks(for:)` dropping the lines - red.
    func testTheRoomSumsTheCheckedLinesAndRecordsThem() async throws {
        let (_, c) = open()
        let m = c.model
        m.elements.set(Cu, .quantify); m.elements.set(Al, .quantify)
        c.elementsChanged()
        try await waitFor("the tiles") { m.tiles.count == 2 }
        XCTAssertEqual(c.mapLinesParameters["map_lines"], "Al K\u{03B1}, Cu K\u{03B1}", "the default lines are recorded as they are")
        XCTAssertTrue(c.tileLineLabels.isEmpty, "a default tile names nothing")
        let defaultAl = try XCTUnwrap(m.tiles.first { $0.z == Al }).counts

        m.elements.toggleLine(Al, "Al_Kb")
        c.elementsChanged()
        try await waitFor("the summed tile") { m.tiles.first { $0.z == Al }?.counts != defaultAl }
        let image = SpectroscopyRoomLiveRegionTests.image()
        let windows = ElementWindows.build(picks: SpectroscopyRoomController.picks(for: m.elements), axis: image.energyAxis, beamEnergyKeV: 200)
        let maps = ElementWindows.maps(image: image.image, windows: windows)
        let alMaps = windows.indices.filter { windows[$0].element == "Al" }.compactMap { maps[$0] }
        XCTAssertEqual(alMaps.count, 2)
        let tile = try XCTUnwrap(m.tiles.first { $0.z == Al })
        for p in tile.counts.indices { XCTAssertEqual(tile.counts[p], alMaps[0][p] + alMaps[1][p], accuracy: 1e-9, "pixel \(p)") }
        XCTAssertEqual(try XCTUnwrap(m.tiles.first { $0.z == Cu }).counts.count, tile.counts.count)
        XCTAssertEqual(m.tiles.count, 2, "one tile per element, however many lines")
        XCTAssertEqual(m.results.filter { $0.z == Al }.count, 1, "one row per element")

        XCTAssertEqual(c.tileLineLabels, [Al: "Al K\u{03B1}+K\u{03B2}"], "the chosen element's tile says so; Cu's default does not")
        XCTAssertEqual(c.mapLinesParameters["map_lines"], "Al K\u{03B1}+K\u{03B2}, Cu K\u{03B1}")
        let labels = m.markers.filter { $0.elementZ == Al }.map(\.label)
        XCTAssertEqual(labels.sorted(), ["Al K\u{03B1}", "Al K\u{03B2}"], "the spectrum marks the checked lines")
        XCTAssertEqual(m.windowBands.filter { $0.elementZ == Al && $0.kind == .signal }.count, 2, "Show \u{203A} Windows draws both")

        // Back to the default: the first tile exactly, nothing named.
        m.elements.resetLines(Al)
        c.elementsChanged()
        try await waitFor("the default tile") { m.tiles.first { $0.z == Al }?.counts == defaultAl }
        XCTAssertTrue(c.tileLineLabels.isEmpty)
        XCTAssertEqual(c.mapLinesParameters["map_lines"], "Al K\u{03B1}, Cu K\u{03B1}")
    }

    /// The FIT is untouched by the line pick: the quantification's method (what the replay step restores) carries no lines.
    /// Mutation: the checked lines written into the method's elements - the method hash moves - red.
    func testTheMethodDoesNotKnowTheLines() async throws {
        let (state, c) = open()
        c.model.elements.set(Al, .quantify)
        c.elementsChanged()
        try await waitFor("the tile") { c.model.tiles.count == 1 }
        let before = SpectroscopyExport.shortHash(state.spectroscopy.method)
        c.model.elements.toggleLine(Al, "Al_Kb")
        c.elementsChanged()
        try await waitFor("the summed tile") { c.mapLineSummaries[Al] == "Al K\u{03B1}+K\u{03B2}" }
        XCTAssertEqual(SpectroscopyExport.shortHash(state.spectroscopy.method), before)
    }

    /// Supervisor (Gate B): Al Kα + Kβ windows overlap at 130 eV; after `build(picks:)` the two signal ranges are disjoint and
    /// adjacent, so a summed map counts each channel once. Mutation: `clipOverlaps` returns its input → red.
    func testTwoLinesOfOneElementNeverShareASignalChannel() throws {
        let axis = EnergyAxis(offset: 0, scale: 0.01, size: 2048)
        let ws = ElementWindows.build(picks: [.init(symbol: "Al", family: .K, lines: ["Al_Ka", "Al_Kb"])], axis: axis, beamEnergyKeV: 200)
        let signals = ws.compactMap { $0.window?.signal }
        XCTAssertEqual(signals.count, 2)
        XCTAssertLessThanOrEqual(signals[0].upperBound, signals[1].lowerBound, "Kβ's window starts where Kα's ends")
        XCTAssertGreaterThan(signals[1].count, 0)
        // Another element's window is not clipped against Al's.
        let two = ElementWindows.build(picks: [.init(symbol: "Al"), .init(symbol: "Mg")], axis: axis, beamEnergyKeV: 200)
        XCTAssertEqual(two.compactMap { $0.window?.signal }.count, 2)
    }
}

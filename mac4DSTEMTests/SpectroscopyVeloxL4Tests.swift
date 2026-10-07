//
//  SpectroscopyVeloxL4Tests.swift
//  The Velox sheet's lane L4 (the controller): the display kernel applied to the signed map before the clamp (row 1a), the
//  proposer's significance carried (2a), Fit only for a pick without a computed k (2c), the pixels behind the spectrum (4b), the
//  windows as energy bands (10a) and the spectrum's candidate pick (onPickElement). Every test names the mutation it catches;
//  each was broken once and seen red (the lane report lists them).
//

import XCTest
@testable import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

@MainActor
final class SpectroscopyVeloxL4Tests: XCTestCase {
    private let Al = 13, Cu = 29, Eu = 63

    private var keep: [AppState] = []

    private func open(image: LoadedSpectrumImage? = nil) -> (AppState, SpectroscopyRoomController) {
        let state = AppState()
        keep.append(state)
        state.openSpectrumImage(image ?? SpectroscopyRoomLiveRegionTests.image())
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

    /// The picture a raw signed map must give: clamp negatives, stretch to the maximum (the pre-kernel `normalised`).
    private func picture(_ map: [Double]) -> [Float] {
        let hi = map.max() ?? 0
        return hi > 0 ? map.map { Float(max($0, 0) / hi) } : [Float](repeating: 0, count: map.count)
    }

    // MARK: Row 1a: the kernel before the clamp

    /// A negative pixel beside a positive one cancels under the kernel; clamping first would turn the negative into 0 and keep
    /// the positive's whole weight (a sparse map inflated). Four pixels [0, 8, -8, 0], 3-tap box (the border renormalised over its
    /// in-bounds taps): signed, pixel 1 is (0 + 8 - 8) / 3 = 0 and pixel 0 is (0 + 8) / 2 = 4, the maximum, so the scale is 4.
    /// Mutation: `display(of:)` filters `max(value, 0)` (clamp, then smooth) - pixel 1 reads 2.67 / 4 - red.
    func testTheKernelFiltersTheSignedMapBeforeTheClamp() {
        let map: [Double] = [0, 8, -8, 0]
        let shown = SpectroscopyRoomController.display(of: map, width: 4, height: 1, smoothing: .box3)
        XCTAssertEqual(shown.scale, 4, accuracy: 1e-6, "the scale is the smoothed signed map's maximum")
        XCTAssertEqual(shown.values.count, 4)
        for (v, e) in zip(shown.values, [1, 0, 0, 0] as [Float]) { XCTAssertEqual(v, e, accuracy: 1e-6) }
        let clampedFirst = MapSmoothing.box3.apply(map.map { max($0, 0) }, width: 4, height: 1)
        XCTAssertGreaterThan(clampedFirst[1], 2, "precondition: the other order would have left pixel 1 bright")
    }

    /// No kernel is the picture the room always drew.
    /// Mutation: `display(of:)` ignoring `.none` (smoothing with the box regardless) - red.
    func testNoKernelIsTheRawPicture() {
        let map: [Double] = [0, 8, -8, 0]
        let shown = SpectroscopyRoomController.display(of: map, width: 4, height: 1, smoothing: .none)
        XCTAssertEqual(shown.values, picture(map))
        XCTAssertEqual(shown.scale, 8)
    }

    private func tilesWith(_ c: SpectroscopyRoomController, smoothing: MapSmoothing = .none) async throws {
        c.model.smoothing = smoothing
        c.model.elements.set(Cu, .quantify); c.model.elements.set(Al, .quantify)
        c.elementsChanged()
        try await waitFor("the tiles") { c.model.tiles.count == 2 }
    }

    /// A tile that lands under a kernel is the kernel's picture of its raw counts, and keeps the raw counts.
    /// Mutation: `apply` builds the tile with `smoothing: .none` - red (values are the raw picture).
    func testATileLandsSmoothedAndKeepsItsRawCounts() async throws {
        let (_, c) = open()
        try await tilesWith(c, smoothing: .box3)
        let cu = try XCTUnwrap(c.model.tiles.first { $0.z == Cu })
        XCTAssertEqual(cu.counts.count, cu.width * cu.height, "the raw signed counts are kept")
        XCTAssertNotEqual(cu.values, picture(cu.counts), "the Cu quadrant's edge is smoothed")
        XCTAssertEqual(cu.values, picture(MapSmoothing.box3.apply(cu.counts, width: cu.width, height: cu.height)))
        XCTAssertGreaterThan(cu.counts.max() ?? 0, 0)
    }

    /// Smooth changed: the tiles are rebuilt from their raw counts, nothing is recomputed (no new generation, the spectrum is the
    /// same object's data), the counts stay, the revision moves; back to none returns the first picture exactly.
    /// Mutations: the rebuild reads `t.values` (as Double) instead of `t.counts` - the round trip to none is no longer the first
    /// picture - red; `tileRevision` not bumped - red; `smoothingChanged` calling `refresh()` - generation moves - red.
    func testSmoothingChangedRebuildsTheTilesFromTheCountsAndComputesNothing() async throws {
        let (_, c) = open()
        try await tilesWith(c)
        let m = c.model
        let before = m.tiles, spectrum = m.series.data, generation = c.generation, revision = m.tileRevision
        let backdrop = m.backdrop
        m.smoothing = .box3
        c.smoothingChanged()
        XCTAssertEqual(m.tiles.map(\.counts), before.map(\.counts), "the raw counts are never touched")
        XCTAssertEqual(m.tiles.map(\.z), before.map(\.z))
        for (t, b) in zip(m.tiles, before) {
            XCTAssertEqual(t.values, picture(MapSmoothing.box3.apply(t.counts, width: t.width, height: t.height)), "Z \(t.z)")
            if t.z == Cu { XCTAssertNotEqual(t.values, b.values, "the Cu quadrant's edge changed") }
            else { XCTAssertEqual(t.values, b.values, "a flat map stays flat to the border (Al)") }
            XCTAssertEqual(t.scale, Float(max(MapSmoothing.box3.apply(t.counts, width: t.width, height: t.height).max() ?? 0, 0)), "the scale follows the kernel")
        }
        XCTAssertEqual(m.tileRevision, revision + 1, "the map's bitmap is rebuilt by identity")
        XCTAssertEqual(c.generation, generation, "nothing is recomputed")
        XCTAssertEqual(m.series.data, spectrum, "the spectrum is untouched")
        XCTAssertEqual(m.backdrop, backdrop, "the HAADF is never smoothed")
        m.smoothing = .none
        c.smoothingChanged()
        XCTAssertEqual(m.tiles.map(\.values), before.map(\.values), "none returns the first picture exactly")
        XCTAssertEqual(m.tiles.map(\.scale), before.map(\.scale))
    }

    // MARK: Row 2a, 2c: Auto ID's role rule and significance

    private func candidate(_ element: String, _ group: String, energy: Double, net: Double = 900, limit: Double = 300,
                           conflicts: [LineConflict] = []) -> ElementCandidate {
        ElementCandidate(element: element, group: group, energyKeV: energy, net: net, sigma: 30, sigmaZero: 90,
                         criticalLevel: 150, detectionLimit: limit, conflicts: conflicts,
                         suggestedRole: .fitOnly, holeRegionNote: nil, misfit: 1)
    }

    private func proposal(_ candidates: [ElementCandidate]) -> ProposalResult {
        ProposalResult(candidates: candidates, sumPeaks: [], refused: [], currie: .standard, notes: [], passes: 1, settled: true)
    }

    private var europium: ElementCandidate { candidate("Eu", "Eu_La", energy: 5.846) }
    private var copperK: ElementCandidate { candidate("Cu", "Cu_Ka", energy: 8.048) }

    /// With the k-factors Computed, an L-group pick is Fit only with its reason named; a K-group pick stays Quantify.
    /// Mutations: `isKGroup` always true - Eu quantifies - red; the prefix dropped - red; the rule applied to every pick - Cu
    /// is Fit only - red.
    func testAComputedKCoversKLinesOnly() throws {
        XCTAssertNotNil(XRayLines.line("Eu_La"), "precondition: the table knows Eu La")
        let o = AutoIDPresentation.outcome(proposal([europium, copperK]), region: "r", computedK: true)
        let byZ = Dictionary(uniqueKeysWithValues: o.suggestions.map { ($0.z, $0) })
        XCTAssertEqual(byZ[Eu]?.proposedRole, .fitOnly)
        XCTAssertTrue(try XCTUnwrap(byZ[Eu]).reason.hasPrefix("fit only (no computed k for L/M lines): net 900 counts"), byZ[Eu]?.reason ?? "no Eu")
        XCTAssertEqual(byZ[Cu]?.proposedRole, .quantify)
        XCTAssertFalse(try XCTUnwrap(byZ[Cu]).reason.contains("fit only"))
    }

    /// A typed k may cover any line: the old rule holds (Quantify), and so does the default of the call.
    /// Mutation: the `computedK &&` guard dropped - Eu is Fit only with a typed k - red.
    func testATypedKKeepsTheOldRule() {
        for o in [AutoIDPresentation.outcome(proposal([europium]), region: "r", computedK: false),
                  AutoIDPresentation.outcome(proposal([europium]), region: "r")] {
            XCTAssertEqual(o.suggestions.first?.proposedRole, .quantify)
            XCTAssertFalse(o.suggestions.first?.reason.contains("no computed k") ?? true)
        }
    }

    /// A FIB question stays Fit only whatever the k.
    /// Mutation: the role taken from `noK` alone - Ga is Quantify with a typed k - red.
    func testAFIBQuestionStaysFitOnly() {
        let ga = candidate("Ga", "Ga_Ka", energy: 9.251, conflicts: LineConflicts.conflicts(element: "Ga", line: "Ga_Ka", lineEnergyKeV: 9.251, parents: []))
        XCTAssertTrue(ga.conflicts.contains { $0.kind == .fibContamination }, "precondition")
        for computed in [false, true] {
            let s = AutoIDPresentation.outcome(proposal([ga]), region: "r", computedK: computed).suggestions
            XCTAssertEqual(s.first?.proposedRole, .fitOnly, "computedK \(computed)")
            XCTAssertFalse(s.first?.reason.contains("no computed k") ?? true, "a K line: the reason is the FIB question")
        }
    }

    /// The proposer's net / L_D rides on the suggestion (net 900 over a limit of 300 is 3.0).
    /// Mutation: `significance:` not passed (0) - red.
    func testSignificanceIsCarried() {
        let o = AutoIDPresentation.outcome(proposal([candidate("Mg", "Mg_Ka", energy: 1.254, net: 900, limit: 300),
                                                      candidate("Al", "Al_Ka", energy: 1.4865, net: 1200, limit: 300)]), region: "r")
        XCTAssertEqual(o.suggestions.map(\.z), [Al, 12], "strongest first")
        XCTAssertEqual(o.suggestions.map(\.significance), [4, 3])
    }

    /// The pick lands as Fit only, through the table's own click: no tile, no row, no at%, and the person's Off is still theirs.
    /// Mutation: `applyAutoIDPicks` setting `.quantify` for every suggestion - Eu quantifies - red.
    func testAFitOnlySuggestionLandsAsFitOnly() {
        let c = SpectroscopyRoomController(); let m = c.model
        let t = m.beginAutoID()
        m.finishAutoID(token: t, outcome: AutoIDPresentation.outcome(proposal([europium, copperK]), region: "r", computedK: true))
        XCTAssertTrue(c.applyAutoIDPicks())
        XCTAssertEqual(m.elements.role(Eu), .fitOnly)
        XCTAssertEqual(m.elements.role(Cu), .quantify)
        XCTAssertFalse(m.elements.quantified.contains(Eu), "a Fit-only element never enters at%")
        XCTAssertTrue(m.elements.activeZ.contains(Eu), "but it is fitted")
    }

    // MARK: Auto ID on a real spectrum reads the k-factor source

    /// A strong line at 6.72 keV (Ho L-alpha) on every pixel: with Computed k-factors Auto ID lands Ho as Fit only, with a Typed
    /// k as Quantify (the person's own factor may cover an L line). The controller reads the inspector's choice.
    /// Mutations: the run passing `computedK: false` - Ho quantifies with Computed k - red; `computedK: true` - Fit only with a
    /// Typed k - red.
    func testTheRunReadsTheKFactorSource() async throws {
        let Ho = 67
        for kind in [QuantificationMethod.KFactorSource.computed, .typed] {
            let (_, c) = open(image: Self.holmiumImage())
            c.model.quantify.kSource = kind
            c.runAutoID()
            try await waitFor("the outcome") { c.model.autoID.outcome != nil || c.model.autoID.failure != nil }
            XCTAssertNil(c.model.autoID.failure)
            let ho = c.model.autoID.outcome?.suggestions.first { $0.z == Ho }
            XCTAssertNotNil(ho, "precondition: the planted line is proposed as Ho")
            XCTAssertEqual(ho?.proposedRole, kind == .computed ? .fitOnly : .quantify, "\(kind)")
            XCTAssertEqual(c.model.elements.role(Ho), kind == .computed ? .fitOnly : .quantify, "the pick landed as proposed (\(kind))")
        }
    }

    private static func holmiumImage() -> LoadedSpectrumImage {
        let nx = 8, ny = 6, channels = 1024
        var counts = [UInt32](repeating: 0, count: nx * ny * channels)
        for p in 0..<(nx * ny) { for c in 0..<channels {
            let e = Double(c) * 0.01
            let v = 6 * exp(-e / 2) + 40 * exp(-pow(e - 1.487, 2) / (2 * 0.0035)) + 60 * exp(-pow(e - 6.720, 2) / (2 * 0.0100))
            counts[p * channels + c] = UInt32(v.rounded())
        } }
        var meta = SpectrumImageMetadata(fileName: "holmium", filePath: "", scanWidth: nx, scanHeight: ny, channelCount: channels,
                                         energyOffsetEV: 0, energyDispersionEV: 10)
        meta.beamEnergyKeV = 200
        return LoadedSpectrumImage(image: DenseSpectrumImage(ny: ny, nx: nx, channels: channels, counts: counts), metadata: meta,
                                   energyAxis: EnergyAxis(offset: 0, scale: 0.01, size: channels))
    }

    // MARK: Row 4b: the pixels behind the spectrum

    /// The whole map: nx * ny, from the open on. A drawn region: its own pixel count, the number the header prints.
    /// Mutations: `bind` not setting it - red at once; `apply` not setting it - the region keeps the whole map's 48 - red.
    func testTheSpectrumPixelsAreTheWholeMapsThenTheRegions() async throws {
        let (_, c) = open()
        XCTAssertEqual(c.model.spectrumPixels, 48, "8 x 6, set at the bind")
        c.editRegion(.rectangle(PixelRect(x0: 1, y0: 1, x1: 4, y1: 3)), final: true)
        if let t = c.lastRefresh { await t.value }
        let region = try XCTUnwrap(c.model.regions.first { $0.id == c.model.selectedRegion })
        XCTAssertEqual(region.pixels, 6)
        XCTAssertEqual(c.model.spectrumPixels, 6)
        c.selectRegion(id: 0)
        if let t = c.lastRefresh { await t.value }
        XCTAssertEqual(c.model.spectrumPixels, 48, "back on the whole map")
    }

    /// While the pointer is down the live sum lands its own series: its pixels are the region's too.
    /// Mutation: `landLiveSum` not setting it - 48 stays - red.
    func testTheLiveSumKeepsThePixelsOfItsRegion() async throws {
        let (_, c) = open()
        if let t = c.lastRefresh { await t.value }   // the open's own whole-map landing comes first
        c.editRegion(.rectangle(PixelRect(x0: 0, y0: 0, x1: 2, y1: 2)), final: false)
        try await waitFor("the live sum") { c.liveSums >= 1 }
        XCTAssertEqual(c.model.spectrumPixels, 4)
        if let t = c.lastRefresh { await t.value }
    }

    // MARK: Row 10a: the windows as energy bands

    private func window(_ id: String, _ element: String, signal: Range<Int>, left: Range<Int>, right: Range<Int>) -> LineWindow {
        LineWindow(element: element, id: id, energy: 1.4865, fwhm: 0.07,
                   window: ResolvedWindow(signal: signal, background: ResolvedWindow.Background(left: left, right: right, scale: 1)),
                   failure: nil, conflicts: [])
    }

    /// Channels 140..<158 of a 10 eV axis starting at 0 are 1.395-1.575 keV (half a channel either side of the first and last
    /// channel's energy); the background windows sit either side, labelled for the line.
    /// Mutations: the half-channel shift dropped - 1.40-1.58 - red; the right band built from the left range - red; the signal
    /// band marked `.background` - red.
    func testTheBandsAreTheWindowsInKeV() throws {
        let axis = EnergyAxis(offset: 0, scale: 0.01, size: 1024)
        let bands = SpectroscopyRoomController.windowBands(for: [window("Al_Ka", "Al", signal: 140..<158, left: 120..<138, right: 160..<178)], axis: axis)
        XCTAssertEqual(bands.map(\.id), ["Al_Ka.signal", "Al_Ka.left", "Al_Ka.right"])
        XCTAssertEqual(bands.map(\.kind), [.signal, .background, .background])
        XCTAssertEqual(bands.map(\.elementZ), [Al, Al, Al])
        XCTAssertEqual(bands.map(\.label), ["Al K\u{03B1}", "Al K\u{03B1}", "Al K\u{03B1}"])
        let expected: [ClosedRange<Double>] = [1.395...1.575, 1.195...1.375, 1.595...1.775]
        for (b, e) in zip(bands, expected) {
            XCTAssertEqual(b.range.lowerBound, e.lowerBound, accuracy: 1e-9, b.id)
            XCTAssertEqual(b.range.upperBound, e.upperBound, accuracy: 1e-9, b.id)
        }
    }

    /// A line with no window (nothing on the axis) draws no band; a window with no background draws only its signal band.
    /// Mutation: the `guard let r = w.window` dropped for a default range - a band for a failed line - red.
    func testALineWithoutWindowsHasNoBands() {
        let axis = EnergyAxis(offset: 0, scale: 0.01, size: 1024)
        let none = LineWindow(element: "Eu", id: "Eu", energy: 0, fwhm: 0, window: nil, failure: "no line", conflicts: [])
        let bare = LineWindow(element: "Cu", id: "Cu_Ka", energy: 8.04, fwhm: 0.15,
                              window: ResolvedWindow(signal: 790..<820, background: nil), failure: nil, conflicts: [])
        let bands = SpectroscopyRoomController.windowBands(for: [none, bare], axis: axis)
        XCTAssertEqual(bands.map(\.id), ["Cu_Ka.signal"])
    }

    /// The live room fills the bands for the listed elements' own windows, around each line's energy.
    /// Mutation: `apply` not setting `windowBands` - empty - red.
    func testTheRoomFillsTheBandsFromTheListedElements() async throws {
        let (_, c) = open()
        XCTAssertTrue(c.model.windowBands.isEmpty, "no element, no window")
        try await tilesWith(c)
        let al = c.model.windowBands.filter { $0.elementZ == Al }
        XCTAssertEqual(al.filter { $0.kind == .signal }.count, 1)
        XCTAssertEqual(al.filter { $0.kind == .background }.count, 2)
        let signal = try XCTUnwrap(al.first { $0.kind == .signal })
        XCTAssertTrue(signal.range.contains(1.4865), "the signal band holds Al K\u{03B1}: \(signal.range)")
        let sides = al.filter { $0.kind == .background }
        XCTAssertTrue(sides.contains { $0.range.upperBound <= signal.range.lowerBound + 1e-9 })
        XCTAssertTrue(sides.contains { $0.range.lowerBound >= signal.range.upperBound - 1e-9 })
    }

    // MARK: A candidate picked from the spectrum

    /// The spectrum's cursor menu picks through the periodic table's own click.
    /// Mutation: `bind` not setting `onPickElement` - nil - red; its body setting Fit only - red.
    func testAPickFromTheSpectrumIsTheTablesClick() throws {
        let (_, c) = open()
        let pick = try XCTUnwrap(c.model.onPickElement)
        pick(Al)
        XCTAssertEqual(c.model.elements.role(Al), .quantify)
        XCTAssertTrue(c.model.elements.manual.contains(Al), "a pick by hand is the person's")
        pick(Al)
        XCTAssertEqual(c.model.elements.role(Al), .off, "the table's click toggles")
    }
}


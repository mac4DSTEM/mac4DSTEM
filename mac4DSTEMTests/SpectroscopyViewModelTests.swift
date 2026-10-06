//
//  SpectroscopyViewModelTests.swift
//  v5.0 WP2 lane V — the Spectroscopy room's pure half (`SpectroscopyLogic.swift`).
//  Every test names the mutation it catches. Break each one before trusting it.
//

import XCTest
import SwiftUI
@testable import mac4DSTEM

@MainActor
final class SpectroscopyViewModelTests: XCTestCase {
    private let Mg = 12, Al = 13, Si = 14, Cu = 29, Ga = 31, Ar = 18

    // Mutation: click() sets .fitOnly, or forgets to mark the element manual.
    func testClickTogglesQuantifyAndOff() {
        var e = ElementSelection()
        e.click(Mg); XCTAssertEqual(e.role(Mg), .quantify); XCTAssertTrue(e.manual.contains(Mg))
        e.click(Mg); XCTAssertEqual(e.role(Mg), .off)
    }

    // Mutation: click() lets Fit only stay Fit only (toggle only quantify<->off from off).
    func testClickOnFitOnlyTurnsQuantify() {
        var e = ElementSelection(); e.set(Cu, .fitOnly); e.click(Cu)
        XCTAssertEqual(e.role(Cu), .quantify)
    }

    // Mutation: remove the unavailable guard.
    func testUnavailableElementsRefuseClicks() {
        var e = ElementSelection(); e.click(1); e.set(4, .quantify)
        XCTAssertEqual(e.cellState(1), .unavailable("No usable X-ray line at this detector window"))
        XCTAssertEqual(e.role(4), .off); XCTAssertTrue(e.manual.isEmpty)
    }

    // Mutation: set() leaves the suggestion pending.
    func testMenuChoiceResolvesSuggestion() {
        var e = ElementSelection(suggestions: [ElementSuggestion(z: Ga, reason: "Ga: from FIB?")])
        XCTAssertEqual(e.cellState(Ga), .suggested("Ga: from FIB?"))
        e.set(Ga, .off)
        XCTAssertEqual(e.cellState(Ga), .off); XCTAssertTrue(e.suggestions.isEmpty)
    }

    // Mutation: accept() overwrites a manual choice, or applies the role of the wrong suggestion.
    func testAcceptingOneSuggestionKeepsManualPicksAndOthers() {
        var e = ElementSelection(roles: [Cu: .fitOnly, Ar: .off], manual: [Cu, Ar],
                                 suggestions: [ElementSuggestion(z: Cu, reason: "x"), ElementSuggestion(z: Ga, reason: "y"),
                                               ElementSuggestion(z: 6, reason: "C?")])
        e.accept(Cu, as: .quantify)                      // owner already chose Fit only
        XCTAssertEqual(e.role(Cu), .fitOnly)
        e.accept(Ga, as: .fitOnly)                       // the role picked on the row, not proposedRole
        XCTAssertEqual(e.role(Ga), .fitOnly)
        XCTAssertEqual(e.suggestions.map(\.z), [6], "only the accepted/dismissed ones leave")
        XCTAssertEqual(e.role(Ar), .off)
    }

    // Mutation: click ignores the pending suggestion (toggles instead of applying proposedRole).
    func testClickOnSuggestedCellAppliesProposedRole() {
        var e = ElementSelection(suggestions: [ElementSuggestion(z: Ga, reason: "Ga?", proposedRole: .fitOnly)])
        e.click(Ga)
        XCTAssertEqual(e.role(Ga), .fitOnly); XCTAssertTrue(e.suggestions.isEmpty)
    }

    // Mutation: rerunAutoID clears every role instead of only the non-manual ones.
    func testAutoIDRerunNeverDropsManualPicks() {
        var e = ElementSelection()
        e.set(Mg, .quantify); e.set(Cu, .fitOnly); e.set(Ar, .off)
        e.rerunAutoID(accepted: [Al: .quantify, Si: .quantify], suggestions: [])
        e.rerunAutoID(accepted: [Si: .quantify], suggestions: [ElementSuggestion(z: Ar, reason: "Ar?"), ElementSuggestion(z: Ga, reason: "Ga?")])
        XCTAssertEqual(e.role(Mg), .quantify); XCTAssertEqual(e.role(Cu), .fitOnly)
        XCTAssertEqual(e.role(Ar), .off, "a manual Off is not re-suggested")
        XCTAssertEqual(e.suggestions.map(\.z), [Ga])
        XCTAssertEqual(e.role(Al), .off, "an earlier automatic pick no longer proposed falls away")
        XCTAssertEqual(e.role(Si), .quantify)
    }

    // Mutation: floor/ceil swapped, or the epsilon dropped (10^3 exactly is a tick).
    func testLogDecadeTicks() {
        XCTAssertEqual(AxisTicks.logDecades(lo: 10, hi: 1e5), [1, 2, 3, 4, 5])
        XCTAssertEqual(AxisTicks.logDecades(lo: 15, hi: 4000), [2, 3])
        XCTAssertEqual(AxisTicks.logDecades(lo: 0, hi: 100), [])
    }

    // Mutation: nice-step table loses 5, or `first` rounds down.
    func testLinearTicks() {
        let t = AxisTicks.linear(lo: 0.5, hi: 2.5, target: 4)
        XCTAssertEqual(t.first!, 0.5, accuracy: 1e-9); XCTAssertEqual(t.last!, 2.5, accuracy: 1e-9)
        XCTAssertEqual(t.count, 5)
        XCTAssertEqual(AxisTicks.linear(lo: 0, hi: 100, target: 5), [0, 20, 40, 60, 80, 100])
        XCTAssertTrue(AxisTicks.linear(lo: 0.55, hi: 2.3, target: 6).allSatisfy { $0 >= 0.55 }, "no tick left of the window")
    }

    // Mutation: fraction uses `hi` instead of span.
    func testEnergyToFractionMapping() {
        var v = SpectrumViewport(domain: 0.5...2.5)
        XCTAssertEqual(v.fraction(of: 0.5), 0); XCTAssertEqual(v.fraction(of: 2.5), 1)
        XCTAssertEqual(v.fraction(of: 1.5), 0.5, accuracy: 1e-12)
        v.zoom(factor: 2, anchor: 0.5)
        XCTAssertEqual(v.lo, 1.0, accuracy: 1e-12); XCTAssertEqual(v.hi, 2.0, accuracy: 1e-12)
        XCTAssertEqual(v.energy(atFraction: 0.25), 1.25, accuracy: 1e-12)
    }

    // Mutation: zoom ignores the anchor (zooms about lo).
    func testZoomKeepsAnchorEnergyFixed() {
        var v = SpectrumViewport(domain: 0.5...2.5)
        let before = v.energy(atFraction: 0.25)
        v.zoom(factor: 4, anchor: 0.25)
        XCTAssertEqual(v.energy(atFraction: 0.25), before, accuracy: 1e-12)
        XCTAssertEqual(v.span, 0.5, accuracy: 1e-12)
    }

    // Mutation: clamp removed, or zoom-out allowed past the domain.
    func testZoomPanClamp() {
        var v = SpectrumViewport(domain: 0.5...2.5)
        v.zoom(factor: 0.1, anchor: 0.5)                       // zoom out past the data
        XCTAssertEqual(v.lo, 0.5); XCTAssertEqual(v.hi, 2.5)
        v.zoom(factor: 10, anchor: 0.5)
        v.pan(byFraction: 50); XCTAssertEqual(v.hi, 2.5, accuracy: 1e-12); XCTAssertEqual(v.span, 0.2, accuracy: 1e-12)
        v.pan(byFraction: -50); XCTAssertEqual(v.lo, 0.5, accuracy: 1e-12)
        v.zoom(factor: 1e9, anchor: 0.5); XCTAssertGreaterThanOrEqual(v.span, v.minimumSpan - 1e-12)
        var fine = SpectrumViewport(domain: 0.5...2.5, minimumSpan: 0.5)
        fine.zoom(factor: 1e6, anchor: 0.5); XCTAssertEqual(fine.span, 0.5, accuracy: 1e-12, "minimum span is per instance (2 channels)")
        v.reset(); XCTAssertEqual(v.span, 2.0)
    }

    // Mutation: divide by m instead of sqrt(m); or drop the m<=0 guard (NaN).
    func testResidualNormalisation() {
        let r = ResidualNormalisation.normalised(data: [110, 90, 5, 7], model: [100, 100, 0, -1])
        XCTAssertEqual(r[0], 1, accuracy: 1e-12); XCTAssertEqual(r[1], -1, accuracy: 1e-12)
        XCTAssertEqual(r[2], 0); XCTAssertEqual(r[3], 0)
        XCTAssertEqual(ResidualNormalisation.normalised(data: [40], model: [16])[0], 6, accuracy: 1e-12)
    }

    // Mutation: a symbol dropped or inserted (the table is a list of 118).
    func testPeriodicSymbols() {
        XCTAssertEqual(PeriodicLayout.symbols.count, 118)
        XCTAssertEqual(PeriodicLayout.symbol(14), "Si"); XCTAssertEqual(PeriodicLayout.z(of: "Cu"), 29)
    }

    // Mutation: the fixture's unvalidated flag is dropped.
    func testFixtureCarriesBadgeAndUnavailableCells() {
        let m = SpectroscopyRoomModel.fixture
        XCTAssertTrue(m.unvalidated)
        XCTAssertFalse(m.elements.manual.contains(Cu), "Cu is a default, not a manual pick")
        XCTAssertEqual(SpectroscopyRoomModel(series: m.series).image.liveDead, nil, "defaults carry no readouts")
        XCTAssertNil(SpectroscopyRoomModel(series: m.series).quantify.quality)
        XCTAssertNil(SpectroscopyRoomModel(series: m.series).quantify.thickness)
        XCTAssertEqual(m.elements.cellState(Cu), .quantify)
        if case .suggested = m.elements.cellState(Ga) {} else { XCTFail("Ga should be suggested") }
        if case .unavailable = m.elements.cellState(3) {} else { XCTFail("Li should be unavailable") }
    }

    // Mutation: hasModel checks only `!data.isEmpty` (indexes an empty model); residual unguarded.
    func testDataOnlySeriesHasNoModelAndRendersWithoutTrapping() throws {
        let data = (0..<100).map { Double($0 % 7) }
        let series = SpectrumSeries(energyStart: 0.5, energyStep: 0.01, data: data, background: [], model: [], overlay: nil)
        XCTAssertFalse(series.hasModel); XCTAssertFalse(series.hasBackground); XCTAssertEqual(series.residual, [])
        let m = SpectroscopyRoomModel(series: series)
        m.markers = [LineMarker(label: "Al Kα", energy: 1.2, elementZ: 13)]
        for width: CGFloat in [900, 500] {
            let r = ImageRenderer(content: SpectroscopyRoomContent(model: m).frame(width: width, height: 600))
            XCTAssertNotNil(r.cgImage, "a data-only series must draw (no index out of range)")
        }
        // a mismatched-length model is also "no model"
        var bad = series; bad.model = [1, 2, 3]
        XCTAssertFalse(bad.hasModel)
    }

    // Mutation: the isFinite guard removed (lo = +inf -> NaN coordinates).
    func testLogRangeWithNoPositiveCountsIsFinite() {
        let r = SpectrumYRange.log(minPositive: .infinity, maximum: 1)
        XCTAssertEqual(r.lo, 1); XCTAssertTrue(r.hi.isFinite); XCTAssertGreaterThan(r.hi, r.lo)
        let n = SpectrumYRange.log(minPositive: 12, maximum: 4000)
        XCTAssertEqual(n.lo, 10); XCTAssertEqual(n.hi, 10_000)
        let zeros = SpectrumSeries(energyStart: 0.5, energyStep: 0.01, data: [Double](repeating: 0, count: 50),
                                   background: [], model: [], overlay: nil)
        let m = SpectroscopyRoomModel(series: zeros)
        XCTAssertNotNil(ImageRenderer(content: SpectrumStripView(model: m).frame(width: 600, height: 300)).cgImage)
    }

    // Mutation: decimals fixed at 1, or derived from the range instead of the step.
    func testTickLabelDecimalsFollowTheStep() {
        XCTAssertEqual(AxisTicks.decimals(forStep: 0.5), 1); XCTAssertEqual(AxisTicks.decimals(forStep: 0.02), 2)
        XCTAssertEqual(AxisTicks.decimals(forStep: 1), 0); XCTAssertEqual(AxisTicks.decimals(forStep: 0.1), 1); XCTAssertEqual(AxisTicks.decimals(forStep: 0.005), 3)
        let step = AxisTicks.niceStep(lo: 0.50, hi: 0.60, target: 5)
        let labels = AxisTicks.linear(lo: 0.50, hi: 0.60, target: 5).map { AxisTicks.label($0, step: step) }
        XCTAssertEqual(Set(labels).count, labels.count, "neighbouring ticks must not print alike: \(labels)")
    }

    // Mutation: nearest line ignores the tolerance; channel index off by one; edge markers count as lines.
    func testHoverSampleEnergyCountsAndNearestLine() throws {
        let m = SpectroscopyRoomModel.fixture
        let vp = SpectrumViewport(domain: m.series.domain)
        let f = vp.fraction(of: 1.254)
        let smp = try XCTUnwrap(SpectrumHover.sample(series: m.series, viewport: vp, fraction: f, markers: m.markers))
        XCTAssertEqual(smp.energy, 1.25, accuracy: 1e-9)
        XCTAssertEqual(smp.counts, m.series.data[75])
        XCTAssertEqual(smp.line, "Mg Kα")
        let far = try XCTUnwrap(SpectrumHover.sample(series: m.series, viewport: vp, fraction: vp.fraction(of: 2.2), markers: m.markers))
        XCTAssertNil(far.line)
        let edge = try XCTUnwrap(SpectrumHover.sample(series: m.series, viewport: vp, fraction: vp.fraction(of: 1.56), markers: m.markers))
        XCTAssertNotEqual(edge.line, "Al K edge")
        XCTAssertNil(SpectrumHover.sample(series: m.series, viewport: vp, fraction: 1.2, markers: m.markers))
    }

    // Mutation: nil/empty counted as validated, or "none" case-sensitive.
    func testUnvalidatedIsDerivedFromTheValidationString() {
        XCTAssertTrue(ValidationState.isUnvalidated(nil)); XCTAssertTrue(ValidationState.isUnvalidated(""))
        XCTAssertTrue(ValidationState.isUnvalidated("none")); XCTAssertTrue(ValidationState.isUnvalidated("None"))
        XCTAssertFalse(ValidationState.isUnvalidated("truth.json 1 dataset"))
        let m = SpectroscopyRoomModel.fixture
        m.validation = "truth.json"; XCTAssertFalse(m.unvalidated)
        m.validation = nil; XCTAssertTrue(m.unvalidated)
    }

    // Mutation: isClipped uses >= 3 or drops the abs.
    func testResidualClipping() {
        XCTAssertTrue(ResidualNormalisation.isClipped(3.01)); XCTAssertTrue(ResidualNormalisation.isClipped(-4))
        XCTAssertFalse(ResidualNormalisation.isClipped(3)); XCTAssertFalse(ResidualNormalisation.isClipped(-2.9))
    }

    // MARK: render check (writes PNGs when SPECTROSCOPY_RENDER_DIR is set)

    func testRenderRoom() throws {
        guard let dir = ProcessInfo.processInfo.environment["SPECTROSCOPY_RENDER_DIR"] else {
            throw XCTSkip("set TEST_RUNNER_SPECTROSCOPY_RENDER_DIR to write the PNGs")
        }
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        func render(_ name: String, _ w: CGFloat, _ h: CGFloat, _ v: some View) throws {
            let r = ImageRenderer(content: v.frame(width: w, height: h).background(Color(white: 0.96)).environment(\.colorScheme, .light))
            r.scale = 2
            let img = try XCTUnwrap(r.cgImage)
            let rep = NSBitmapImageRep(cgImage: img)
            try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: "\(dir)/\(name).png"))
        }
        let m = SpectroscopyRoomModel.fixture
        try render("room-wide", 1000, 740, SpectroscopyRoomContent(model: m))
        try render("room-narrow", 600, 900, SpectroscopyRoomContent(model: m))
        try render("inspector", 320, 900, SpectroscopyInspectorSections(model: m, startOpen: true).padding(12))
    }
}

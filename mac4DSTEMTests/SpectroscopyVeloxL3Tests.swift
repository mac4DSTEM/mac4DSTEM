//
//  SpectroscopyVeloxL3Tests.swift
//  Lane L3 (the Velox sheet, 2026-10-07): the spectrum's cursor candidates (row 3a), counts per pixel (4b), the window bands
//  (10a) and the range readout (13a). Every test names the mutation it catches; each was broken once and seen red (the lane
//  report lists them).
//

import XCTest
import DSTEMCore
@testable import mac4DSTEM

@MainActor
final class SpectroscopyVeloxL3Tests: XCTestCase {
    private let Al = 13, Ar = 18, Cu = 29, Si = 14
    private let de = Locale(identifier: "de_DE")

    private func labels(_ c: [SpectrumHover.Candidate]) -> [String] { c.map(\.label) }

    // MARK: candidates (3a)

    /// 2,957 keV with Al listed: Ar Kα (0.7 eV away) and the Al Kα+Kα pile-up sum (2 × 1,4865 = 2,973) are both named, Ar first
    /// by distance. Mutation: the sum branch removed, or the order by element number (Al's sum before Ar), red.
    func testCandidatesAtArKAlphaNameArFirstThenTheAlSum() throws {
        let c = SpectrumHover.candidates(at: 2.957, resolutionMnKaEV: 130, listed: [Al])
        let ar = try XCTUnwrap(c.firstIndex { $0.label == "Ar Kα" })
        let sum = try XCTUnwrap(c.firstIndex { $0.label == "Al Kα+Kα sum" })
        XCTAssertEqual(c[ar].kind, .line); XCTAssertEqual(c[ar].z, Ar)
        XCTAssertEqual(c[sum].kind, .sum); XCTAssertEqual(c[sum].energy, 2 * 1.4865, accuracy: 1e-9)
        XCTAssertEqual(ar, 0, "Ar Kα is the closest")
        XCTAssertLessThan(ar, sum)
        // Al not listed: no sum is invented for it.
        XCTAssertFalse(labels(SpectrumHover.candidates(at: 2.957, resolutionMnKaEV: 130, listed: [])).contains("Al Kα+Kα sum"))
    }

    /// 8,04 keV with Cu listed: Cu Kα first. Mutation: the listed-first rank dropped (see the next test for the case it governs).
    func testCandidatesAtCuKAlphaNameCuFirst() {
        let c = SpectrumHover.candidates(at: 8.04, resolutionMnKaEV: 130, listed: [Cu])
        XCTAssertEqual(c.first?.label, "Cu Kα")
        XCTAssertEqual(c.first?.kind, .line)
    }

    /// At 8,10 keV Ta Lα (8,146) is closer than Cu Kα (8,048): the listed element still comes first; unlisted, distance rules.
    /// Mutation: the rank (listed first) removed, or applied to every kind (sums too), red.
    func testAListedLineComesBeforeACloserUnlistedOne() {
        let listed = SpectrumHover.candidates(at: 8.10, resolutionMnKaEV: 130, listed: [Cu])
        XCTAssertEqual(listed.first?.label, "Cu Kα")
        XCTAssertTrue(labels(listed).contains("Ta Lα"))
        XCTAssertEqual(SpectrumHover.candidates(at: 8.10, resolutionMnKaEV: 130, listed: []).first?.label, "Ta Lα")
    }

    /// A listed element's own sum does not outrank an unlisted line (it is named, after Ar): rank is for lines only.
    /// Mutation: rank 0 for every candidate of a listed element, red.
    func testASumDoesNotOutrankAnUnlistedLine() {
        let c = SpectrumHover.candidates(at: 2.9844, resolutionMnKaEV: 130, listed: [Al])   // on Ag Lα; the Al sum (2,973) is 11 eV away
        XCTAssertEqual(c.first?.label, "Ag Lα")
    }

    /// The Si escape of a listed line: Cu Kα − 1,740 keV = 6,3078 keV is named "Cu Kα esc"; Cu unlisted: not named. At 0 keV the
    /// Si Kα escape would be −0,0003 keV and is never named. Mutation: the `esc > 0` guard dropped, or the escape energy wrong
    /// (1.74 → 1.84), red.
    func testTheSiEscapeOfAListedLine() throws {
        let esc = try XCTUnwrap(SpectrumHover.candidates(at: 6.3078, resolutionMnKaEV: 130, listed: [Cu]).first { $0.kind == .escape })
        XCTAssertEqual(esc.label, "Cu Kα esc"); XCTAssertEqual(esc.energy, 8.0478 - 1.740, accuracy: 1e-9)
        XCTAssertTrue(SpectrumHover.candidates(at: 6.3078, resolutionMnKaEV: 130, listed: []).allSatisfy { $0.kind == .line })
        XCTAssertTrue(SpectrumHover.candidates(at: 0, resolutionMnKaEV: 130, listed: [Si]).allSatisfy { $0.kind != .escape })
    }

    /// ± 1 FWHM: at Ar Kα the width is 97,7 eV, so 90 eV away names it and 105 eV away does not; a worse detector widens it.
    /// Mutation: 2 × FWHM, or the 0,1 keV fallback used always, red.
    func testTheToleranceIsOneFWHMOfTheLinesOwnEnergy() {
        func hasAr(_ e: Double, res: Double = 130) -> Bool { labels(SpectrumHover.candidates(at: e, resolutionMnKaEV: res, listed: [])).contains("Ar Kα") }
        XCTAssertTrue(hasAr(2.9577 + 0.090))
        XCTAssertFalse(hasAr(2.9577 + 0.105))
        XCTAssertTrue(hasAr(2.9577 + 0.105, res: 150))
        XCTAssertTrue(SpectrumHover.candidates(at: 5.0, resolutionMnKaEV: 130, listed: []).allSatisfy { $0.kind == .line })
    }

    /// Only α lines, never H or He's ionisation energies. Mutation: `notRealLines` ignored (H "Kα" at 1,36 eV), or Kβ admitted
    /// (Ar Kβ at 3,1905 keV would be named, as "Ar Kα").
    func testOnlyAlphaLinesAndNoHydrogen() {
        XCTAssertTrue(SpectrumHover.candidates(at: 0.0014, resolutionMnKaEV: 130, listed: []).allSatisfy { $0.z > 2 })
        let atArKb = SpectrumHover.candidates(at: 3.1905, resolutionMnKaEV: 130, listed: [])
        XCTAssertFalse(atArKb.contains { abs($0.energy - 3.1905) < 1e-6 })
    }

    /// `sample` carries the candidates, built from the listed elements, and keeps its marker rule. Mutation: `listed` unused
    /// (no sum), the marker rule dropped.
    func testTheSampleCarriesTheCandidates() throws {
        let m = SpectroscopyRoomModel.fixture
        let vp = SpectrumViewport(domain: m.series.domain)
        let smp = try XCTUnwrap(SpectrumHover.sample(series: m.series, viewport: vp, fraction: vp.fraction(of: 1.4865), markers: m.markers, listed: [Al]))
        XCTAssertEqual(smp.line, "Al Kα")
        XCTAssertEqual(smp.candidates.first?.label, "Al Kα")
        let wide = SpectrumSeries(energyStart: 0.5, energyStep: 0.01, data: [Double](repeating: 3, count: 400), background: [], model: [], overlay: nil)
        let vw = SpectrumViewport(domain: wide.domain)
        let sum = try XCTUnwrap(SpectrumHover.sample(series: wide, viewport: vw, fraction: vw.fraction(of: 2.973), markers: [], listed: [Al]))
        XCTAssertTrue(labels(sum.candidates).contains("Al Kα+Kα sum"))
        let none = try XCTUnwrap(SpectrumHover.sample(series: wide, viewport: vw, fraction: vw.fraction(of: 2.973), markers: [], listed: []))
        XCTAssertFalse(labels(none.candidates).contains("Al Kα+Kα sum"))
    }

    // MARK: the readout text

    /// "2,957 keV · 1 380 counts · Ar Kα · Al Kα+Kα sum": the energy in the person's locale, the thin-grouped counts, at most
    /// three names. Mutation: the locale ignored, the name cap 3 → 4, the grouping lost, red.
    func testTheReadoutText() {
        let s = SpectrumHover.Sample(energy: 2.957, counts: 1380, line: nil, candidates: [
            .init(z: Ar, label: "Ar Kα", energy: 2.9577, kind: .line), .init(z: Al, label: "Al Kα+Kα sum", energy: 2.973, kind: .sum),
            .init(z: 47, label: "Ag Lα", energy: 2.9844, kind: .line), .init(z: 90, label: "Th Mα", energy: 2.9964, kind: .line)])
        let text = SpectrumReadout.parts(s, locale: de).joined(separator: SpectrumReadout.separator)
        XCTAssertEqual(text, "2,957 keV · 1\u{202F}380 counts · Ar Kα · Al Kα+Kα sum · Ag Lα")
    }

    /// A marker's own line is the first name (today's rule) and is not named twice. Mutation: no dedupe, or the line last.
    func testTheListedLineIsNamedFirstOnce() {
        let s = SpectrumHover.Sample(energy: 8.04, counts: 5, line: "Cu Kα", candidates: [
            .init(z: Cu, label: "Cu Kα", energy: 8.0478, kind: .line), .init(z: 73, label: "Ta Lα", energy: 8.146, kind: .line)])
        XCTAssertEqual(Array(SpectrumReadout.parts(s, locale: de).dropFirst(2)), ["Cu Kα", "Ta Lα"])
    }

    /// Per pixel the counts read "0,027 counts/px". Mutation: the divisor ignored, "counts" kept in the unit.
    func testThePerPixelReadout() {
        let s = SpectrumHover.Sample(energy: 1.4865, counts: 2.7, line: nil)
        XCTAssertEqual(SpectrumReadout.parts(s, divisor: 100, locale: de)[1], "0,027 counts/px")
        XCTAssertEqual(SpectrumReadout.perPixel(250, locale: de), "250")
        XCTAssertEqual(SpectrumReadout.perPixel(12.34, locale: de), "12,3")
    }

    /// The box grows to the text and caps: trailing names go and "…" says so; the energy never goes. Mutation: no cap, "…" lost,
    /// the first part dropped.
    func testTheReadoutFitsOrTrimsWithAnEllipsis() {
        let w: (String) -> CGFloat = { CGFloat($0.count) * 10 }
        let parts = ["2,957 keV", "1 380 counts", "Ar Kα", "Al Kα+Kα sum"]
        XCTAssertEqual(SpectrumReadout.fit(parts, cap: 1000, width: w), parts.joined(separator: " · "))
        XCTAssertEqual(SpectrumReadout.fit(parts, cap: 260, width: w), "2,957 keV · 1 380 counts…")
        XCTAssertEqual(SpectrumReadout.fit(parts, cap: 5, width: w), "2,957 keV…")
        XCTAssertEqual(SpectrumReadout.widthCap, 320)
    }

    // MARK: counts per pixel (4b)

    /// Mutation: multiplied instead of divided; the guard dropped (a 0-pixel region gives inf/NaN, a 0 divisor).
    func testPerPixelDividesAndGuardsZeroPixels() {
        XCTAssertEqual(SpectrumScale.perPixel([100, 50, 0], pixels: 100), [1, 0.5, 0])
        XCTAssertEqual(SpectrumScale.perPixel([100, 50], pixels: 0), [100, 50])
        XCTAssertEqual(SpectrumScale.perPixel([100], pixels: -3), [100])
        XCTAssertEqual(SpectrumScale.divisor(perPixel: true, pixels: 25), 25)
        XCTAssertEqual(SpectrumScale.divisor(perPixel: false, pixels: 25), 1)
        XCTAssertEqual(SpectrumScale.divisor(perPixel: true, pixels: 0), 1, "the toggle on with no pixel count draws counts")
    }

    /// The log axis's floor is one raw count in the plotted unit. Mutation: the floor fixed at 1, red.
    func testTheLogFloorFollowsTheUnit() {
        XCTAssertEqual(SpectrumYRange.log(minPositive: 0.02, maximum: 3, unit: 0.01).lo, 0.01, accuracy: 1e-12)
        XCTAssertEqual(SpectrumYRange.log(minPositive: 0.5, maximum: 300).lo, 1)
        XCTAssertEqual(SpectrumYRange.log(minPositive: .infinity, maximum: 0, unit: 0.01).lo, 0.01)
    }

    /// Mutation: the unit title ignores the toggle.
    func testTheAxisTitleNamesThePixel() {
        XCTAssertEqual(SpectrumReadout.yAxisTitle(channelEV: 20, perPixel: false), "counts / 20 eV")
        XCTAssertEqual(SpectrumReadout.yAxisTitle(channelEV: 20, perPixel: true), "counts / px / 20 eV")
    }

    // MARK: windows (10a)

    /// Signal 8 %, background 5 % (faint, in that order). Mutation: the two swapped.
    func testTheWindowBandOpacities() {
        XCTAssertEqual(WindowBandStyle.opacity(.signal), 0.08)
        XCTAssertEqual(WindowBandStyle.opacity(.background), 0.05)
    }

    // MARK: range readout (13a)

    private func ramp() -> SpectrumSeries {   // channel i at 1.0 + 0.1 i keV, counts i + 1: total 55
        SpectrumSeries(energyStart: 1.0, energyStep: 0.1, data: (1...10).map(Double.init), background: [], model: [], overlay: nil)
    }

    /// 1,3 to 1,6 keV is channels 3...6 (counts 4 + 5 + 6 + 7 = 22) of 55, whichever way it was dragged. Mutation: the 1e-9
    /// rounding guard dropped (1,3 lands on channel 3 + 4e-16 and the first channel is lost), the end exclusive, the fraction
    /// taken of the range instead of the total.
    func testRangeCountsAndFraction() {
        let r = SpectrumHover.range(series: ramp(), from: 1.3, to: 1.6)
        XCTAssertEqual(r.counts, 22); XCTAssertEqual(r.fraction, 22.0 / 55.0, accuracy: 1e-12)
        let back = SpectrumHover.range(series: ramp(), from: 1.6, to: 1.3)
        XCTAssertEqual(back.counts, 22)
    }

    /// Outside the axis the range clamps; an empty series or a range between channels reads 0. Mutation: no clamp (a trap).
    func testRangeClampsAndHandlesEmpty() {
        XCTAssertEqual(SpectrumHover.range(series: ramp(), from: -5, to: 99).counts, 55)
        XCTAssertEqual(SpectrumHover.range(series: ramp(), from: 1.31, to: 1.39).counts, 0)
        let none = SpectrumSeries(energyStart: 0, energyStep: 0.01, data: [], background: [], model: [], overlay: nil)
        XCTAssertEqual(SpectrumHover.range(series: none, from: 0, to: 1).counts, 0)
        let flat = SpectrumSeries(energyStart: 0, energyStep: 0.01, data: [0, 0, 0], background: [], model: [], overlay: nil)
        XCTAssertEqual(SpectrumHover.range(series: flat, from: 0, to: 1).fraction, 0)
    }

    /// "1,40–1,60 keV · 61 230 counts · 15,4 % of the region", and per pixel. Mutation: the order of the range not normalised,
    /// the percent not scaled ×100, counts/px not used.
    func testTheRangeText() {
        XCTAssertEqual(SpectrumReadout.rangeText(from: 1.4, to: 1.6, counts: 61_230, fraction: 0.154, locale: de),
                       "1,40–1,60 keV · 61\u{202F}230 counts · 15,4 % of the region")
        XCTAssertEqual(SpectrumReadout.rangeText(from: 1.6, to: 1.4, counts: 61_230, fraction: 0.154, divisor: 1000, locale: de),
                       "1,40–1,60 keV · 61,2 counts/px · 15,4 % of the region")
    }

    // MARK: the gesture (13a)

    /// ⌥ is what separates the range drag from the pan; the counts gutter always stretches. Mutation: ⌥ ignored (range never, or
    /// always), the gutter test dropped.
    func testOptionDistinguishesTheRangeDragFromThePan() {
        XCTAssertEqual(SpectrumStripLogic.dragMode(optionHeld: false, startX: 200, plotLeft: 46), .pan)
        XCTAssertEqual(SpectrumStripLogic.dragMode(optionHeld: true, startX: 200, plotLeft: 46), .range)
        XCTAssertEqual(SpectrumStripLogic.dragMode(optionHeld: false, startX: 10, plotLeft: 46), .stretchY)
        XCTAssertEqual(SpectrumStripLogic.dragMode(optionHeld: true, startX: 10, plotLeft: 46), .stretchY)
    }

    /// The range's ends from the drag: x as a fraction of the frame, clamped to it, to energies. Mutation: no clamp.
    func testTheRangeEndsClampToTheFrame() {
        let vp = SpectrumViewport(domain: 0...10)
        let r = SpectrumStripLogic.rangeEnergies(startX: 46 + 100, endX: 46 + 900, plotLeft: 46, plotWidth: 400, viewport: vp)
        XCTAssertEqual(r.from, 2.5, accuracy: 1e-9); XCTAssertEqual(r.to, 10, accuracy: 1e-9)
        XCTAssertEqual(SpectrumStripLogic.rangeEnergies(startX: 0, endX: 46 + 200, plotLeft: 46, plotWidth: 400, viewport: vp).from, 0)
    }

    /// The gesture code itself: the ⌥ range drag is the only gesture that passes `optionHeld: true`, and it is gated by
    /// `.modifiers(.option)`; the plain pan passes false, and the ⌘ zoom box is the one gesture gated by `.modifiers(.command)`. A source check, because SwiftUI gestures cannot be driven in a unit run.
    /// Mutation: `.modifiers(.option)` removed from the range gesture (⌥-less drags would select a range), red.
    func testTheRangeGestureIsGatedByOption() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("mac4DSTEM/UI/Spectroscopy/SpectrumStripView.swift")
        let src = try String(contentsOf: url, encoding: .utf8)
        XCTAssertEqual(src.components(separatedBy: "optionHeld: true").count - 1, 1)
        XCTAssertEqual(src.components(separatedBy: "optionHeld: false").count - 1, 2, "the plain pan and the ⌘ zoom box")
        let r = try XCTUnwrap(src.range(of: "drag(v, size, optionHeld: true, commandHeld: false)"))
        XCTAssertTrue(src[r.upperBound...].prefix(160).contains(".modifiers(.option)"))
        let c = try XCTUnwrap(src.range(of: "drag(v, size, optionHeld: false, commandHeld: true)"))
        XCTAssertTrue(src[c.upperBound...].prefix(160).contains(".modifiers(.command)"), "the zoom box is gated by ⌘")
    }
}

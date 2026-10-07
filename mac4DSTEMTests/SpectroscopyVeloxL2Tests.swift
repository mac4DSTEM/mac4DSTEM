import XCTest
import DSTEMCore
@testable import mac4DSTEM

/// Velox sheet, lane L2 (2026-10-07): the inspector's Smooth row (1a), the Found row's net / L_D (2a), the Absorption row (8a)
/// and the Info tab's rows (9a). Pure strings and rules; the views only place them.
@MainActor
final class SpectroscopyVeloxL2Tests: XCTestCase {
    private let en = Locale(identifier: "en_US"), de = Locale(identifier: "de_DE")
    private let Al = 13, Cu = 29, O = 8, Eu = 63, Hf = 72

    private func outcome(_ s: [ElementSuggestion]) -> AutoIDOutcome {
        AutoIDOutcome(region: "r", suggestions: s, suspects: [], notTested: [], notes: [])
    }

    // MARK: 1a Smooth

    /// The menu offers every kernel, named as the tile names it; "None" for the raw map.
    /// Mutation: `none` titled with the empty `label` - red.
    func testSmoothingTitlesNameEveryKernel() {
        XCTAssertEqual(MapSmoothing.allCases.map(ElementsSection.smoothingTitle),
                       ["None", "3 \u{00D7} 3", "5 \u{00D7} 5", "\u{03C3} 1 px", "\u{03C3} 2 px"])
    }

    /// The help says it is display only and what stays raw.
    /// Mutation: the help drops "untouched" - red.
    func testSmoothingHelpSaysDisplayOnly() {
        XCTAssertTrue(ElementsSection.smoothingHelp.contains("displayed maps only"))
        XCTAssertTrue(ElementsSection.smoothingHelp.contains("untouched"))
    }

    // MARK: 2a Found

    /// Strongest first as the proposer gave them; one decimal below 10, none above; 0 (unknown) is the symbol alone.
    /// Mutation: the decimal rule inverted (one decimal at 10 and above) - red; `significance > 0` dropped - red.
    func testFoundTextShowsNetOverLDInTheSuggestionOrder() {
        let s = [ElementSuggestion(z: Cu, reason: "", significance: 41.4), ElementSuggestion(z: Al, reason: "", significance: 380.2),
                 ElementSuggestion(z: O, reason: "", significance: 12.04), ElementSuggestion(z: Eu, reason: "", significance: 1.14),
                 ElementSuggestion(z: Hf, reason: "", significance: 0.2)]
        XCTAssertEqual(ElementsSection.foundText(outcome(s), locale: en), "Cu 41, Al 380, O 12, Eu 1.1, Hf 0.2")
        XCTAssertEqual(ElementsSection.foundText(outcome(s), locale: de), "Cu 41, Al 380, O 12, Eu 1,1, Hf 0,2")
        XCTAssertEqual(ElementsSection.foundText(outcome([ElementSuggestion(z: Al, reason: "")]), locale: en), "Al")
        XCTAssertEqual(ElementsSection.foundText(outcome([]), locale: en), "none")
    }

    /// 9.96 would print "10.0" with a decimal: it is rounded first, then the rule is chosen.
    /// Mutation: the rule reads the unrounded value - red.
    func testFoundTextRoundsBeforeChoosingDecimals() {
        XCTAssertEqual(ElementsSection.foundText(outcome([ElementSuggestion(z: Al, reason: "", significance: 9.96)]), locale: en), "Al 10")
        XCTAssertEqual(ElementsSection.foundText(outcome([ElementSuggestion(z: Al, reason: "", significance: 9.94)]), locale: en), "Al 9.9")
    }

    /// A pick that was applied as Fit only (a line without a computed k) says so, next to its number or alone.
    /// Mutation: the suffix keyed on `.quantify` - red.
    func testFoundTextMarksFitOnlyPicks() {
        let s = [ElementSuggestion(z: Cu, reason: "", proposedRole: .fitOnly, significance: 3.2),
                 ElementSuggestion(z: Hf, reason: "", proposedRole: .fitOnly),
                 ElementSuggestion(z: Al, reason: "", proposedRole: .quantify, significance: 50)]
        XCTAssertEqual(ElementsSection.foundText(outcome(s), locale: en), "Cu 3.2 (fit only), Hf (fit only), Al 50")
    }

    /// The hover gets one first line defining the number, in the person's decimal separator, before today's reasons.
    /// Mutation: the line appended after the reasons - red.
    func testFoundHelpStartsWithTheCurrieLine() {
        XCTAssertEqual(ElementsSection.significanceLine(locale: en), "net / L_D: 1 = just detectable (Currie, \u{03B1} = \u{03B2} = 0.05)")
        XCTAssertEqual(ElementsSection.significanceLine(locale: de), "net / L_D: 1 = just detectable (Currie, \u{03B1} = \u{03B2} = 0,05)")
        let o = outcome([ElementSuggestion(z: Al, reason: "net 900 counts", significance: 3)])
        let help = ElementsSection.foundHover(o, locale: en)
        XCTAssertTrue(help.hasPrefix("net / L_D: 1 = just detectable"))
        XCTAssertTrue(help.contains(ElementsSection.foundHelp))
        XCTAssertTrue(help.contains("Al: net 900 counts"))
    }

    // MARK: 8a Absorption

    /// The box is off while no thickness is typed, and typing one turns it on; the stored value is never written by this rule.
    /// Mutation: enabled when the thickness is zero-or-nil check removed (always enabled) - red.
    func testAbsorptionNeedsAThickness() {
        var q = QuantifySettings()
        XCTAssertFalse(QuantificationSection.absorptionEnabled(q))
        q.thickness = 80
        XCTAssertTrue(QuantificationSection.absorptionEnabled(q))
        XCTAssertEqual(QuantificationSection.absorptionHelp, "Needs a thickness; the box follows it.")
    }

    /// Without a thickness the box shows unticked (the fit does refuse absorption then) while the stored provenance key stays true;
    /// with one it shows the stored choice.
    /// Mutation: the shown value is `absorption` alone - red.
    func testAbsorptionBoxFollowsTheThicknessWithoutWritingTheKey() {
        var q = QuantifySettings()
        q.absorption = true
        XCTAssertFalse(QuantificationSection.absorptionShown(q))
        XCTAssertTrue(q.absorption)
        q.thickness = 50
        XCTAssertTrue(QuantificationSection.absorptionShown(q))
        q.absorption = false
        XCTAssertFalse(QuantificationSection.absorptionShown(q))
    }

    /// The "Off: no thickness typed." note is gone for the refusal text; another refusal and an applied note stay.
    /// Mutation: the thickness refusal mapped back to the old note - red.
    func testNoThicknessNoteIsGone() {
        XCTAssertNil(QuantifyPresentation.absorptionNoteText("not applied: no thickness is typed (nm): type one in the Quantify inspector"))
        XCTAssertEqual(QuantifyPresentation.absorptionNoteText("not applied: the mass-absorption table is not available"),
                       "Off: the mass-absorption table is not available")
        XCTAssertEqual(QuantifyPresentation.absorptionNoteText("4 detectors \u{00B7} TOA from file"), "4 detectors \u{00B7} TOA from file")
    }

    // MARK: 9a Info

    private func meta() -> SpectrumImageMetadata {
        SpectrumImageMetadata(fileName: "a.emd", filePath: "", scanWidth: 4, scanHeight: 4, channelCount: 4096,
                              energyOffsetEV: -1932, energyDispersionEV: 5)
    }

    /// "5 eV/ch" and "−1 932 eV": the file's own numbers, a true minus, a narrow no-break space for the thousands.
    /// Mutation: the minus written as a hyphen - red; grouping removed - red.
    func testDispersionAndOffset() {
        var m = meta(); m.energyDispersionEV = 20
        XCTAssertEqual(SpectroscopyPlaceholderFormat.dispersion(m, locale: en), "20 eV/ch")
        XCTAssertEqual(SpectroscopyPlaceholderFormat.offset(m, locale: en), "\u{2212}1\u{202F}932 eV")
        m.energyDispersionEV = 2.5; m.energyOffsetEV = 12.25
        XCTAssertEqual(SpectroscopyPlaceholderFormat.dispersion(m, locale: de), "2,5 eV/ch")
        XCTAssertEqual(SpectroscopyPlaceholderFormat.offset(m, locale: de), "12,25 eV")
    }

    /// Stage only when a tilt is in the file; a lone tilt is shown alone.
    /// Mutation: `||` turned into `&&` - red.
    func testStageNeedsATilt() {
        var m = meta()
        XCTAssertNil(SpectroscopyPlaceholderFormat.stage(m, locale: en))
        m.alphaTiltDegrees = 7.3; m.betaTiltDegrees = 0
        XCTAssertEqual(SpectroscopyPlaceholderFormat.stage(m, locale: en), "\u{03B1} 7.3\u{00B0} \u{00B7} \u{03B2} 0.0\u{00B0}")
        XCTAssertEqual(SpectroscopyPlaceholderFormat.stage(m, locale: de), "\u{03B1} 7,3\u{00B0} \u{00B7} \u{03B2} 0,0\u{00B0}")
        m.betaTiltDegrees = nil
        XCTAssertEqual(SpectroscopyPlaceholderFormat.stage(m, locale: en), "\u{03B1} 7.3\u{00B0}")
    }

    /// Live time only where a detector carries it; real time follows when it is there; segments that differ show a range.
    /// Mutation: a "not read" string for the none case - red; the range collapsed to the first value - red.
    func testLiveTimeOnlyWhenTheFileHasIt() {
        var m = meta()
        m.detectors = [SpectrumDetectorSegment(name: "SuperXG11")]
        XCTAssertNil(SpectroscopyPlaceholderFormat.liveTime(m, locale: en))
        m.detectors = [SpectrumDetectorSegment(name: "A", liveTime: 4187.7, realTime: 1423.1)]
        XCTAssertEqual(SpectroscopyPlaceholderFormat.liveTime(m, locale: de), "4\u{202F}187,7 s \u{00B7} real 1\u{202F}423,1 s")
        m.detectors = [SpectrumDetectorSegment(name: "A", liveTime: 100), SpectrumDetectorSegment(name: "B", liveTime: 100)]
        XCTAssertEqual(SpectroscopyPlaceholderFormat.liveTime(m, locale: en), "100.0 s")
        m.detectors = [SpectrumDetectorSegment(name: "A", liveTime: 100), SpectrumDetectorSegment(name: "B", liveTime: 120.5)]
        XCTAssertEqual(SpectroscopyPlaceholderFormat.liveTime(m, locale: en), "100.0\u{2013}120.5 s")
    }
}

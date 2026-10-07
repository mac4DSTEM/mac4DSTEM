import AppKit
import SwiftUI
import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

/// Lane L11 (the owner's drive findings, build 2): the room's choices as Liquid Glass chips (`GlassChipGroup`). The look itself (quiet
/// at rest, alive under the pointer, the tint when on) is the system's and cannot be asserted in a hosted layout; the supervisor
/// drives it. Here: the selection logic, the bindings through the group, the chips' definitions, the wrapping and the width.
@MainActor
final class SpectroscopyDriveL11Tests: XCTestCase {

    // MARK: Selection logic

    /// A picker keeps exactly one chip on; a tap on the one that is on keeps it (no empty state).
    /// Mutation: `.single` toggles like `.multi` (tap on the chip that is on empties the set) - red.
    func testSingleChipsKeepOneOnAndNeverEmpty() {
        XCTAssertEqual(GlassChipSelection.tapped("b", on: ["a"], mode: .single), ["b"])
        XCTAssertEqual(GlassChipSelection.tapped("a", on: ["a"], mode: .single), ["a"], "tapping the chip that is on keeps it on")
        XCTAssertEqual(GlassChipSelection.tapped("a", on: [], mode: .single), ["a"])
    }

    /// Toggles flip only the tapped chip.
    /// Mutation: `.multi` replaces the set with the tapped chip alone - red.
    func testMultiChipsToggleOnlyTheTappedOne() {
        XCTAssertEqual(GlassChipSelection.tapped("b", on: ["a"], mode: .multi), ["a", "b"])
        XCTAssertEqual(GlassChipSelection.tapped("a", on: ["a", "b"], mode: .multi), ["b"])
        XCTAssertEqual(GlassChipSelection.tapped("a", on: ["a"], mode: .multi), [])
    }

    /// A disabled chip changes nothing in either mode.
    /// Mutation: the `guard enabled` line removed from `GlassChipSelection.tapped` - red.
    func testADisabledChipDoesNothing() {
        XCTAssertEqual(GlassChipSelection.tapped("b", on: ["a"], mode: .single, enabled: false), ["a"])
        XCTAssertEqual(GlassChipSelection.tapped("b", on: ["a"], mode: .multi, enabled: false), ["a"])
        XCTAssertEqual(GlassChipSelection.tapped("a", on: ["a"], mode: .multi, enabled: false), ["a"])
    }

    // MARK: The inspector's bindings, through the group

    private func group<ID: Hashable>(_ chips: [GlassChip<ID>], _ mode: GlassChipMode, _ selection: Binding<Set<ID>>) -> GlassChipGroup<ID> {
        GlassChipGroup(chips: chips, mode: mode, selection: selection)
    }

    /// int / net: a tap on a chip writes `mapMode`; the model's value is the chip that is on; only the two per-pixel modes are chips.
    /// Mutation: `mapChips` offers every `MapMode` (wt% and at% are not per-pixel maps) or `mapSelection` writes `.integrated` always - red.
    func testMapsChipsAreIntAndNetAndWriteTheMode() {
        let m = SpectroscopyRoomModel.fixture
        XCTAssertEqual(ElementsSection.mapChips.map(\.title), ["int", "net"])
        m.mapMode = .netCounts
        let g = group(ElementsSection.mapChips, .single, ElementsSection.mapSelection(m))
        XCTAssertEqual(ElementsSection.mapSelection(m).wrappedValue, [.netCounts])
        g.tap(.integrated)
        XCTAssertEqual(m.mapMode, .integrated)
        g.tap(.integrated)
        XCTAssertEqual(m.mapMode, .integrated, "a picker does not turn off")
        g.tap(.netCounts)
        XCTAssertEqual(m.mapMode, .netCounts)
    }

    /// Region tool: a tap on a symbol chip writes `drawTool`; each chip is its tool's symbol and is named for VoiceOver.
    /// Mutation: `toolSelection` ignores the tap (writes `.rectangle`) or a chip carries another tool's symbol - red.
    func testRegionToolChipsWriteTheToolAndCarryTheirSymbol() {
        let m = SpectroscopyRoomModel.fixture
        m.drawTool = .rectangle
        let chips = RegionSection.toolChips
        XCTAssertEqual(chips.map(\.id), DrawTool.allCases)
        XCTAssertEqual(chips.map { $0.symbol ?? "" }, DrawTool.allCases.map(\.symbol))
        XCTAssertTrue(chips.allSatisfy { !$0.showsTitle && !$0.title.isEmpty }, "a symbol chip is named for VoiceOver")
        let g = group(chips, .single, RegionSection.toolSelection(m))
        g.tap(.polygon); XCTAssertEqual(m.drawTool, .polygon)
        g.tap(.ellipse); XCTAssertEqual(m.drawTool, .ellipse)
        g.tap(.rectangle); XCTAssertEqual(m.drawTool, .rectangle)
    }

    /// Each curve chip flips its own layer and no other; the chip is tinted and dotted in the curve's own colour.
    /// Mutation: two key paths swapped in `CurveLayer.keyPath`, or `curveSelection` writes only the tapped layer's neighbour - red.
    func testEachCurveChipFlipsItsOwnLayerOnly() {
        let m = SpectroscopyRoomModel.fixture
        for layer in CurveLayer.allCases {
            m.layers = SpectrumLayers()
            let before = CurveLayer.allCases.map { m.layers[keyPath: $0.keyPath] }
            let g = group(SpectrumLayersSection.curveChips, .multi, SpectrumLayersSection.curveSelection(m))
            g.tap(layer)
            for (i, other) in CurveLayer.allCases.enumerated() {
                XCTAssertEqual(m.layers[keyPath: other.keyPath], other == layer ? !before[i] : before[i], "\(layer.title) flips \(other.title)?")
            }
            g.tap(layer)
            XCTAssertEqual(CurveLayer.allCases.map { m.layers[keyPath: $0.keyPath] }, before, "a second tap restores")
        }
        for chip in SpectrumLayersSection.curveChips {
            XCTAssertEqual(chip.tint, chip.id.color)
            XCTAssertEqual(chip.symbolColor, chip.id.color)
            XCTAssertEqual(chip.accessibilityID, "spectroscopy.layers." + chip.id.title.lowercased(), "the id the toggles had")
        }
        XCTAssertEqual(SpectrumLayersSection.curveChips.map(\.title), ["Spectrum", "Background", "Model", "Residual", "Pins"])
    }

    /// Linear / Log: the chip pair is the log flag, one on at a time.
    /// Mutation: `scaleSelection` writes `isLog` inverted - red.
    func testScaleChipsAreTheLogFlag() {
        let m = SpectroscopyRoomModel.fixture
        m.layers.log = false
        let g = group(SpectrumLayersSection.scaleChips, .single, SpectrumLayersSection.scaleSelection(m))
        XCTAssertEqual(SpectrumLayersSection.scaleSelection(m).wrappedValue, [.linear])
        g.tap(.log); XCTAssertTrue(m.layers.log)
        XCTAssertEqual(SpectrumLayersSection.scaleSelection(m).wrappedValue, [.log])
        g.tap(.linear); XCTAssertFalse(m.layers.log)
        g.tap(.linear); XCTAssertFalse(m.layers.log)
    }

    /// Per pixel and Windows: two toggles in one group; each is disabled until it has its data and then a tap does nothing.
    /// Mutation: `GlassChipGroup.tap` passes `enabled: true` whatever the chip says, or `overlaySelection` swaps the two flags - red.
    func testOverlayChipsToggleTheirFlagsAndStayDeadWithoutData() {
        let m = SpectroscopyRoomModel.fixture
        m.layers.perPixel = false; m.layers.windows = false
        m.spectrumPixels = 0; m.windowBands = []
        var chips = SpectrumLayersSection.overlayChips(m)
        XCTAssertEqual(chips.map(\.title), ["Per pixel", "Windows"])
        XCTAssertEqual(chips.map(\.enabled), [false, false])
        var g = group(chips, .multi, SpectrumLayersSection.overlaySelection(m))
        g.tap(.perPixel); g.tap(.windows)
        XCTAssertFalse(m.layers.perPixel); XCTAssertFalse(m.layers.windows)

        m.spectrumPixels = 1200
        chips = SpectrumLayersSection.overlayChips(m)
        XCTAssertEqual(chips.map(\.enabled), [true, false], "only Per pixel has data")
        g = group(chips, .multi, SpectrumLayersSection.overlaySelection(m))
        g.tap(.perPixel); g.tap(.windows)
        XCTAssertTrue(m.layers.perPixel); XCTAssertFalse(m.layers.windows)

        m.windowBands = [WindowBand(id: "Al_Ka.signal", elementZ: 13, label: "Al K\u{03B1}", range: 1.4...1.57, kind: .signal)]
        g = group(SpectrumLayersSection.overlayChips(m), .multi, SpectrumLayersSection.overlaySelection(m))
        g.tap(.windows)
        XCTAssertTrue(m.layers.perPixel); XCTAssertTrue(m.layers.windows, "the two are independent")
        g.tap(.perPixel)
        XCTAssertFalse(m.layers.perPixel); XCTAssertTrue(m.layers.windows)
    }

    // MARK: Wrapping and width

    /// Chips wrap to a new row when the next would pass the width; a zero width stacks them, so the row's minimum width is its widest chip.
    /// Mutation: `arrange` never wraps (the `x + s.width > maxWidth` test removed) - red.
    func testChipFlowWrapsAndItsMinimumIsTheWidestChip() {
        let sizes = [CGSize(width: 80, height: 24), CGSize(width: 100, height: 24), CGSize(width: 70, height: 24)]
        let wide = GlassChipFlow.arrange(sizes: sizes, maxWidth: 1000, spacing: 8, lineSpacing: 6)
        XCTAssertEqual(wide.origins, [CGPoint(x: 0, y: 0), CGPoint(x: 88, y: 0), CGPoint(x: 196, y: 0)])
        XCTAssertEqual(wide.size, CGSize(width: 266, height: 24))
        let narrow = GlassChipFlow.arrange(sizes: sizes, maxWidth: 200, spacing: 8, lineSpacing: 6)
        XCTAssertEqual(narrow.origins, [CGPoint(x: 0, y: 0), CGPoint(x: 88, y: 0), CGPoint(x: 0, y: 30)], "the third wraps")
        XCTAssertEqual(narrow.size, CGSize(width: 188, height: 54))
        let stacked = GlassChipFlow.arrange(sizes: sizes, maxWidth: 0, spacing: 8, lineSpacing: 6)
        XCTAssertEqual(stacked.size.width, 100, "the widest chip is the minimum width")
        XCTAssertEqual(stacked.origins.map(\.y), [0, 30, 60])
        XCTAssertEqual(GlassChipFlow.arrange(sizes: [], maxWidth: 100, spacing: 8, lineSpacing: 6).size, .zero)
    }

    /// The Spectroscopy sections that now hold chips fit the narrowest inspector column (280 pt less 2 x 16 pt of padding), laid out
    /// with the glass modifiers hosted.
    /// Mutation: a chip's horizontal padding raised from 10 to 60 pt, or the flow layout replaced by an HStack - red.
    func testTheChipSectionsFitTheNarrowestColumn() {
        let budget = LayoutPolicy.inspectorWidth.min - 2 * 16
        let m = SpectroscopyRoomModel.fixture
        m.spectrumPixels = 1200
        func minimum<V: View>(_ view: V) -> CGFloat {
            NSHostingController(rootView: InspectorGroup { view }).sizeThatFits(in: CGSize(width: 1, height: 10_000)).width
        }
        for (name, w) in [("Elements", minimum(ElementsSection(model: m))), ("Region", minimum(RegionSection(model: m))),
                          ("Spectrum", minimum(SpectrumLayersSection(model: m)))] {
            XCTAssertGreaterThan(w, 10, "\(name): the probe measured nothing")
            XCTAssertLessThanOrEqual(w, budget, "\(name) needs \(w) pt of \(budget)")
        }
    }
}

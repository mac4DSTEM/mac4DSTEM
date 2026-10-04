//
//  FinalPolishR2Tests.swift
//  Slot 4⅞ lane R2 (2026-10-04, owner card Q3 a): the SCAN navigator moves from the result pane
//  into the diffraction pane's top-trailing corner. The rule is a pure predicate; where the view
//  is drawn is pinned by reading the source (the structure the drive then looks at). Each test
//  names the mutation it catches.
//

import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

@MainActor
final class FinalPolishR2Tests: XCTestCase {

    // MARK: - The rule

    /// A new `ProductDomain` case stops this switch compiling until its navigator rule is decided here.
    private func expectedShown(_ domain: ProductDomain) -> Bool {
        switch domain {
        case .scan: false                       // the result is itself clickable: it picks the scan position
        case .detector, .reconstruction: true   // a Bragg-vector map / parallax / single-slice phase is not
        }
    }

    /// Mutation it catches: the comparison flipped (`==` for `!=`) or the domains swapped, so the
    /// navigator shows over a clickable scan map and is missing beside a Bragg-vector map.
    func testTheNavigatorIsShownForDetectorAndReconstructionAndHiddenForScan() {
        XCTAssertTrue(ScanNavigatorPlacement.isShown(domain: .detector, hasImage: true), "Bragg-vector map")
        XCTAssertTrue(ScanNavigatorPlacement.isShown(domain: .reconstruction, hasImage: true), "parallax / single-slice")
        XCTAssertFalse(ScanNavigatorPlacement.isShown(domain: .scan, hasImage: true), "a scan map scrubs by itself")
        for domain in [ProductDomain.scan, .detector, .reconstruction] {
            XCTAssertEqual(ScanNavigatorPlacement.isShown(domain: domain, hasImage: true), expectedShown(domain),
                           "\(domain)")
        }
    }

    /// Mutation it catches: the `hasImage` guard dropped (an empty navigator drawn for a detector product
    /// before the scan image exists), or a nil domain read as "not scan" (the old `!= .scan` on an optional,
    /// which shows the inset beside a pattern with no result at all).
    func testNoImageOrNoProductShowsNoNavigator() {
        for domain in [ProductDomain.scan, .detector, .reconstruction] {
            XCTAssertFalse(ScanNavigatorPlacement.isShown(domain: domain, hasImage: false), "\(domain), no image")
        }
        XCTAssertFalse(ScanNavigatorPlacement.isShown(domain: nil, hasImage: true), "no displayed product")
        XCTAssertFalse(ScanNavigatorPlacement.isShown(domain: nil, hasImage: false))
    }

    /// The pane evaluates the rule on `appState.displayedProduct?.domain` and `scanNavigationImage != nil`;
    /// this runs those two reads on a real `AppState` for each domain. Mutation it catches: a product
    /// publication that stops carrying its domain (the rule would then be fed `.scan` for everything).
    func testTheRuleReadsTheDisplayedProductsDomainFromAppState() throws {
        let state = AppState()
        func shown() -> Bool {
            ScanNavigatorPlacement.isShown(domain: state.displayedProduct?.domain,
                                           hasImage: state.scanNavigationImage != nil)
        }
        XCTAssertFalse(shown(), "no product, no navigation image")

        state.scanNavigationImage = FloatImage(width: 4, height: 3, pixels: [Float](repeating: 1, count: 12))
        XCTAssertNil(state.displayedProduct)
        XCTAssertFalse(shown(), "an image but no displayed product")

        for domain in [ProductDomain.scan, .detector, .reconstruction] {
            state.publishProduct(
                kind: "r2_probe", displayName: "R2 probe", valueUnits: "intensity",
                payload: .scalar(FloatImage(width: 8, height: 8, pixels: [Float](repeating: 1, count: 64))),
                domain: domain)
            XCTAssertEqual(state.displayedProduct?.domain, domain)
            XCTAssertEqual(shown(), expectedShown(domain), "\(domain) product on screen")
        }

        state.scanNavigationImage = nil
        XCTAssertFalse(shown(), "a reconstruction on screen but no scan image to navigate by")
    }

    // MARK: - Where the view is drawn (read from the source: the pane is a view)

    private func uiSources() throws -> [(name: String, text: String)] {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let ui = root.appendingPathComponent("mac4DSTEM/UI")
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: ui.path) else {
            throw XCTSkip("source tree not beside the tests: \(ui.path)")
        }
        let swift = names.filter { $0.hasSuffix(".swift") }.sorted()
        return try swift.map { ($0, try String(contentsOf: ui.appendingPathComponent($0), encoding: .utf8)) }
    }

    private func occurrences(of needle: String, in text: String) -> Int {
        text.components(separatedBy: needle).count - 1
    }

    /// The text from `start` up to (not including) the next of `ends` that follows it; fails the test when a marker is missing.
    private func segment(_ text: String, from start: String, to ends: [String]) throws -> String {
        let begin = try XCTUnwrap(text.range(of: start), "marker missing: \(start)")
        let tail = text[begin.lowerBound...]
        let stops = ends.compactMap { tail.dropFirst(start.count).range(of: $0)?.lowerBound }
        return String(tail[..<(stops.min() ?? tail.endIndex)])
    }

    /// Mutation it catches: the navigator drawn again by the result pane (a second copy of the view
    /// or of the rule there), or dropped from the diffraction pane.
    func testOnlyTheDiffractionPaneDrawsTheNavigator() throws {
        let panes = try XCTUnwrap(try uiSources().first { $0.name == "ImagePanes.swift" }, "ImagePanes.swift").text
        let diffraction = try segment(panes, from: "struct DiffractionPane: View {", to: ["struct ScanNavigatorInset: View {"])
        let realSpace = try segment(panes, from: "struct RealSpacePane: View {", to: [])   // to the end of the file

        XCTAssertEqual(occurrences(of: "ScanNavigatorInset(image:", in: diffraction), 1, "drawn once in the diffraction pane")
        XCTAssertEqual(occurrences(of: "ScanNavigatorPlacement.isShown(", in: diffraction), 1, "under the one rule")
        XCTAssertFalse(realSpace.contains("ScanNavigator"), "the result pane draws no navigator and asks no rule")
        XCTAssertFalse(realSpace.contains("scanNavigationImage"), "nor reads the navigation image")
    }

    /// The navigator must sit OUTSIDE the diffraction pane's zoom/pan/clip layer: it is a ZStack sibling
    /// after `.zoomPan(...)`, the layer's last modifier, and it is pinned to the top-trailing corner.
    /// Mutation it catches: the call moved before `.zoomPan` (inside the scaled, clipped ZStack, where it
    /// would be magnified 4x and clipped away when panned) or its alignment changed to another corner.
    func testTheNavigatorSitsOutsideTheZoomLayerAtTheTopTrailingCorner() throws {
        let panes = try XCTUnwrap(try uiSources().first { $0.name == "ImagePanes.swift" }, "ImagePanes.swift").text
        let diffraction = try segment(panes, from: "struct DiffractionPane: View {", to: ["struct ScanNavigatorInset: View {"])

        let zoom = try XCTUnwrap(diffraction.range(of: ".zoomPan($zp, box: box)"), ".zoomPan marker")
        let call = try XCTUnwrap(diffraction.range(of: "ScanNavigatorInset(image:"), "the navigator call")
        XCTAssertGreaterThan(call.lowerBound, zoom.upperBound, "drawn after, so outside, the zoomed and clipped layer")

        let placement = try segment(diffraction, from: "ScanNavigatorInset(image:", to: ["PaneFooter {"])
        XCTAssertTrue(placement.contains("alignment: .topTrailing"), "pinned to the pane's top-trailing corner")
        XCTAssertFalse(placement.contains("scaleEffect"), "unscaled")
    }

    /// One view carries the navigator's accessibility identifier, declared once in the UI sources.
    /// Mutation it catches: a second copy of the view (or of the identifier) anywhere in UI/.
    func testTheNavigatorsAccessibilityIdentifierIsDeclaredOnce() throws {
        let sources = try uiSources()
        let declared = sources.reduce(0) { $0 + occurrences(of: "\"result.scanNavigator\"", in: $1.text) }
        XCTAssertEqual(declared, 1, "result.scanNavigator in UI/: \(sources.filter { $0.text.contains("result.scanNavigator") }.map(\.name))")
        let structs = sources.reduce(0) { $0 + occurrences(of: "struct ScanNavigatorInset", in: $1.text) }
        XCTAssertEqual(structs, 1, "one navigator view")
    }
}

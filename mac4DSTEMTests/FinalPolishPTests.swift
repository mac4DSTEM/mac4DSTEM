//
//  FinalPolishPTests.swift
//  Slot 4⅞ lane P (2026-10-04, found by the polish drive, shot 48-detect-after): the SCAN
//  navigator was 118 pt WIDE and 118 * ry / rx tall, so a 17 x 77 scan drew 118 x 534 pt and
//  covered ~30 % of the diffraction pattern beside it. It now keeps the scan's aspect ratio inside
//  a 118 x 118 box (the LONGER side is 118), neither side below the width of its "SCAN" label
//  (29 pt, measured below; the fix round's refuter found the first floor, 24 pt, wrapped the label
//  to "SCA" / "N" on the drive's own 17 x 77 scan). The size and the drag-to-scan-position mapping
//  are pure statics on `ScanNavigatorPlacement`; the view is pinned by reading its source. Each
//  test names the mutation it catches.
//

import AppKit
import DSTEMCore
import SwiftUI
import XCTest
@testable import mac4DSTEM

@MainActor
final class FinalPolishPTests: XCTestCase {

    private let accuracy: CGFloat = 1e-9

    // MARK: - The size

    /// A square scan is unchanged: the full 118 x 118 box, as before the fix.
    /// Mutation it catches: the box shrunk or grown for every scan (a margin taken off the longer side,
    /// a different constant), which would change the square scans that were never a problem.
    func testASquareScanIsTheWholeBox() {
        let box = ScanNavigatorPlacement.maxSide
        XCTAssertEqual(box, 118, "the box the owner has been looking at")
        for n in [1, 17, 100, 480] {
            let size = ScanNavigatorPlacement.size(rx: n, ry: n)
            XCTAssertEqual(size.width, 118, accuracy: accuracy, "\(n) x \(n) width")
            XCTAssertEqual(size.height, 118, accuracy: accuracy, "\(n) x \(n) height")
        }
        let explicit = ScanNavigatorPlacement.size(rx: 100, ry: 100, maxSide: 80)
        XCTAssertEqual(explicit.width, 80, accuracy: accuracy, "the box is a parameter of the rule")
        XCTAssertEqual(explicit.height, 80, accuracy: accuracy)
    }

    /// The drive's scan: 17 x 77 would be (118 * 17 / 77) = 26 pt wide at its true aspect ratio, which is
    /// below the "SCAN" label (29 pt), so it is floored: 29 x 118 pt, not 118 x 534. The sweep pins the
    /// rule for any shape whose short side clears the floor (`minSide`; strips are the next test): the
    /// longer side is 118 and the aspect ratio is the scan's.
    /// Mutation it catches: the old width-fixed rule (`width = 118`, `height = 118 * ry / rx`), which
    /// gives 118 x 534 here, and the opposite fit (the SHORTER side set to 118).
    func testATallScanFitsItsLongerSideInTheBox() {
        let tall = ScanNavigatorPlacement.size(rx: 17, ry: 77)
        XCTAssertEqual(tall.width, 29, accuracy: accuracy, "the drive's Si-SiGe scan, width (the label's)")
        XCTAssertEqual(tall.height, 118, accuracy: accuracy, "the drive's Si-SiGe scan, height (was 534)")

        for (rx, ry) in [(8, 30), (101, 101), (84, 100), (64, 128), (2, 3)] {
            let size = ScanNavigatorPlacement.size(rx: rx, ry: ry)
            XCTAssertEqual(max(size.width, size.height), 118, accuracy: accuracy, "\(rx) x \(ry): the longer side")
            XCTAssertLessThanOrEqual(size.width, 118 + accuracy, "\(rx) x \(ry) fits the box (width)")
            XCTAssertLessThanOrEqual(size.height, 118 + accuracy, "\(rx) x \(ry) fits the box (height)")
            XCTAssertEqual(size.width / size.height, CGFloat(rx) / CGFloat(ry), accuracy: 1e-9,
                           "\(rx) x \(ry): the scan's aspect ratio")
        }
    }

    /// A wide scan keeps the old width: 77 x 17 gives 118 x 29 (its height floored, as the tall scan's width is),
    /// 30 x 8 gives 118 x (118 * 8 / 30), above the floor.
    /// Mutation it catches: the fit applied to the tall case only, or the longer side taken from the wrong
    /// axis (the SHORTER side set to 118 draws a wide scan 534 pt wide, past the pane).
    func testAWideScanKeepsItsWidth() {
        let wide = ScanNavigatorPlacement.size(rx: 77, ry: 17)
        XCTAssertEqual(wide.width, 118, accuracy: accuracy)
        XCTAssertEqual(wide.height, 29, accuracy: accuracy)
        let clear = ScanNavigatorPlacement.size(rx: 30, ry: 8)
        XCTAssertEqual(clear.width, 118, accuracy: accuracy, "a wide scan above the floor, width")
        XCTAssertEqual(clear.height, 118.0 * 8.0 / 30.0, accuracy: accuracy, "a wide scan above the floor, its true height")
        let transposed = ScanNavigatorPlacement.size(rx: 17, ry: 77)
        XCTAssertEqual(wide.width, transposed.height, accuracy: accuracy, "a scan and its transpose are mirror boxes")
        XCTAssertEqual(wide.height, transposed.width, accuracy: accuracy)
    }

    /// A line scan (1 x 1000 or 1000 x 1) is not drawn as a hairline: neither side goes below `minSide`
    /// (29 pt: the width of the "SCAN" label, so the label stays on one line; the 9-pt marker fits and a drag
    /// has something to land on). The drive's 17 x 77 scan (26 pt at its true aspect ratio) is floored by it.
    /// A size below 1 is read as 1.
    /// Mutation it catches: the floor removed (width 0.118 pt: nothing to grab), or lowered below the label
    /// (the first fix's 24 pt).
    func testAStripKeepsAHitSize() {
        let minimum = ScanNavigatorPlacement.minSide
        XCTAssertEqual(minimum, 29)
        let column = ScanNavigatorPlacement.size(rx: 1, ry: 1000)
        XCTAssertEqual(column.width, minimum, accuracy: accuracy, "1 x 1000 width")
        XCTAssertEqual(column.height, 118, accuracy: accuracy, "1 x 1000 height")
        let row = ScanNavigatorPlacement.size(rx: 1000, ry: 1)
        XCTAssertEqual(row.width, 118, accuracy: accuracy, "1000 x 1 width")
        XCTAssertEqual(row.height, minimum, accuracy: accuracy, "1000 x 1 height")

        let drive = ScanNavigatorPlacement.size(rx: 17, ry: 77)
        XCTAssertEqual(drive.width, minimum, accuracy: accuracy, "the drive's 17 x 77 scan sits on the floor")
        for (rx, ry) in [(0, 0), (-3, 5), (0, 77)] {
            let size = ScanNavigatorPlacement.size(rx: rx, ry: ry)
            XCTAssertTrue(size.width.isFinite && size.height.isFinite, "\(rx) x \(ry) is finite")
            XCTAssertGreaterThanOrEqual(min(size.width, size.height), minimum, "\(rx) x \(ry) keeps the floor")
            XCTAssertLessThanOrEqual(max(size.width, size.height), 118 + accuracy, "\(rx) x \(ry) fits the box")
        }
    }

    // MARK: - The drag mapping

    /// The whole inset maps to the whole scan, whatever its shape: the corners reach the first and the last
    /// pixel, the centre of every scan pixel's marker maps back to that pixel, and a drag past an edge stays
    /// on the edge pixel. Run on the drive's tall scan and on a line scan (stretched to its floor).
    /// Mutation it catches: the mapping reading the old fixed 118-pt width (a tall inset 29 pt wide would then
    /// reach x = 4 of 17 at its right edge), the height assumed square, the scrub index rounded instead of
    /// floored, and the empty-scan guard dropped (an empty scan would read -1).
    func testTheWholeInsetMapsToTheWholeScan() {
        let none = ScanNavigatorPlacement.scanPosition(at: CGPoint(x: 5, y: 5), in: CGSize(width: 118, height: 118), rx: 0, ry: 0)
        XCTAssertEqual(none.x, 0, "an empty scan: x stays 0, never -1")
        XCTAssertEqual(none.y, 0, "an empty scan: y stays 0, never -1")
        for (rx, ry) in [(17, 77), (77, 17), (100, 100), (1, 1000)] {
            let size = ScanNavigatorPlacement.size(rx: rx, ry: ry)
            func at(_ p: CGPoint) -> (x: Int, y: Int) {
                ScanNavigatorPlacement.scanPosition(at: p, in: size, rx: rx, ry: ry)
            }
            let origin = at(CGPoint(x: 0, y: 0))
            XCTAssertEqual(origin.x, 0, "\(rx) x \(ry): top-left x")
            XCTAssertEqual(origin.y, 0, "\(rx) x \(ry): top-left y")
            let inside = at(CGPoint(x: size.width - 0.001, y: size.height - 0.001))
            XCTAssertEqual(inside.x, rx - 1, "\(rx) x \(ry): bottom-right x, just inside")
            XCTAssertEqual(inside.y, ry - 1, "\(rx) x \(ry): bottom-right y, just inside")
            let edge = at(CGPoint(x: size.width, y: size.height))
            XCTAssertEqual(edge.x, rx - 1, "\(rx) x \(ry): bottom-right x, on the edge")
            XCTAssertEqual(edge.y, ry - 1, "\(rx) x \(ry): bottom-right y, on the edge")
            let past = at(CGPoint(x: -40, y: size.height + 400))
            XCTAssertEqual(past.x, 0, "\(rx) x \(ry): a drag left of the inset")
            XCTAssertEqual(past.y, ry - 1, "\(rx) x \(ry): a drag below the inset")

            // The marker is drawn at the centre of its pixel: (x + 0.5) / rx * width. It must read back.
            var misread: [String] = []
            for ix in 0..<min(rx, 120) {
                for iy in Swift.stride(from: 0, to: ry, by: max(ry / 40, 1)) {
                    let centre = CGPoint(x: (CGFloat(ix) + 0.5) / CGFloat(rx) * size.width,
                                         y: (CGFloat(iy) + 0.5) / CGFloat(ry) * size.height)
                    let back = at(centre)
                    if back.x != ix || back.y != iy { misread.append("(\(ix), \(iy)) read as (\(back.x), \(back.y))") }
                }
            }
            XCTAssertTrue(misread.isEmpty, "\(rx) x \(ry): \(misread.count) marker centres misread, first: \(misread.prefix(3))")
        }
    }

    // MARK: - The view uses the rule (read from the source: the inset is a view)

    /// The inset draws at `ScanNavigatorPlacement.size(...)` and scrubs through `scanPosition(...)`; the
    /// fixed-width arithmetic and the 118 literal are gone from it.
    /// Mutation it catches: the view restored to its own `width = 118` / `height = width * ry / rx` (a stale
    /// merge, or a later edit that "simplifies" the size back), which no pure test above can see.
    func testTheInsetViewUsesThePureRule() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let url = root.appendingPathComponent("mac4DSTEM/UI/ImagePanes.swift")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("source tree not beside the tests: \(url.path)")
        }
        let panes = try String(contentsOf: url, encoding: .utf8)
        let begin = try XCTUnwrap(panes.range(of: "struct ScanNavigatorInset: View {"), "the inset view")
        let tail = panes[begin.lowerBound...]
        let end = try XCTUnwrap(tail.range(of: "struct RealSpacePane: View {"), "the next view")
        let view = String(tail[..<end.lowerBound])

        XCTAssertTrue(view.contains("ScanNavigatorPlacement.size(rx: image.width, ry: image.height)"),
                      "the frame comes from the rule")
        XCTAssertTrue(view.contains("ScanNavigatorPlacement.scanPosition(at: value.location, in: size,"),
                      "the scrub reads the same size the frame uses")
        XCTAssertFalse(view.contains("118"), "no size literal in the view")
        XCTAssertFalse(view.contains("static let width"), "no fixed width of its own")
        XCTAssertFalse(view.contains("CGFloat(image.height) / CGFloat(max(image.width"),
                       "no height-from-fixed-width arithmetic")
        let frame = ".frame(width: width, height: height)"
        XCTAssertEqual(view.components(separatedBy: frame).count - 1, 2,
                       "the image and the inset both take the rule's width x height, untransposed")
        XCTAssertTrue(view.contains(".font(.system(size: 9, weight: .bold, design: .monospaced))"),
                      "the label the floor is measured against (testTheFloorHoldsTheScanLabelOnOneLine)")
        XCTAssertTrue(view.contains(".padding(3)"), "the label's padding, which that test measures with it")
    }

    // MARK: - The floor is the label's width

    /// The floor must hold the "SCAN" label on one line: laid out as the inset draws it (9-pt monospaced
    /// bold, `.padding(3)`; testTheInsetViewUsesThePureRule pins that spec in the view), the label is
    /// ~28.25 pt wide, and `minSide` may not be below that. The fix round's refuter measured it (SwiftUI
    /// reports 29 x 17 pt rendered, 22.25 pt of glyphs); the first fix's 24 pt floor wrapped it to "SCA" / "N".
    /// Mutation it catches: `minSide` lowered below the label (24, or the 26 pt a 17 x 77 scan has at its
    /// true aspect ratio).
    func testTheFloorHoldsTheScanLabelOnOneLine() {
        let label = Text("SCAN")
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .padding(3)
        let natural = NSHostingController(rootView: label).sizeThatFits(in: CGSize(width: 10_000, height: 10_000))
        XCTAssertGreaterThan(natural.width, 20, "the probe measured the label (\(natural.width) pt)")
        XCTAssertLessThan(natural.height, 30, "one line of 9-pt text (\(natural.height) pt)")
        XCTAssertGreaterThanOrEqual(ScanNavigatorPlacement.minSide, natural.width,
                                    "the floor is below the label (\(natural.width) pt): it would wrap")
        XCTAssertGreaterThanOrEqual(ScanNavigatorPlacement.size(rx: 17, ry: 77).width, natural.width,
                                    "the drive's 17 x 77 scan: the inset is as wide as its label")
    }
}

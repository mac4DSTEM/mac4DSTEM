import AppKit
import SwiftUI
import XCTest
@testable import mac4DSTEM

/// The S6 kit additions: `InspectorWarning` (the caption-size orange note) and
/// `InspectorAdaptiveMenu` (the menu twin of `InspectorAdaptiveButton`).
/// Both are laid out through a hosting controller, the way
/// `InspectorWidthBudgetTests` measures a room.
@MainActor
final class InspectorKitGapsTests: XCTestCase {
    private func size<V: View>(_ view: V, width: CGFloat?) -> CGSize {
        let host = NSHostingController(rootView: view)
        let proposed = CGSize(width: width ?? 10_000, height: 10_000)
        return host.sizeThatFits(in: proposed)
    }

    /// Mutation: `.fixedSize()` added to the body — red, the note no longer
    /// wraps and its width exceeds the 248-pt column.
    func testAWarningWrapsInsideTheInspectorColumn() {
        let text = "The selected reference-peak rank is absent in this pattern; "
            + "the relative filter cannot be evaluated."
        let wrapped = size(InspectorWarning(text), width: 248)
        let oneLine = size(InspectorWarning(text), width: nil)
        XCTAssertLessThanOrEqual(wrapped.width, 248)
        XCTAssertGreaterThan(oneLine.width, 248, "the probe text must be longer than the column")
        XCTAssertGreaterThan(wrapped.height, oneLine.height, "the note must wrap onto more lines")
    }

    func testAWarningMatchesTheHandRolledLabelItReplaces() {
        let text = "From an earlier run — the settings above have changed."
        let kit = size(InspectorWarning(text, systemImage: "nosign"), width: 248)
        let handRolled = size(
            Label(text, systemImage: "nosign").font(.caption).foregroundStyle(.orange),
            width: 248)
        XCTAssertEqual(kit.width, handRolled.width, accuracy: 0.5)
        XCTAssertEqual(kit.height, handRolled.height, accuracy: 0.5)
    }

    /// Mutation: the label replaced by a plain `Label` (no `ViewThatFits`) —
    /// red, the menu can no longer shrink below the title's width.
    func testAnAdaptiveMenuCollapsesToItsSymbolWhenTheRowIsNarrow() {
        func menu() -> InspectorAdaptiveMenu<Button<Text>> {
            InspectorAdaptiveMenu("Add a phase from the library", systemImage: "plus") {
                Button("One") {}
            }
        }
        let roomy = size(menu(), width: nil)
        let narrow = size(menu(), width: 1)
        XCTAssertLessThan(narrow.width, roomy.width)
    }
}

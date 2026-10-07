//
//  ShellGlassTests.swift
//  Lane L5 (Velox sheet row 8c): the dataset menu's "Preprocess Raw Data…" is a 4D-STEM verb, so a window that holds a
//  spectrum image and no 4D cube does not offer it. The shell's glass (flat columns, `.glass` buttons since lane L6, 2026-10-07)
//  is blind to a hosted-layout test; what is testable is the rule that decides the menu's items. Each test names its mutation.
//

import XCTest
@testable import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

@MainActor
final class ShellGlassTests: XCTestCase {

    /// Mutation: return true for every input (the verb always offered) -> the spectrum-only row goes red.
    func testPreprocessIsHiddenOnlyWhereASpectrumImageHasNoCube() {
        XCTAssertFalse(DatasetMenuRule.showsPreprocessRawData(hasSpectrumImage: true, hasCube: false),
                       "a spectrum image alone: a 4D verb has nothing to act on")
        XCTAssertTrue(DatasetMenuRule.showsPreprocessRawData(hasSpectrumImage: false, hasCube: false),
                      "an empty window still offers it (X3: with or without a dataset)")
        XCTAssertTrue(DatasetMenuRule.showsPreprocessRawData(hasSpectrumImage: false, hasCube: true),
                      "a cube alone")
        XCTAssertTrue(DatasetMenuRule.showsPreprocessRawData(hasSpectrumImage: true, hasCube: true),
                      "a cube with its spectrum image is still a 4D window")
    }

    /// The rule reads the app's own flags, the ones the Spectroscopy room uses (`isSpectrumOnly`).
    /// Mutation: pass `hasCube: appState.hasSpectrumImage` in the AppState overload -> the opened-image row goes red.
    func testTheRuleFollowsTheWindowsDocument() {
        let state = AppState()
        XCTAssertTrue(DatasetMenuRule.showsPreprocessRawData(in: state), "empty window")
        state.openSpectrumImage(DemoSpectrumImageSource.make())
        XCTAssertTrue(state.isSpectrumOnly)
        XCTAssertFalse(DatasetMenuRule.showsPreprocessRawData(in: state), "spectrum image, no cube")
    }
}

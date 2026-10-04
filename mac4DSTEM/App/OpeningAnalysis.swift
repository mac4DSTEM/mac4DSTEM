import Foundation
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif

/// What an opened (or reopened) dataset says once its first analysis has run:
/// pure, so it is unit-tested rather than implied by the order of calls in
/// `activate` (polish 2026-09-30, drives 1 and 2B).
enum OpeningAnalysis {
    /// The footer's pattern readout for a position, one wording for the click
    /// and for the re-assert below.
    static func patternReadout(_ position: ScanPos) -> String {
        "Pattern x \(position.x), y \(position.y)"
    }

    /// A reopen that CARRIES the user's place (promote) ends on the analysis
    /// line ("Virtual detector ✓ …"), so the selected position was readable
    /// only from the marker (drive 2B). The readout is put back when there is
    /// a position worth reading — off the origin — and the analysis left an
    /// image (a failed or cancelled one keeps its own line).
    static func restoresPatternReadout(selected: ScanPos, hasProduct: Bool) -> Bool {
        hasProduct && selected != ScanPos(x: 0, y: 0)
    }
}

extension AppState {
    /// The analysis every open path runs once the dataset is active
    /// (`activate`, a file open, a configurator commit, a promote). It is
    /// PREPARE's pass: `activate` always lands the window in Prepare, whose
    /// own result is the virtual image — the same first image a launch shows
    /// (drives 1 and 2B). It never runs the remembered task: the task is kept
    /// so the user's place survives, but nothing of it runs here, and a task
    /// whose analysis is a whole-scan pass (DPC) or whose result belongs to
    /// another room (a restored Bragg map or strain map) must not fill Prepare
    /// unasked. A room shows its own result when it is entered
    /// (`presentProductForEnteredMode`).
    func runOpeningAnalysis() async {
        await runVirtualDetector()
        if OpeningAnalysis.restoresPatternReadout(
            selected: selectedScan, hasProduct: resultPresentation.product != nil
        ) {
            showReadout(OpeningAnalysis.patternReadout(selectedScan))
        }
    }
}

import Foundation
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif

/// What an opened (or reopened) dataset shows and says once its first
/// analysis has run. Two rules, pure so they are unit-tested rather than
/// implied by the order of calls in `activate` (polish 2026-09-30, drives 1
/// and 2B).
enum OpeningAnalysis {
    /// A freshly opened cube in Prepare must show an image. The task the
    /// user last used is carried across datasets, and most tasks have nothing
    /// to show before their own explicit run — a cube opened after a phase
    /// map titled its real-space pane "Phase map (0 candidates)" over "No
    /// Result Yet" in Prepare, a room with no phase map in it. So when the
    /// default action left nothing on screen, the virtual image — the same
    /// first image a launch shows — is what the pane gets. Never repeated for
    /// the virtual-detector task itself (it already tried) and never outside
    /// Prepare (a task's own room keeps its own empty state).
    static func needsVirtualImage(
        hasProduct: Bool, area: WorkspaceArea, mode: AnalysisMode
    ) -> Bool {
        !hasProduct && area == .prepare && mode != .virtualDetector
    }

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
    /// (`activate`, a file open, a configurator commit, a promote).
    func runOpeningAnalysis() async {
        await runCurrentAnalysis()
        if OpeningAnalysis.needsVirtualImage(
            hasProduct: resultPresentation.product != nil,
            area: navigation.workspaceArea, mode: navigation.analysisMode
        ) {
            await runVirtualDetector()
        }
        if OpeningAnalysis.restoresPatternReadout(
            selected: selectedScan, hasProduct: resultPresentation.product != nil
        ) {
            showReadout(OpeningAnalysis.patternReadout(selectedScan))
        }
    }
}

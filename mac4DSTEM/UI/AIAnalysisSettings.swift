import SwiftUI
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif

/// The AI Analysis workspace's inspector Settings tab — the sixth analysis
/// room (owner decision, `docs/decisions.md`).
///
/// Learned-disks classification lives in the Disks room
/// (`UI/MapSettings.swift`); precipitates are not wired here because their
/// ship gate is unmet (`docs/archive/v3/precipitate-baseline-2026-09-11.md`).
/// Add their section here, beside grouping, once that gate is met.
struct AIAnalysisSettings: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        switch appState.navigation.analysisMode {
        case .phaseMapping: PhaseMappingSections()
        // Grouping is the room's default task, and anything that is not phase
        // mapping arrives here only by landing on that default.
        default: DiffractionGroupsSection()
        }
    }
}

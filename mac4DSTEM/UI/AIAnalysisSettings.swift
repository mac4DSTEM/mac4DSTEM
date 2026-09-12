import SwiftUI
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif

/// The AI Analysis workspace's inspector Settings tab — the sixth room the
/// owner asked for on 2026-09-11 (`docs/decisions.md`).
///
/// Written fresh rather than ported. The branch's `AIAnalysisSettings` hosted
/// a learned-disks case that v3.0.0 retired into the Disks room
/// (`UI/MapSettings.swift`), and a precipitates section that is not wired this
/// run — its pre-registered ship gate is unmet
/// (`docs/archive/v3/precipitate-baseline-2026-09-11.md`). Porting it would
/// have re-landed a panel for a capability that already lives elsewhere and a
/// panel for one that does not ship.
///
/// So this holds exactly what the room actually contains today. When
/// precipitates earn their gate, their section is added here beside it.
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

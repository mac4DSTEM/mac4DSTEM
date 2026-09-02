import SwiftUI
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif

/// The navigation/selection seam (S22c; `docs/development-process.md` §7 —
/// one seam per stage, extracted at a green boundary). Owns which workspace
/// and task the user is in and which panes are visible: pure view-state, no
/// science. `AppState` holds it as `navigation` without forwarding
/// properties — the same contract `StrainProductTests` pins for `strain`.
///
/// Orchestration deliberately stays on `AppState` (`selectWorkspace`,
/// `changeMode`): switching tasks touches result bookkeeping and recovery,
/// which are AppState's to coordinate. This type only stores the answer.
@Observable
final class WorkspaceNavigation {
    /// Changing workspace releases the focus ring: `nil` until one of the new
    /// workspace's panes claims it. Results has a single pane, so it is
    /// focused on arrival.
    var workspaceArea: WorkspaceArea = .prepare {
        didSet {
            if workspaceArea != oldValue {
                focusedPane = workspaceArea == .results ? .result : nil
            }
        }
    }

    /// v2.5 step 7c (plan §11g decision 3): the pane holding the focus ring,
    /// written by that pane and read only by the inspector column.
    /// `ActivePane` is untouched — it still drives Prepare's ROI direction.
    var focusedPane: FocusedPane?

    /// Which inspector the column renders. `nil` focus keeps the 7b per-task
    /// conditions (`AppState.inspectorShows*`) — an adapter that expires when
    /// every pane sets `focusedPane` (7c slice 5).
    var inspectorContent: InspectorContent {
        focusedPane == .result ? .product : .dataset
    }

    /// Task selection. The recovery hook preserves the exact semantics the
    /// old stored property's `didSet` had on `AppState`: persist the
    /// position whenever the task actually changes, whoever wrote it.
    var analysisMode: AnalysisMode = .virtualDetector {
        didSet { if analysisMode != oldValue { onModeChange?() } }
    }

    var showLogPane = false
    var showToolsPane = true
    var showInspectorPane = false

    @ObservationIgnored var onModeChange: (() -> Void)?
}

/// The pane that carries the focus ring, named by what it draws — one
/// descriptor per pane (plan §11c), so the inspector never asks which
/// workspace it is in. Cases are added as each workspace's panes start
/// claiming it.
enum FocusedPane: Equatable, Sendable {
    /// A live CBED pattern with the virtual detector drawn over it (Prepare,
    /// Imaging's virtual detector): the aperture rows and the diffraction
    /// histogram belong beside it.
    case detectorPattern
    /// A live CBED pattern without a detector overlay (Bragg disks): the
    /// diffraction histogram, no aperture rows.
    case pattern
    /// A real-space image or map computed from the cube: its own histogram.
    case image
    /// The Results workspace's product pane: `ProductInspector`.
    case result

    var showsAperture: Bool { self == .detectorPattern }
    var showsDiffractionHistogram: Bool { self == .detectorPattern || self == .pattern }
    var showsRealSpaceHistogram: Bool { self == .image }

    /// The descriptor a live pane claims when it takes the ring. `nil` for a
    /// workspace whose panes do not claim yet (7c slices 3–5), which leaves
    /// the inspector on the 7b per-task conditions — the adapter expires
    /// when every case here is non-nil.
    static func livePane(
        _ active: ActivePane, in area: WorkspaceArea, task: AnalysisMode
    ) -> FocusedPane? {
        switch area {
        case .prepare, .image:
            // Both draw the virtual detector on their diffraction pane.
            active == .diffraction ? .detectorPattern : .image
        case .map:
            switch task {
            case .disks:
                active == .diffraction ? .pattern : .image
            default:
                // Beside a strain or orientation map the diffraction pane
                // shows the map's evidence overlays; its descriptor is the
                // map's (7b's rule, F1.59, kept).
                .image
            }
        case .reconstruct, .results:
            nil
        }
    }
}

enum InspectorContent: Equatable, Sendable {
    /// `DatasetInspector`: file, live panes, diagnostics, products.
    case dataset
    /// `ProductInspector`: the displayed product's descriptor, the session
    /// inventory, diagnostics (plan §11g decision 2).
    case product
}

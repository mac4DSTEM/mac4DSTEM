import Foundation
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif

/// The window's two documents (v5.0 WP2, ADR 053 item 3): a 4D cube, an EDX
/// spectrum image, or both. Placement, not an owner — the state is
/// `spectroscopy` (`SpectroscopySession`) and the 4D owners.
///
/// **The split.** `hasDataset` keeps its meaning, a 4D cube is open
/// (`descriptor?.is4D == true`), and every 4D gate keeps reading it, so no 4D
/// behaviour changes. `hasDocument` is the new, wider question — does the
/// window hold anything — asked only where a spectrum-only window must not
/// fall back to the welcome screen.
extension AppState {
    /// An EDX spectrum image is open in this window.
    var hasSpectrumImage: Bool { spectroscopy.source != nil }

    /// The window holds a document of either kind.
    var hasDocument: Bool { hasDataset || hasSpectrumImage }

    /// A spectrum image and no 4D cube: the 4D rooms have nothing to show.
    var isSpectrumOnly: Bool { hasSpectrumImage && !hasDataset }

    /// Whether the Go to <room> menu item may be chosen (`WorkspaceArea.isAvailable`).
    func isWorkspaceAvailable(_ area: WorkspaceArea) -> Bool {
        area.isAvailable(hasFourDCube: hasDataset, hasSpectrumImage: hasSpectrumImage)
    }

    /// Whether the sidebar disables this room and `selectWorkspace` declines
    /// it: a 4D room in a spectrum-only window. Narrower than
    /// `!isWorkspaceAvailable` on purpose — with no document at all the
    /// sidebar's rooms stay selectable, as they were before the seventh room.
    func isWorkspaceWithheld(_ area: WorkspaceArea) -> Bool {
        isSpectrumOnly && area.needsFourDCube
    }

    /// Opening a 4D file while this window holds only a spectrum image opens a
    /// NEW window (supervisor's decision, 2026-10-05, on Fable's advice): Velox
    /// and GMS open every file as its own document, and attaching the cube here
    /// would assert a registration between the two scans that the app cannot
    /// state until WP3's registration record. Both open funnels (`openFile`,
    /// `openFileForConfiguration`) ask this first; true means the URL went to
    /// the new window and this window does nothing. With no spectrum image, or
    /// with a 4D cube already open, it is false and the open runs as before.
    /// No route set (a test, a harness) also leaves the open as before.
    func routesOpenToNewWindow(_ url: URL, configure: Bool) -> Bool {
        guard isSpectrumOnly, let route = openInNewWindow else { return false }
        route(url, configure)
        return true
    }

    /// The entry point a reader calls with an opened EDX spectrum image (the
    /// Velox routing and the DM4 EDS SI come later, through Gate B). The image
    /// becomes this window's — beside the 4D cube when one is open, which it
    /// leaves untouched — and the window shows its room.
    func openSpectrumImage(_ source: any SpectrumImageSource) {
        spectroscopy.open(source)
        selectWorkspace(.spectroscopy)
        statusText = "Opened \(source.metadata.fileName)"
    }
}

#if DEBUG
/// A spectrum image with metadata only, so the room can be seen before the
/// readers land: `--demo-spectrum-fixture` opens it in a fresh window
/// (`DatasetWindow`, the `--demo-fixture` shape). DEBUG builds only; it holds
/// no spectra, and nothing reads any.
final class DemoSpectrumImageSource: SpectrumImageSource {
    /// The launch flag's once-guard, process-wide (`DatasetWindow`).
    static var openedAtLaunch = false
    let metadata = SpectrumImageMetadata(
        fileName: "Demo spectrum image", filePath: "",
        scanWidth: 64, scanHeight: 64, channelCount: 2048,
        energyOffsetEV: 0, energyDispersionEV: 10,
        scanPixelSize: 1, scanPixelUnit: "nm")
}
#endif

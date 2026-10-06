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

    /// The entry point a reader calls with an opened EDX spectrum image. The image becomes this window's — beside the
    /// 4D cube when one is open, which it leaves untouched — and the window shows its room.
    func openSpectrumImage(_ source: any SpectrumImageSource) {
        attachSpectrumImage(source)
        selectWorkspace(.spectroscopy)
        statusText = "Opened \(source.metadata.fileName)"
    }

    /// Makes `source` the window's spectrum image and binds the room to it, WITHOUT changing the room: the GMS joint open
    /// lands on the 4D cube's room as before and the Spectroscopy room is then one ⌘6 away.
    func attachSpectrumImage(_ source: any SpectrumImageSource) {
        spectroscopy.open(source)
        spectroscopyRoom.bind(source, session: spectroscopy, hasFourDCube: hasDataset)
    }

    /// v5.0 WP2: the shipped-behaviour change. A Velox EMD (it used to open as a one-row cube, open-items) or a DM4 whose
    /// only 3D+ object is an EDS spectrum image opens as a spectrum image: no cube, the Spectroscopy room selected.
    /// Returns false, having touched nothing, for every other file, so the 4D open that follows is exactly as before.
    ///
    /// Off the main actor: sniffing the file and decoding it (~3.6 s for a 1.7 GB Velox file) run in detached tasks, the
    /// open is bracketed as a load (spinner, Cancel) like the 4D open, and a cancel drops the result. A spectrum image
    /// holds no security-scoped access after the read (it is read whole) and is not added to Recents (a Recent re-opens through
    /// `openFile`, which routes it again, but Recents carry sidecar semantics that spectrum images do not have yet).
    /// The security-scope calls and the sniff, injectable so a test can see the order. The sniff MUST run inside the scope: for
    /// a sandboxed Recents or Reopen bookmark URL it cannot read the file outside it, answers `.other`, and the 4D open would
    /// take the Velox HAADF stack for a one-row cube (the shipped defect).
    struct SpectrumOpenAccess {
        var start: (URL) -> Bool = { $0.startAccessingSecurityScopedResource() }
        var stop: (URL) -> Void = { $0.stopAccessingSecurityScopedResource() }
        var kind: @Sendable (String) -> SpectrumFileKind = { SpectrumImageOpener.kind(ofFileAt: $0) }
    }

    func openAsSpectrumImageIfApplicable(_ url: URL, access: SpectrumOpenAccess = SpectrumOpenAccess()) async -> Bool {
        let ext = url.pathExtension.lowercased()
        guard ext == "emd" || ext == "dm4" else { return false }
        let path = url.path
        let accessed = access.start(url)
        defer { if accessed { access.stop(url) } }
        let sniff = access.kind
        let kind = await Task.detached(priority: .userInitiated) { sniff(path) }.value
        guard kind != .other else { return false }
        // One window rule (owner's reverse case, R2 round 2): a window that holds a 4D cube does not take a spectrum image
        // from a file open either; it goes to a NEW window, as a 4D file does from a spectrum-only one. (The joint GMS
        // attach does not come through here.)
        if hasDataset, let route = openInNewWindow { route(url, false); return true }
        let load = beginDatasetLoading("Opening \(url.lastPathComponent)…")
        errorMessage = nil
        defer { finishDatasetLoading(owner: load) }
        beginDatasetLoadingStage(kind == .veloxSpectrumImage
            ? "Reading the spectrum stream of \(url.lastPathComponent)…"
            : "Reading the EDS spectrum image of \(url.lastPathComponent)…")
        do {
            let image = try await Task.detached(priority: .userInitiated) {
                try SpectrumImageOpener.open(path: path, kind: kind)
            }.value
            if load.isCancelled || datasetSession.loadWasCancelled { statusText = "Load cancelled"; return true }
            openSpectrumImage(image)
        } catch {
            present(error)
        }
        return true
    }

    /// After a 4D cube opened from a GMS file: attaches the file's EDS spectrum image, if it has one, as the window's
    /// spectrum image, registered by identity (same Experiment ID and scan grid) or with the reason it is not. A failure
    /// here never fails the cube's open: it is said in the status line.
    func attachGMSSpectrumImage(of url: URL, descriptor: DatasetDescriptor) async {
        guard url.pathExtension.lowercased() == "dm4" else { return }
        let path = url.path
        let identity = GMSFourDIdentity(objectIndex: Self.gmsObjectIndex(descriptor.datasetPath),
                                        scanWidth: descriptor.rx, scanHeight: descriptor.ry)
        statusText = "Looking for an EDS spectrum image in \(url.lastPathComponent)…"
        let result: Result<LoadedSpectrumImage?, Error> = await Task.detached(priority: .userInitiated) {
            Result { try SpectrumImageOpener.openGMSEDS(path: path, fourD: identity) }
        }.value
        // The cube is already showing (this runs after the load finished): attach only if it is still this window's cube.
        guard self.descriptor?.filePath == descriptor.filePath, hasDataset else { return }
        switch result {
        case .success(let image?): attachSpectrumImage(image)
        case .success(nil): break
        case .failure(let error): statusText = "The EDS spectrum image in \(url.lastPathComponent) was not attached: \(error.localizedDescription)"
        }
    }

    /// `ImageList.4.ImageData.Data` -> 4.
    static func gmsObjectIndex(_ datasetPath: String) -> Int? {
        let parts = datasetPath.split(separator: ".")
        return parts.count >= 2 && parts[0] == "ImageList" ? Int(parts[1]) : nil
    }
}

#if DEBUG
/// A small synthetic spectrum image (32 x 32 px, 1024 channels of 10 eV; an Al matrix with a Mg-Si blob), so the room can be
/// seen without a file: `--demo-spectrum-fixture` opens it in a fresh window (`DatasetWindow`, the `--demo-fixture` shape).
/// DEBUG builds only. Its counts are made up and say nothing about any sample.
enum DemoSpectrumImageSource {
    /// The launch flag's once-guard, process-wide (`DatasetWindow`).
    static var openedAtLaunch = false

    static func make() -> LoadedSpectrumImage {
        let ny = 32, nx = 32, channels = 1024
        var counts = [UInt32](repeating: 0, count: ny * nx * channels)
        var state: UInt64 = 0x9E3779B97F4A7C15
        func next() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Double(state >> 40) / Double(1 << 24)
        }
        let peaks: [(keV: Double, matrix: Double, blob: Double)] = [(1.487, 40, 12), (1.254, 0.4, 14), (1.740, 0.4, 16)]
        for y in 0..<ny { for x in 0..<nx {
            let inBlob = pow(Double(x) - 16, 2) + pow(Double(y) - 16, 2) < 64
            for c in 0..<channels {
                let e = Double(c) * 0.01
                var mean = 0.4 * exp(-e / 3)
                for p in peaks { mean += (inBlob ? p.blob : p.matrix) * exp(-pow(e - p.keV, 2) / (2 * 0.0035)) * 0.02 }
                counts[(y * nx + x) * channels + c] = UInt32(max(0, mean + (next() - 0.5) * sqrt(max(mean, 0.01))))
            }
        } }
        var meta = SpectrumImageMetadata(fileName: "Demo spectrum image", filePath: "", scanWidth: nx, scanHeight: ny,
                                         channelCount: channels, energyOffsetEV: 0, energyDispersionEV: 10,
                                         scanPixelSize: 1, scanPixelUnit: "nm")
        meta.origin = nil
        return LoadedSpectrumImage(image: DenseSpectrumImage(ny: ny, nx: nx, channels: channels, counts: counts), metadata: meta,
                                   energyAxis: EnergyAxis(offset: 0, scale: 0.01, size: channels))
    }
}
#endif

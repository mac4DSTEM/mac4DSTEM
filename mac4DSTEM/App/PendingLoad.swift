//
//  PendingLoad.swift
//  Role: A dataset that has been opened far enough to look at, but not yet
//        committed to a load — the state L5's configurator edits.
//
//  This is the stage's `AppState` seam (docs/development-process.md §7): the
//  state L5 *adds*, in its own `@Observable` type that `AppState` holds, no
//  forwarding properties. Same precedent as `App/DatasetResidency.swift` (L2)
//  and `App/LoadedView.swift` (L3/L4). v2 S4 keeps the rule: the single-DP
//  pane, the display caches and the direct-beam guard all live here, and the
//  facade gained nothing.
//
//  THE MOMENT THIS EXISTS FOR. The plan's L5 item 2: the size arithmetic is only
//  worth showing while the decision is still cheap. Once a 50 GB cube has been
//  read there is nothing to decide. So the reader is opened, the descriptor
//  discovered and a strided preview built — all cheap — and then the app STOPS
//  and asks, instead of committing to the expensive pass.
//
//  ENTRY IS OPT-IN (release owner, 2026-08-18). "Open Dataset…" loads the whole
//  file exactly as it always has; this path is reached only from "Open with
//  options…". The alternative — configuring on every open — was the plan's
//  literal intent but puts a step in front of every open including the many
//  where the whole file is what you want, and a defect in it would block all
//  opens rather than one path.
//

import Foundation
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif

@Observable
final class PendingLoad: Identifiable {

    /// One display-ready image: normalized pixels plus the version
    /// `UI2MetalImage` keys its texture upload on. Computed ONCE when the
    /// data lands — never in a view body (#31's class of defect) — so a crop
    /// drag tick costs no per-frame normalization or hashing.
    struct DisplayImage {
        let pixels: [Float]
        let width: Int
        let height: Int
        let version: Int

        init(pixels: [Float], width: Int, height: Int) {
            self.pixels = pixels
            self.width = width
            self.height = height
            self.version = UI2MetalImage.contentVersion(
                of: pixels, width: width, height: height
            )
        }
    }

    /// Stable for the life of this pending open, so presenting it as a sheet
    /// does not re-create the sheet on every keystroke in the configurator.
    let id = UUID()

    /// The dataset as stored, at full extent.
    let source: DatasetDescriptor
    /// Held open so committing does not have to re-open and re-discover.
    let reader: any FourDDataSource
    /// One array over the source for every pre-load read — the preview build
    /// and the single-DP fetches share its pattern cache, so clicking a
    /// position the preview already sampled costs nothing (a per-fetch array
    /// started cold and re-read the disk every click).
    let data: FourDArray
    /// The security-scoped URL this came from, handed back on commit or release.
    let url: URL
    /// Whether `startAccessingSecurityScopedResource` succeeded, so the release
    /// path knows whether it owes a stop.
    let accessedSecurityScope: Bool

    /// The strided sample the user is looking at while deciding. Nil while it
    /// is still being built — the configurator shows the arithmetic either way,
    /// because the numbers do not depend on the picture.
    var preview: DatasetPreview? {
        didSet { previewDidLand() }
    }

    /// What the user has configured. Starts at full extent, which is the
    /// identity: pressing Load without touching anything is the same load
    /// "Open Dataset…" would have done.
    var configuration: LoadConfiguration

    /// Bytes the file occupies on disk, or nil if it could not be read.
    ///
    /// Worth showing next to the f32 cube size because the two differ by the
    /// dtype: a uint16 file costs **twice** its own size once loaded, and that
    /// is exactly the surprise this screen exists to remove.
    let fileByteCount: Int?

    init(
        source: DatasetDescriptor,
        reader: any FourDDataSource,
        url: URL,
        accessedSecurityScope: Bool,
        fileByteCount: Int?
    ) {
        self.source = source
        self.reader = reader
        self.data = FourDArray(reader: reader, descriptor: source)
        self.url = url
        self.accessedSecurityScope = accessedSecurityScope
        self.fileByteCount = fileByteCount
        self.configuration = LoadConfiguration(source: source)
    }

    // MARK: - Display caches (v2 S4)

    /// The three panes' pixels, normalized at SET time. `realSpace` and
    /// `maxDP` are recomputed only if `preview` is ever reassigned;
    /// `singleDP` recomputes per fetched pattern.
    private(set) var realSpaceDisplay: DisplayImage?
    private(set) var maxDPDisplay: DisplayImage?
    private(set) var singleDPDisplay: DisplayImage?

    private func previewDidLand() {
        guard let preview else {
            realSpaceDisplay = nil
            maxDPDisplay = nil
            beamPosition = nil
            return
        }
        realSpaceDisplay = DisplayImage(
            pixels: preview.realSpace.normalized(),
            width: preview.realSpace.width, height: preview.realSpace.height
        )
        // Log for the same reason as everywhere a max-DP is drawn:
        // linear-normalized it is the central beam and nothing else.
        maxDPDisplay = DisplayImage(
            pixels: preview.maxDP.normalized(useLog: true),
            width: preview.maxDP.qx, height: preview.maxDP.qy
        )
        beamPosition = Self.beamProxyPosition(of: preview.meanDP)
    }

    // MARK: - The single-DP pane (owner request 2026-08-18, v2 S4)

    /// One REAL diffraction pattern, at a scan position the user picked by
    /// clicking the real-space preview. The mean/max panes answer "where is
    /// the signal overall"; this one answers "what does one actual pattern
    /// look like", which is what choosing a detector crop against needs.
    /// Nil until the first fetch lands.
    private(set) var singleDP: DiffractionPattern? {
        didSet {
            singleDPDisplay = singleDP.map {
                DisplayImage(pixels: $0.normalized(useLog: true),
                             width: $0.qx, height: $0.qy)
            }
        }
    }

    /// Source scan coordinates of `singleDP` — the position the caption names.
    /// Set at fetch *request* time so a click gives immediate feedback; the
    /// pattern follows when the read completes.
    private(set) var singleDPPosition: (ry: Int, rx: Int)?

    private var singleDPFetch: Task<Void, Never>?

    /// Fetch the pattern at a source scan position (clamped into the scan).
    /// A newer click cancels the older fetch, so a stale pattern can never
    /// land after a newer one — and superseded reads stop issuing work.
    func fetchSingleDP(ry: Int, rx: Int) {
        let y = max(0, min(source.ry - 1, ry))
        let x = max(0, min(source.rx - 1, rx))
        singleDPPosition = (y, x)
        singleDPFetch?.cancel()
        let array = data
        singleDPFetch = Task {
            guard !Task.isCancelled else { return }
            let pattern = try? await array.pattern(ry: y, rx: x)
            guard !Task.isCancelled else { return }
            self.singleDP = pattern
        }
    }

    /// Stop any in-flight fetch. The discard path calls this so a dropped
    /// `PendingLoad` does not keep reading a file whose security scope is
    /// about to be released.
    func cancelSingleDPFetch() {
        singleDPFetch?.cancel()
    }

    /// First fill of the single-DP pane: the brightest *sampled* scan position
    /// when a preview exists (a pattern with signal beats a corner of vacuum),
    /// the scan centre otherwise.
    func fetchDefaultSingleDP() {
        guard singleDPPosition == nil else { return }
        if let preview,
           let brightest = Self.brightestPosition(
               of: preview.realSpace.pixels,
               width: preview.realSpace.width, height: preview.realSpace.height
           ) {
            let position = preview.sourcePosition(
                forSampledX: brightest.x, sampledY: brightest.y
            )
            fetchSingleDP(ry: position.ry, rx: position.rx)
        } else {
            fetchSingleDP(ry: source.ry / 2, rx: source.rx / 2)
        }
    }

    /// Index of the largest finite pixel, as (x, y). Nil when the image is
    /// empty or nothing is finite. Pure, so the tests can pin it.
    nonisolated static func brightestPosition(
        of pixels: [Float], width: Int, height: Int
    ) -> (x: Int, y: Int)? {
        guard width > 0, height > 0, pixels.count == width * height else { return nil }
        var bestIndex = -1
        var bestValue = -Float.greatestFiniteMagnitude
        for (index, value) in pixels.enumerated() where value.isFinite {
            if value > bestValue {
                bestValue = value
                bestIndex = index
            }
        }
        guard bestIndex >= 0 else { return nil }
        return (bestIndex % width, bestIndex / width)
    }

    // MARK: - Configure-time direct-beam guard (v2 S4)

    /// Where the direct beam is, as evidenced by the sampled preview — the
    /// brightest pixel of the MEAN pattern, computed once when the preview
    /// lands. The direct beam dominates a mean over scan positions, while the
    /// max pattern can be won locally by one saturated Bragg disk.
    /// Nil when there is no usable evidence — no preview, or a FLAT mean
    /// (vacuum / flat-field data), where "the brightest pixel" is an artifact
    /// of tie-breaking, not a beam. Known limit, stated rather than hidden:
    /// a beam-stopped or hot-pixel acquisition can put the mean's brightest
    /// pixel somewhere other than the beam, and the guard below would then
    /// refuse a legitimate crop — the refusal message names its evidence so
    /// that case is arguable, and whether it needs an override is a queued
    /// owner question (docs/open-items.md).
    private(set) var beamPosition: (x: Int, y: Int)?

    nonisolated static func beamProxyPosition(
        of pattern: DiffractionPattern
    ) -> (x: Int, y: Int)? {
        guard pattern.qx > 0, pattern.qy > 0,
              pattern.pixels.count == pattern.qx * pattern.qy else { return nil }
        var bestIndex = -1
        var bestValue = -Float.greatestFiniteMagnitude
        var leastValue = Float.greatestFiniteMagnitude
        for (index, value) in pattern.pixels.enumerated() where value.isFinite {
            if value > bestValue {
                bestValue = value
                bestIndex = index
            }
            if value < leastValue {
                leastValue = value
            }
        }
        // Flat or empty ⇒ no evidence ⇒ no position (and so no refusal).
        guard bestIndex >= 0, bestValue > leastValue else { return nil }
        return (bestIndex % pattern.qx, bestIndex / pattern.qx)
    }

    /// Refusal of a detector selection that excludes the direct beam, decided
    /// BEFORE the load. `CalibrationReReference.apply` refuses this crop well —
    /// but only when there is an existing calibration to re-reference, so on a
    /// first open nothing fired: the load succeeded silently and the
    /// geometric-default centre landed wherever the box happened to be
    /// (release owner, 2026-08-19).
    ///
    /// Checked against the view's `readDetectorCrop` — the rectangle a reader
    /// ACTUALLY reads, crop trimmed to a whole number of bins — never
    /// `configuration.detectorCrop` (`LoadSpecification`'s own rule). The
    /// difference bites twice: a beam in the bin-trimmed remainder of a crop,
    /// and a bin on the full detector whose edge trim drops the beam with no
    /// crop set at all.
    var directBeamRefusal: String? {
        Self.directBeamRefusal(beam: beamPosition,
                               readDetectorCrop: view?.readDetectorCrop)
    }

    /// Pure so the tests can pin it. `crop` must be the READ rectangle.
    nonisolated static func directBeamRefusal(
        beam: (x: Int, y: Int)?, readDetectorCrop crop: AxisCrop?
    ) -> String? {
        guard let beam, let crop else { return nil }
        let inside = beam.x >= crop.xOffset && beam.x < crop.xOffset + crop.width
            && beam.y >= crop.yOffset && beam.y < crop.yOffset + crop.height
        guard !inside else { return nil }
        return "This detector selection excludes the direct beam: the brightest "
            + "region of the sampled preview is at detector column \(beam.x), "
            + "row \(beam.y), outside the region actually read — "
            + "rows \(crop.yOffset)–\(crop.yOffset + crop.height - 1), "
            + "columns \(crop.xOffset)–\(crop.xOffset + crop.width - 1), "
            + "after any bin trim. "
            + "Widen or move the crop — without the beam the loaded view has no valid origin."
    }

    // MARK: - What the configuration would cost

    /// The view that would be loaded, or nil when the configuration is not
    /// loadable (a bin factor that leaves no pixels, say). The Load button binds
    /// to this being non-nil, so the configurator cannot offer a load the reader
    /// would refuse.
    var view: LoadView? { configuration.view }

    var loadedByteCount: Int? { configuration.byteCount }
    var fullExtentByteCount: Int { configuration.fullExtentByteCount }

    /// "42% of the full cube", or nil at full extent where there is nothing to
    /// compare against.
    var reductionSummary: String? {
        guard let fraction = configuration.fractionOfFullExtent, fraction < 1 else { return nil }
        return String(format: "%.0f%% of the full cube", fraction * 100)
    }

    /// The loaded shape, as the reader would see it.
    var loadedShapeString: String? { view?.descriptor.shapeString }

    /// Detector rows and columns the bin factor would trim from the far edge.
    /// Stated before the load, not after: it is a change to what gets read.
    var discardedEdge: (rows: Int, columns: Int)? {
        guard let view, view.discardedDetectorRows > 0 || view.discardedDetectorColumns > 0
        else { return nil }
        return (view.discardedDetectorRows, view.discardedDetectorColumns)
    }

    /// Why the current configuration cannot be loaded, in the user's terms.
    var refusalReason: String? {
        guard view == nil else { return nil }
        do {
            _ = try LoadView(source: source, specification: configuration.specification)
            return nil
        } catch let error as LoadSpecificationError {
            return error.errorDescription
        } catch {
            return error.localizedDescription
        }
    }
}

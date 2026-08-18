//
//  PendingLoad.swift
//  Role: A dataset that has been opened far enough to look at, but not yet
//        committed to a load — the state L5's configurator edits.
//
//  This is the stage's `AppState` seam (docs/development-process.md §7): the
//  state L5 *adds*, in its own `@Observable` type that `AppState` holds, no
//  forwarding properties. Same precedent as `App/DatasetResidency.swift` (L2)
//  and `App/LoadedView.swift` (L3/L4).
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

@Observable
final class PendingLoad: Identifiable {

    /// Stable for the life of this pending open, so presenting it as a sheet
    /// does not re-create the sheet on every keystroke in the configurator.
    let id = UUID()

    /// The dataset as stored, at full extent.
    let source: DatasetDescriptor
    /// Held open so committing does not have to re-open and re-discover.
    let reader: any FourDDataSource
    /// The security-scoped URL this came from, handed back on commit or release.
    let url: URL
    /// Whether `startAccessingSecurityScopedResource` succeeded, so the release
    /// path knows whether it owes a stop.
    let accessedSecurityScope: Bool

    /// The strided sample the user is looking at while deciding. Nil while it
    /// is still being built — the configurator shows the arithmetic either way,
    /// because the numbers do not depend on the picture.
    var preview: DatasetPreview?

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
        self.url = url
        self.accessedSecurityScope = accessedSecurityScope
        self.fileByteCount = fileByteCount
        self.configuration = LoadConfiguration(source: source)
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

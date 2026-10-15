import Foundation
import simd
import DiffractoOrientation

/// The app's Bragg peaks in the form DiffractoKit's `PhaseVectorMatcher` takes (0.3.0 Migration: `scan:scanWidth:scanHeight:`
/// with `PeakCoordinates.detectorPixels`). Each peak's `Float` x, y becomes a `SIMD2<Double>` exactly, and the kit subtracts the
/// origin in `Float`, so the vectors equal the former `Double(p.x - originX) * scale` bit for bit.
extension BraggPeak {
    package nonisolated var phaseScanPosition: SIMD2<Double> { SIMD2(Double(x), Double(y)) }
}

extension BraggVectors {
    /// Row-major, `scanWidth` × `scanHeight`, as `peaks`.
    package nonisolated var phaseScan: [[SIMD2<Double>]] { peaks.map { $0.map(\.phaseScanPosition) } }
}

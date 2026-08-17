//
//  ResidentCube.swift
//  Role: The whole datacube held as one float32 MTLBuffer, and the rule that
//        decides whether a given cube is allowed to be held that way.
//
//  WHY THIS IS CHEAP: `VirtualDetector.tiled` already builds an MTLBuffer per
//  scan tile and hands it to the SAME compute functions a whole-cube path
//  would call — there is no separate tiled kernel. A resident cube is just
//  "the tile is the whole cube, and the buffer is not thrown away".
//
//  EXACTNESS (invariant I2, docs/load-pipeline-plan.md §4). `virtualMaskSum`
//  and `virtualAperture` run one thread per SCAN position, summing over the
//  detector in a fixed order, from a mask built out of qy/qx only. Tiles
//  partition the SCAN axis, so a tile boundary never splits a per-output-pixel
//  reduction and every tile sees the identical mask. The resident and tiled
//  virtual images are therefore BIT-IDENTICAL, which is why
//  tools/virtual-detector-residency asserts exact `==` rather than a tolerance.
//
//  That argument does NOT cover reductions that combine tiles:
//  `tiledDPStatistics` (weighted mean) and `tiledDiffraction` (running sum) are
//  float-order dependent. They keep their tiled reduction even when the cube is
//  resident — `FourDArray.scanTile` simply serves their tiles out of the
//  resident buffer, so they skip the disk without changing a single number.
//

import Foundation
import Metal

/// How the compute layer gets its pixels.
enum Residency: String, Sendable, CaseIterable {
    /// Bounded scan-row tiles. Always available, always tested (invariant I6).
    case streamed
    /// One MTLBuffer holding the whole cube as float32.
    case resident
    /// Resident when the cube fits the *measured* admission budget, else
    /// streamed. See `ResidencyAdmission.measuredWorkingSetFraction`.
    case automatic
}

/// The whole cube as one float32 buffer, with the descriptor it was built from.
///
/// `@unchecked Sendable`: the buffer is filled once, before this value is
/// published, and is only ever read afterwards — every kernel binds the cube as
/// an input. Same rationale as `FFT2D`'s setup: immutable after construction,
/// so sharing it across actors is safe even though `MTLBuffer` is not Sendable.
nonisolated struct ResidentCube: @unchecked Sendable {
    let buffer: MTLBuffer
    let descriptor: DatasetDescriptor
    /// Which view of the source these bytes are. Compared by `matches`, because
    /// the descriptor alone cannot tell two equal-sized crops apart.
    let specification: LoadSpecification

    var byteCount: Int { descriptor.byteCountAsFloat32 }

    /// Whether this buffer actually holds the cube `other` describes.
    ///
    /// Checked at every dispatch rather than assumed.
    ///
    /// **The specification is part of the identity, and that is the whole
    /// point.** Comparing file, dataset path and shape alone is not enough:
    /// `LoadSpecification` crops carry *offsets*, so two crops of equal extent
    /// at different positions — `y:0..<128, x:0..<128` versus
    /// `y:128..<256, x:128..<256` on a 256×256 detector — produce an identical
    /// `filePath`, an identical `datasetPath` and an identical `shape`, over
    /// completely disjoint pixels. Shape-only matching would hand a stale buffer
    /// to the resident fast path and compute a correct number about the wrong
    /// data — exactly what this guard exists to prevent.
    ///
    /// Found by adversarial review 2026-08-17, when an earlier comment here
    /// claimed the opposite (that a specification change "will reshape the
    /// descriptor"). Closed in L3 by carrying the specification.
    func matches(_ other: DatasetDescriptor,
                 specification otherSpecification: LoadSpecification) -> Bool {
        descriptor.filePath == other.filePath
            && descriptor.datasetPath == other.datasetPath
            && descriptor.shape == other.shape
            && specification == otherSpecification
    }
}

/// The admission rule: may this cube be held resident on this machine?
enum ResidencyAdmission {

    /// The fraction of the device's **own** recommended Metal working set that
    /// a resident cube may occupy.
    ///
    /// **`nil` means not yet measured, and `.automatic` therefore streams.**
    ///
    /// This is deliberately not a number anyone reasoned their way to.
    /// Getting it wrong does not throw — Metal pages, and the app becomes
    /// *slower than tiled while appearing to succeed*, which is the worst
    /// regression class this app produces. `docs/load-pipeline-plan.md` L2.3
    /// requires the knee to be **measured** by the residency sweep in
    /// `tools/performance-baseline/`, on two real cubes either side of it,
    /// before this becomes non-nil.
    ///
    /// It is a fraction of the machine's own working set, never a fixed byte
    /// count: the app ships to Macs from 8 GB to 128 GB+, and the same cube
    /// must go resident on a large machine and stream on a small one, from one
    /// rule. Tuning it to make one particular dataset fit would be a defect.
    static let measuredWorkingSetFraction: Double? = nil

    /// Whether `descriptor` fits `fraction` of `workingSetSize`.
    ///
    /// Reads return Float32 regardless of the on-disk dtype (see
    /// `FourDDataSource`), so a uint16 file needs **twice** its file size here.
    /// `byteCountAsFloat32` is already that number; the on-disk size would be
    /// the more flattering figure and the wrong one.
    static func admits(
        _ descriptor: DatasetDescriptor,
        workingSetSize: UInt64,
        fraction: Double
    ) -> Bool {
        guard descriptor.is4D, fraction > 0, workingSetSize > 0 else { return false }
        let bytes = descriptor.byteCountAsFloat32
        guard bytes > 0 else { return false }
        return Double(bytes) <= Double(workingSetSize) * fraction
    }

    /// Resolve a requested mode against this machine.
    ///
    /// `.resident` bypasses the *threshold* — that is the seam the parity
    /// harness needs, since the development machine is an 8 GB M3 MacBook Air
    /// whose working set cannot hold a real cube, and an admission-gated
    /// harness would silently compare the tiled path against itself, which is
    /// the exact "assertion that passes in the broken state" this repo has been
    /// burned by.
    ///
    /// **It does not bypass `maximumBufferLength`.** An earlier version made
    /// `.resident` unbounded on the grounds that "the caller takes
    /// responsibility", which was not a real safeguard: no caller can check a
    /// limit the repo never consulted — `maxBufferLength` had zero references
    /// anywhere — and a shared-storage allocation past it either fails or, on
    /// Apple Silicon, succeeds virtually and thrashes on first touch. Refusing
    /// is the only honest answer, and the caller degrades to streaming (I6).
    static func shouldAdmit(
        _ requested: Residency,
        descriptor: DatasetDescriptor,
        workingSetSize: UInt64,
        maximumBufferLength: Int,
        fraction: Double? = measuredWorkingSetFraction
    ) -> Bool {
        guard descriptor.is4D else { return false }
        let bytes = descriptor.byteCountAsFloat32
        guard bytes > 0, bytes <= maximumBufferLength else { return false }
        switch requested {
        case .streamed:
            return false
        case .resident:
            return true
        case .automatic:
            guard let fraction else { return false }
            return admits(descriptor, workingSetSize: workingSetSize, fraction: fraction)
        }
    }
}

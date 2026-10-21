import Foundation
import simd
import DiffractoCore
import DiffractoOrientation

// The orientation value types (`EulerAngles`, `ZoneAxisFrame`, `OrientationResult`) and the symmetry mathematics
// (reduction to the fundamental zone, direction folding and sampling, the cubic, hexagonal and monoclinic IPF keys)
// are DiffractoKit's DiffractoOrientation since 0.5.0 (`CrystalOrientationSymmetry`, key `.native`: the app's
// own conventions, pinned bit-exact to the former app source). What stays here is the app's policy and presentation:
// the backend choice, `ACOMCrystalSymmetry` (a thin facade over the kit, plus the unreduced fallback the kit does not
// have) and `OrientationMap`.

package nonisolated enum ACOMMatchingBackend: String, Sendable, Equatable, CaseIterable, Identifiable {
    case automatic = "Automatic"
    case cpu = "Accelerate CPU"
    case metal = "Metal GPU"

    package var id: String { rawValue }
}

/// One corner of the 6/mmm key triangle: its crystal-Cartesian direction (py4DSTEM frame: a along +x, c along +z), the
/// four-index label the legend prints, and the colour the kit's `.native` hexagonal key gives it.
package nonisolated struct HexagonalKeyCorner: Sendable, Equatable {
    package let direction: SIMD3<Double>
    package let label: String
    package let color: SIMD3<Float>
}

/// Explicit symmetry policy for orientation reporting. The built-in presets and the custom editor
/// are cubic or hexagonal; an imported structure may also be `.monoclinic` (2/m, b unique, 2026-10-14);
/// `.identity` is the safe fallback for every other structure until its point group is implemented. It has no
/// fundamental zone, so no plan is built for it (`CrystalModel.supportsOrientationMapping`, `OrientationPlan.generate`);
/// its branches below are reachable only from direct callers and tests, kept for the model's reporting helpers.
/// The three reduced cases are the kit's `CrystalOrientationSymmetry` for m-3m, 6/mmm and 2/m with the `.native` keys.
package nonisolated enum ACOMCrystalSymmetry: String, Sendable, Equatable {
    case cubic
    case hexagonal
    case monoclinic
    case identity

    package var displayName: String {
        switch self {
        case .cubic: return "Cubic m-3m"
        case .hexagonal: return "Hexagonal 6/mmm"
        case .monoclinic: return "Monoclinic 2/m"
        case .identity: return "Unreduced"
        }
    }

    /// The kit's Laue class of the reduced cases; nil for `.identity`, which has no fundamental zone.
    package var laueClass: LaueClass? {
        switch self {
        case .cubic: return .mThreeBarM
        case .hexagonal: return .sixOverMmm
        case .monoclinic: return .twoOverM
        case .identity: return nil
        }
    }

    private static let cubicKit = CrystalOrientationSymmetry(laueClass: .mThreeBarM)
    private static let hexagonalKit = CrystalOrientationSymmetry(laueClass: .sixOverMmm)
    private static let monoclinicKit = CrystalOrientationSymmetry(laueClass: .twoOverM)

    private var kit: CrystalOrientationSymmetry? {
        switch self {
        case .cubic: return Self.cubicKit
        case .hexagonal: return Self.hexagonalKit
        case .monoclinic: return Self.monoclinicKit
        case .identity: return nil
        }
    }

    /// The representative of `S * matrix` with the smallest rotation angle (the kit's rule), and that angle. A matrix that
    /// is not a proper rotation (the kit refuses it) comes back unreduced with angle 0; the matcher only passes rotations.
    package func reduce(_ matrix: simd_double3x3) ->
        (matrix: simd_double3x3, disorientationRad: Float) {
        guard let kit else {
            let rotation = simd_transpose(matrix)
            let cosine = min(1, max(-1, (simd_trace(rotation) - 1) / 2))
            return (matrix, Float(acos(cosine)))
        }
        return (try? kit.reduce(matrix)) ?? (matrix, 0)
    }

    package func sampleFundamentalZone(count: Int) -> [SIMD3<Double>] {
        guard let kit else {
            guard count > 0 else { return [] }
            let golden = Double.pi * (3 - 5.0.squareRoot())
            return (0..<count).map { index in
                let z = (Double(index) + 0.5) / Double(count)
                let radius = max(0, 1 - z * z).squareRoot()
                return SIMD3(radius * cos(golden * Double(index)),
                             radius * sin(golden * Double(index)), z)
            }
        }
        // The kit refuses counts outside 0...4096 (before allocating); no caller asks for more.
        return (try? kit.sampleFundamentalZone(count: count)) ?? []
    }

    package func ipfColor(direction: SIMD3<Double>) -> SIMD3<Float> {
        guard let kit else {
            let value = simd_normalize(direction)
            return SIMD3(Float(abs(value.x)), Float(abs(value.y)), Float(abs(value.z)))
        }
        // A zero or non-finite pole has no colour (the kit refuses it): the key's [001] corner colour stands in, the same
        // stand-in the former app reduction gave (it folded such a pole to [001]).
        return (try? kit.ipfColor(direction: direction, key: .native))
            ?? ((try? kit.ipfColor(direction: [0, 0, 1], key: .native)) ?? SIMD3(1, 0, 0))
    }

    /// The 6/mmm key triangle's three corners: the legend and the test read this table. The frame is py4DSTEM's
    /// (`UnitCell.realLattice`: a along +x), so azimuth 0 is the a-axis [2-1-10] and azimuth 30 deg is [10-10]. The
    /// pre-2026-09-30 labels had the two prismatic corners swapped (Gate D, open-items 2026-09-11); the colours were
    /// never changed, only what they are called.
    package static let hexagonalKeyCorners: [HexagonalKeyCorner] = [
        HexagonalKeyCorner(direction: SIMD3(0, 0, 1), label: "0001", color: SIMD3(1, 0, 0)),
        HexagonalKeyCorner(direction: SIMD3(1, 0, 0), label: "2-1-10", color: SIMD3(0, 1, 0)),
        HexagonalKeyCorner(direction: SIMD3(cos(.pi / 6), sin(.pi / 6), 0), label: "10-10",
                           color: SIMD3(0, 0, 1)),
    ]
}

package nonisolated struct OrientationMap {
    package let width: Int
    package let height: Int
    package let matchingBackend: ACOMMatchingBackend
    package let symmetry: ACOMCrystalSymmetry
    package let templateCount: Int
    package var results: [OrientationResult]

    package init(width: Int, height: Int, matchingBackend: ACOMMatchingBackend = .cpu,
         symmetry: ACOMCrystalSymmetry = .cubic, templateCount: Int = 0) {
        self.width = width
        self.height = height
        self.matchingBackend = matchingBackend
        self.symmetry = symmetry
        self.templateCount = templateCount
        self.results = Array(repeating: .empty, count: width * height)
    }

    package subscript(x: Int, y: Int) -> OrientationResult {
        get { results[y * width + x] }
        set { results[y * width + x] = newValue }
    }

    // The read-out arithmetic (Euler text, reliability gate, matched fraction, the scalar planes and the IPF-Z bytes with
    // the low-reliability mask) is DiffractoKit's `OrientationMapAnalysis` since 0.8.1; these members wrap it in the app's
    // image types. An unmatched position (`templateIndex < 0`) is never given a number.

    /// The Euler angles at a scan position, formatted for a read-out, or nil when the position is outside the map or
    /// carries no match (an unindexed position has an `euler` of (0, 0, 0), which would otherwise read as a plausible
    /// "0.0°, 0.0°, 0.0°").
    package func eulerText(x: Int, y: Int) -> String? {
        OrientationMapAnalysis.eulerText(results: results, width: width, height: height, x: x, y: y)
    }

    private func plane(_ pixels: [Float]) -> FloatImage { FloatImage(width: width, height: height, pixels: pixels) }

    package var reliabilityImage: FloatImage { plane(OrientationMapAnalysis.reliabilityPlane(results)) }
    package var scoreImage: FloatImage { plane(OrientationMapAnalysis.scorePlane(results)) }
    /// In-plane rotation angle at each position, in [0, 1) (radians / 2π), for a cyclic colormap.
    package var inPlaneAngleImage: FloatImage { plane(OrientationMapAnalysis.inPlaneAnglePlane(results)) }
    /// Cyclic φ₁ and φ₂ are wrapped to [0,1); middle Φ spans [0,1] (Φ / π).
    package var phi1Image: FloatImage { plane(OrientationMapAnalysis.phi1Plane(results)) }
    package var phi2Image: FloatImage { plane(OrientationMapAnalysis.phi2Plane(results)) }
    package var PhiImage: FloatImage { plane(OrientationMapAnalysis.PhiPlane(results)) }
    package var symmetryDisorientationImage: FloatImage {
        plane(OrientationMapAnalysis.symmetryDisorientationPlane(results))
    }

    /// Symmetry-specific inverse-pole-figure color for sample Z (beam).
    package var ipfZImage: RGBAImage { ipfZImage(maskingReliabilityBelow: nil) }

    /// The reliability value below which the given fraction of MATCHED positions falls (0.1 gives the 10th percentile).
    /// Nil when nothing matched. The default confidence gate for the IPF map.
    package func reliabilityThreshold(percentile fraction: Float) -> Float? {
        OrientationMapAnalysis.reliabilityThreshold(results: results, percentile: fraction)
    }

    /// Fraction of matched positions at or above `threshold`; nil when nothing matched.
    package func fractionOfMatchedPositions(withReliabilityAtLeast threshold: Float) -> Float? {
        OrientationMapAnalysis.fractionOfMatched(results: results, reliabilityAtLeast: threshold)
    }

    /// IPF-Z with every matched position whose reliability falls below `threshold` drawn neutral grey instead of a
    /// saturated orientation colour (a low-confidence match must not read as a textured polycrystal). Unmatched positions
    /// stay black. The colour key is the map's `symmetry`.
    package func ipfZImage(maskingReliabilityBelow threshold: Float?) -> RGBAImage {
        RGBAImage(width: width, height: height,
                  rgba: OrientationMapAnalysis.ipfZRGBA(results: results, maskingReliabilityBelow: threshold,
                                                        color: { symmetry.ipfColor(direction: $0) }))
    }
}

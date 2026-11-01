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

/// The lab frame of the Euler angles an ACOM map reports: py4DSTEM's (f050d207).
///
/// py4DSTEM's orientation matrix G (lab to crystal: its columns are the lab axes in crystal coordinates) has lab x along
/// the detector's first axis, the rows (py4DSTEM qx, `crystal_ACOM.py` `qphi = arctan2(qy, qx)`), y along the columns
/// (qy) and z = x cross y. The kit's matcher measures azimuths in the app's detector frame, x along the columns and y along
/// the rows, so its matrix is in a frame with x and y swapped and z reversed (still right-handed): G_py4DSTEM =
/// G_matcher * F, F the half turn about the in-plane diagonal. Measured on the public Al-Mg-Si demo against py4DSTEM's
/// `match_single_pattern` on the same peaks: 50.3 deg apart on grain C [111] (median, after the crystal's symmetry) without
/// F, 0.30 deg with it; no other relabelling of the axes comes within 9 deg.
///
/// The angles are SciPy `Rotation.from_matrix(G.T).as_euler("zxz")` of that G (`EulerAngles`), what py4DSTEM's
/// `orientation_map_to_orix_CrystalMap` computes; in Bunge's notation (orix's default `from_euler`, lab to crystal) the
/// same orientation is (phi2, Phi, phi1), the triple reversed.
package nonisolated enum ACOMEulerFrame: Equatable {
    /// Angles in py4DSTEM's frame (every map since 2026-10-31).
    case py4DSTEM
    /// A product written before 2026-10-31 (no `provenanceKey`): the matcher's frame; `py4DSTEM(fromMatcher:)` converts it.
    case matcherBefore20261031
    /// A value this build does not know.
    case unknown

    /// The provenance key naming the frame, and its value.
    package static let provenanceKey = "euler_frame"
    package static let py4DSTEMMarker = "py4DSTEM"

    /// What the three angles are, for the products' and the bundle's metadata.
    package static let conventionText =
        "radians; SciPy Rotation.from_matrix(G.T).as_euler('zxz') of the py4DSTEM orientation matrix G (lab to crystal), as py4DSTEM computes; in Bunge (lab to crystal, orix from_euler default) the orientation is (phi2, Phi, phi1)"
    package static let labFrameText =
        "py4DSTEM detector frame: x along the detector rows (qx), y along the columns (qy), z = x cross y; no R-Q rotation applied"
    /// py4DSTEM's own orix export (`orientation_map_to_orix_CrystalMap`) passes the triple to `from_euler(..., "crystal2lab")`,
    /// which is not G but diag(1, -1, 1) G diag(1, -1, 1), a half turn about y on the crystal side and on the lab side (orix
    /// 0.15.0 and SciPy 1.18.1, 500 random G, 9e-16; the Bunge reading (phi2, Phi, phi1) is G to the same 9e-16).
    package static let orixText =
        "orix Rotation.from_euler([phi2, Phi, phi1]) is G; Rotation.from_euler([phi1, Phi, phi2], direction='crystal2lab') reproduces py4DSTEM's orientation_map_to_orix_CrystalMap, which is not G"
    package static let scanAxesText =
        "maps are scan rows by scan columns: py4DSTEM Rx by Ry; in py4DSTEM's orix export (transpose_xy) orix x is the scan row"

    /// The frame of a product's angles from its provenance.
    package static func frame(ofProvenance provenance: [String: String]) -> ACOMEulerFrame {
        switch provenance[provenanceKey] {
        case nil: return .matcherBefore20261031
        case py4DSTEMMarker?: return .py4DSTEM
        default: return .unknown
        }
    }

    /// F: py4DSTEM lab coordinates to the matcher's (x and y swapped, z reversed; its own inverse, determinant 1).
    package static let py4DSTEMFromMatcher = simd_double3x3(rows: [
        SIMD3(0, 1, 0), SIMD3(1, 0, 0), SIMD3(0, 0, -1),
    ])

    /// The matcher's angles in py4DSTEM's frame: G * F, reduced to the symmetry's fundamental zone again (the
    /// representative with the smallest rotation angle, the kit's rule), with that representative's rotation angle.
    package static func py4DSTEM(fromMatcher euler: EulerAngles, symmetry: ACOMCrystalSymmetry)
        -> (euler: EulerAngles, disorientationRad: Float) {
        let reduced = symmetry.reduce(euler.py4DSTEMOrientationMatrix * py4DSTEMFromMatcher)
        return (EulerAngles(py4DSTEMOrientationMatrix: reduced.matrix), reduced.disorientationRad)
    }

    /// A matched result with its angles and FZ angle in py4DSTEM's frame; template, in-plane angle, mirror flag and scores
    /// stay the matcher's (they describe the template match on the detector, and the overlays draw from them). An
    /// unmatched result is returned as it is.
    package static func py4DSTEM(fromMatcher result: OrientationResult, symmetry: ACOMCrystalSymmetry) -> OrientationResult {
        guard result.templateIndex >= 0 else { return result }
        var out = result
        let converted = py4DSTEM(fromMatcher: result.euler, symmetry: symmetry)
        out.euler = converted.euler
        out.symmetryDisorientationRad = converted.disorientationRad
        return out
    }
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
    /// 1 at a mirrored match, 0 elsewhere (`OrientationMapAnalysis.mirroredPlane`): the plane the in-plane angle needs to be read with.
    package var mirroredImage: FloatImage { plane(OrientationMapAnalysis.mirroredPlane(results).map(Float.init)) }
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

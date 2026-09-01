import Foundation
import simd

nonisolated enum ACOMMatchingBackend: String, Sendable, Equatable, CaseIterable, Identifiable {
    case automatic = "Automatic"
    case cpu = "Accelerate CPU"
    case metal = "Metal GPU"

    var id: String { rawValue }
}

/// py4DSTEM/orix-compatible Bunge Euler angles in radians. py4DSTEM stores an
/// orientation matrix whose columns are lab x/y/z in crystal coordinates,
/// then exports `matrix.T` through SciPy's extrinsic `zxz` decomposition.
nonisolated struct EulerAngles: Equatable, Hashable {
    var phi1: Float
    var Phi: Float
    var phi2: Float

    init(phi1: Float, Phi: Float, phi2: Float) {
        self.phi1 = phi1
        self.Phi = Phi
        self.phi2 = phi2
    }

    static let zero = EulerAngles(phi1: 0, Phi: 0, phi2: 0)

    /// Decompose py4DSTEM's orientation-matrix convention exactly: transpose
    /// crystal-coordinate lab axes to crystal→lab, then extrinsic zxz. At
    /// gimbal lock, match SciPy by folding the observable rotation into phi1
    /// and setting phi2 to zero.
    init(py4DSTEMOrientationMatrix matrix: simd_double3x3) {
        let r = simd_transpose(matrix)
        let r22 = min(1.0, max(-1.0, r.columns.2.z))
        let middle = acos(r22)
        let sine = sin(middle)
        let first: Double
        let third: Double
        if abs(sine) > 1e-8 {
            first = atan2(r.columns.0.z, r.columns.1.z)   // atan2(R20,R21)
            third = atan2(r.columns.2.x, -r.columns.2.y) // atan2(R02,-R12)
        } else if r22 > 0 {
            first = atan2(r.columns.0.y, r.columns.0.x)   // Phi = 0: phi1+phi2
            third = 0
        } else {
            first = atan2(-r.columns.0.y, r.columns.0.x)  // Phi = pi: phi1-phi2
            third = 0
        }
        self.phi1 = Float(Self.signedAngle(first))
        self.Phi = Float(middle)
        self.phi2 = Float(Self.signedAngle(third))
    }

    /// Crystal→lab rotation matrix corresponding to SciPy `from_euler("zxz")`.
    var crystalToLabMatrix: simd_double3x3 {
        let a = Double(phi1), b = Double(Phi), c = Double(phi2)
        let ca = cos(a), sa = sin(a), cb = cos(b), sb = sin(b)
        let cc = cos(c), sc = sin(c)
        return simd_double3x3(columns: (
            SIMD3(cc * ca - sc * cb * sa,
                  sc * ca + cc * cb * sa,
                  sb * sa),
            SIMD3(-cc * sa - sc * cb * ca,
                  -sc * sa + cc * cb * ca,
                  sb * ca),
            SIMD3(sc * sb, -cc * sb, cb)
        ))
    }

    var py4DSTEMOrientationMatrix: simd_double3x3 {
        simd_transpose(crystalToLabMatrix)
    }

    private static func signedAngle(_ value: Double) -> Double {
        var angle = value.truncatingRemainder(dividingBy: 2 * .pi)
        if angle <= -.pi { angle += 2 * .pi }
        if angle > .pi { angle -= 2 * .pi }
        return abs(angle) < 1e-12 ? 0 : angle
    }

    var degrees: (Float, Float, Float) {
        let scale = Float(180.0 / Double.pi)
        return (phi1 * scale, Phi * scale, phi2 * scale)
    }
}

/// Orientation-matrix construction shared by the plan, matcher, and harness.
/// Columns are detector x, detector y, and beam z expressed in crystal axes,
/// matching py4DSTEM's `Orientation.matrix` convention.
nonisolated enum ACOMOrientation {
    static func detectorBasis(zoneAxis n: SIMD3<Double>) -> simd_double3x3 {
        let reference: SIMD3<Double> = abs(n.x) < 0.9 ? [1, 0, 0] : [0, 1, 0]
        let e1 = simd_normalize(simd_cross(n, reference))
        let e2 = simd_cross(n, e1)
        return simd_double3x3(columns: (e1, e2, n))
    }

    /// py4DSTEM applies this in-plane matrix on the right of the zone basis.
    static func matrix(detectorBasis basis: simd_double3x3,
                       inPlaneAngle angle: Float) -> simd_double3x3 {
        let c = cos(Double(angle)), s = sin(Double(angle))
        let inPlane = simd_double3x3(columns: (
            SIMD3(c, -s, 0), SIMD3(s, c, 0), SIMD3(0, 0, 1)
        ))
        return basis * inPlane
    }
}

/// Cubic crystal-symmetry operations and the m-3m inverse-pole-figure color
/// key used for ACOM results. py4DSTEM stores lab axes in the columns of the
/// orientation matrix, so an equivalent cubic orientation is `S * matrix`.
nonisolated enum CubicOrientationSymmetry {
    /// The 24 proper signed-permutation matrices of the cubic rotation group.
    static let operators: [simd_double3x3] = {
        let permutations = [
            [0, 1, 2], [0, 2, 1], [1, 0, 2],
            [1, 2, 0], [2, 0, 1], [2, 1, 0],
        ]
        var result: [simd_double3x3] = []
        for permutation in permutations {
            for sx in [-1.0, 1.0] {
                for sy in [-1.0, 1.0] {
                    for sz in [-1.0, 1.0] {
                        let signs = [sx, sy, sz]
                        var rows = Array(repeating: Array(repeating: 0.0, count: 3), count: 3)
                        for row in 0..<3 { rows[row][permutation[row]] = signs[row] }
                        let candidate = simd_double3x3(rows: rows)
                        if simd_determinant(candidate) > 0.5 { result.append(candidate) }
                    }
                }
            }
        }
        return result
    }()

    /// Select one deterministic representative from the 24 equivalent
    /// orientations. The chosen representative has the smallest rotation from
    /// identity; canonical quaternion components break exact ties.
    static func reduce(_ matrix: simd_double3x3) ->
        (matrix: simd_double3x3, disorientationRad: Float) {
        var bestMatrix = matrix
        var bestKey: [Double]?
        var bestAngle = Double.pi
        for symmetry in operators {
            let candidate = symmetry * matrix
            let q = canonicalQuaternion(simd_quatd(simd_transpose(candidate)))
            let key = [-q.w, q.x, q.y, q.z]
            if bestKey == nil || lexicographicallyPrecedes(key, bestKey!) {
                bestKey = key
                bestMatrix = candidate
                bestAngle = 2 * acos(min(1, max(0, q.w)))
            }
        }
        return (bestMatrix, Float(bestAngle))
    }

    /// Fold a direction into the cubic m-3m IPF sector z ≥ x ≥ y ≥ 0.
    static func reduceDirection(_ direction: SIMD3<Double>) -> SIMD3<Double> {
        let length = simd_length(direction)
        guard length.isFinite, length > 1e-15 else { return [0, 0, 1] }
        let values = [abs(direction.x), abs(direction.y), abs(direction.z)].sorted()
        return simd_normalize(SIMD3(values[1], values[0], values[2]))
    }

    /// Deterministic, approximately uniform sampling of the cubic m-3m
    /// direction fundamental zone [001]-[101]-[111]. A dense Fibonacci sphere
    /// is folded by symmetry, then spherical farthest-point selection avoids
    /// spending templates on symmetry-equivalent beam directions.
    static func sampleFundamentalZone(count: Int) -> [SIMD3<Double>] {
        guard count > 0 else { return [] }
        let vertices = [
            SIMD3<Double>(0, 0, 1),
            simd_normalize(SIMD3<Double>(1, 0, 1)),
            simd_normalize(SIMD3<Double>(1, 1, 1)),
        ]
        if count <= vertices.count { return Array(vertices.prefix(count)) }

        let candidateCount = max(128, count * 12)
        let golden = Double.pi * (3 - 5.0.squareRoot())
        var candidates: [SIMD3<Double>] = []
        candidates.reserveCapacity(candidateCount)
        for index in 0..<candidateCount {
            let z = 1 - 2 * (Double(index) + 0.5) / Double(candidateCount)
            let radius = max(0, 1 - z * z).squareRoot()
            let azimuth = golden * Double(index)
            candidates.append(reduceDirection(SIMD3(
                radius * cos(azimuth), radius * sin(azimuth), z
            )))
        }

        var selected = vertices
        var minimumChord = candidates.map { candidate in
            vertices.map { 1 - simd_dot(candidate, $0) }.min() ?? 0
        }
        while selected.count < count {
            guard let best = minimumChord.indices.max(by: {
                minimumChord[$0] < minimumChord[$1]
            }) else { break }
            let next = candidates[best]
            selected.append(next)
            for index in candidates.indices {
                minimumChord[index] = min(
                    minimumChord[index], 1 - simd_dot(candidates[index], next)
                )
            }
            minimumChord[best] = -.infinity
        }
        return selected
    }

    /// EDAX/TSL-style cubic IPF color, numerically aligned with orix's m-3m
    /// direction color key. Pure red/green/blue denote [001]/[101]/[111].
    static func ipfColor(direction: SIMD3<Double>) -> SIMD3<Float> {
        let v = reduceDirection(direction)
        let azimuth = correctedAzimuth(rawAzimuth(v))

        let vCenterNormal = unit(simd_cross(v, sectorCenter))
        var radial = Double.infinity
        for normal in sectorNormals {
            let boundary = unit(simd_cross(vCenterNormal, normal))
            let numerator = vectorAngle(-v, boundary)
            let denominator = vectorAngle(-sectorCenter, boundary)
            let ratio = numerator / denominator
            radial = min(radial, ratio.isFinite ? ratio : 1)
        }
        if !radial.isFinite { radial = 1 }
        return hslToRGB(hue: azimuth / (2 * .pi), lightness: 0.5 + 0.5 * radial)
    }

    private static let sectorCenter = simd_normalize(SIMD3(
        0.4281523501333333, 0.19245008973333333, 0.7614856834666667
    ))
    private static let sectorVertices = [
        simd_normalize(SIMD3(1.0, 1.0, 1.0)),
        simd_normalize(SIMD3(1.0, 0.0, 1.0)),
        SIMD3(0.0, 0.0, 1.0),
    ]
    private static let sectorNormals = [
        SIMD3(1.0, -1.0, 0.0),
        SIMD3(-1.0, 0.0, 1.0),
        SIMD3(0.0, 1.0, 0.0),
    ]

    /// A one-time equalized angular lookup around the asymmetric spherical
    /// triangle. This is the polar-coordinate construction used by MTEX/TSL.
    private static let azimuthLookup: [Double] = {
        let count = 1000
        let rawAngles = (0..<count).map { 2 * Double.pi * Double($0) / Double(count - 1) }
        let rx = SIMD3(0.0, 0.0, 1.0) - sectorCenter
        let tangent = unit(simd_cross(unit(rx - simd_dot(rx, sectorCenter) * sectorCenter),
                                      sectorCenter))
        var distances = [Double]()
        distances.reserveCapacity(count - 1)
        for angle in rawAngles.dropLast() {
            let rotated = rodrigues(tangent, axis: sectorCenter, angle: angle)
            let boundaryDistances = sectorNormals.map {
                vectorAngle(simd_cross($0, rotated), sectorCenter)
            }
            distances.append(boundaryDistances.min() ?? 0)
        }

        var cuts = sectorVertices.map { rawAzimuth($0) }.sorted().map {
            Int((Double(count) * $0 / (2 * .pi)).rounded())
        }
        if cuts.first.map({ $0 < 10 }) == true { cuts.removeFirst() }
        if cuts.count == 2 {
            for range in [0..<cuts[0], cuts[0]..<cuts[1], cuts[1]..<distances.count] {
                let sum = range.reduce(0.0) { $0 + distances[$1] }
                if sum > 0 {
                    let scale = 3 / sum
                    for index in range { distances[index] *= scale }
                }
            }
        }
        let total = distances.reduce(0, +)
        var cumulative = [0.0]
        cumulative.reserveCapacity(count)
        var sum = 0.0
        for distance in distances {
            sum += distance
            cumulative.append(2 * .pi * sum / total)
        }
        return cumulative
    }()

    private static func rawAzimuth(_ v: SIMD3<Double>) -> Double {
        let initial = SIMD3(0.0, 0.0, 1.0) - sectorCenter
        let x = unit(initial - simd_dot(initial, sectorCenter) * sectorCenter)
        let y = unit(simd_cross(sectorCenter, x))
        let distance = unit(v - sectorCenter)
        guard simd_length_squared(distance) > 0 else { return 0 }
        let angle = atan2(simd_dot(y, distance), simd_dot(x, distance))
        return angle < 0 ? angle + 2 * .pi : angle
    }

    private static func correctedAzimuth(_ angle: Double) -> Double {
        let position = max(0, min(Double(azimuthLookup.count - 1),
                                  angle / (2 * .pi) * Double(azimuthLookup.count - 1)))
        let lower = Int(position.rounded(.down))
        let upper = min(lower + 1, azimuthLookup.count - 1)
        let fraction = position - Double(lower)
        return azimuthLookup[lower] * (1 - fraction) + azimuthLookup[upper] * fraction
    }

    private static func canonicalQuaternion(_ quaternion: simd_quatd) ->
        (w: Double, x: Double, y: Double, z: Double) {
        var values = (quaternion.real, quaternion.imag.x, quaternion.imag.y, quaternion.imag.z)
        if values.0 < 0 || (abs(values.0) < 1e-14 && firstNonzeroIsNegative([values.1, values.2, values.3])) {
            values = (-values.0, -values.1, -values.2, -values.3)
        }
        return (values.0, values.1, values.2, values.3)
    }

    private static func firstNonzeroIsNegative(_ values: [Double]) -> Bool {
        for value in values where abs(value) > 1e-14 { return value < 0 }
        return false
    }

    private static func lexicographicallyPrecedes(_ lhs: [Double], _ rhs: [Double]) -> Bool {
        for (a, b) in zip(lhs, rhs) where abs(a - b) > 1e-13 { return a < b }
        return false
    }

    private static func unit(_ value: SIMD3<Double>) -> SIMD3<Double> {
        let length = simd_length(value)
        return length > 1e-15 && length.isFinite ? value / length : .zero
    }

    private static func vectorAngle(_ lhs: SIMD3<Double>, _ rhs: SIMD3<Double>) -> Double {
        let a = unit(lhs), b = unit(rhs)
        guard simd_length_squared(a) > 0, simd_length_squared(b) > 0 else { return .nan }
        return acos(min(1, max(-1, simd_dot(a, b))))
    }

    private static func rodrigues(_ vector: SIMD3<Double>, axis: SIMD3<Double>,
                                  angle: Double) -> SIMD3<Double> {
        let c = cos(angle), s = sin(angle)
        return vector * c + simd_cross(axis, vector) * s
            + axis * simd_dot(axis, vector) * (1 - c)
    }

    private static func hslToRGB(hue: Double, lightness: Double) -> SIMD3<Float> {
        let h = hue - floor(hue)
        let l2 = 2 * lightness
        let s2 = l2 <= 1 ? l2 : 2 - l2
        let saturation = l2 + s2 > 0 ? 2 * s2 / (l2 + s2) : 0
        let value = (l2 + s2) / 2
        let sector = h * 6
        let index = Int(floor(sector)) % 6
        let f = sector - floor(sector)
        let p = value * (1 - saturation)
        let q = value * (1 - saturation * f)
        let t = value * (1 - saturation * (1 - f))
        let rgb: SIMD3<Double>
        switch index {
        case 0: rgb = [value, t, p]
        case 1: rgb = [q, value, p]
        case 2: rgb = [p, value, t]
        case 3: rgb = [p, q, value]
        case 4: rgb = [t, p, value]
        default: rgb = [value, p, q]
        }
        return SIMD3(Float(rgb.x), Float(rgb.y), Float(rgb.z))
    }
}

/// Proper rotational subgroup of the hexagonal 6/mmm Laue class (D6): six
/// rotations about c plus six twofold rotations about basal-plane axes. The
/// diffraction/Friedel direction key folds the resulting sector to
/// `[0001]-[10-10]-[11-20]`.
nonisolated enum HexagonalOrientationSymmetry {
    static let operators: [simd_double3x3] = {
        var result: [simd_double3x3] = []
        for index in 0..<6 {
            let angle = Double(index) * .pi / 3
            let c = cos(angle), s = sin(angle)
            result.append(simd_double3x3(rows: [
                [c, -s, 0], [s, c, 0], [0, 0, 1],
            ]))
        }
        for index in 0..<6 {
            let angle = Double(index) * .pi / 6
            let x = cos(angle), y = sin(angle)
            result.append(simd_double3x3(rows: [
                [2 * x * x - 1, 2 * x * y, 0],
                [2 * x * y, 2 * y * y - 1, 0],
                [0, 0, -1],
            ]))
        }
        return result
    }()

    static func reduce(_ matrix: simd_double3x3) ->
        (matrix: simd_double3x3, disorientationRad: Float) {
        var bestMatrix = matrix
        var bestKey: [Double]?
        var bestAngle = Double.pi
        for symmetry in operators {
            let candidate = symmetry * matrix
            var quaternion = simd_quatd(simd_transpose(candidate))
            if quaternion.real < 0 { quaternion = simd_quatd(
                real: -quaternion.real, imag: -quaternion.imag
            ) }
            let key = [-quaternion.real, quaternion.imag.x,
                       quaternion.imag.y, quaternion.imag.z]
            if bestKey == nil || key.lexicographicallyPrecedes(bestKey!) {
                bestKey = key
                bestMatrix = candidate
                bestAngle = 2 * acos(min(1, max(0, quaternion.real)))
            }
        }
        return (bestMatrix, Float(bestAngle))
    }

    static func reduceDirection(_ direction: SIMD3<Double>) -> SIMD3<Double> {
        let length = simd_length(direction)
        guard length.isFinite, length > 1e-15 else { return [0, 0, 1] }
        var value = direction / length
        if value.z < 0 { value = -value }
        let basal = hypot(value.x, value.y)
        var azimuth = atan2(value.y, value.x).truncatingRemainder(dividingBy: .pi / 3)
        if azimuth < 0 { azimuth += .pi / 3 }
        if azimuth > .pi / 6 { azimuth = .pi / 3 - azimuth }
        return simd_normalize(SIMD3(
            basal * cos(azimuth), basal * sin(azimuth), value.z
        ))
    }

    static func sampleFundamentalZone(count: Int) -> [SIMD3<Double>] {
        guard count > 0 else { return [] }
        let vertices = [
            SIMD3<Double>(0, 0, 1),
            SIMD3<Double>(1, 0, 0),
            SIMD3<Double>(cos(.pi / 6), sin(.pi / 6), 0),
        ]
        if count <= vertices.count { return Array(vertices.prefix(count)) }
        let candidateCount = max(192, count * 16)
        let golden = Double.pi * (3 - 5.0.squareRoot())
        var candidates: [SIMD3<Double>] = []
        for index in 0..<candidateCount {
            let z = 1 - 2 * (Double(index) + 0.5) / Double(candidateCount)
            let radius = max(0, 1 - z * z).squareRoot()
            candidates.append(reduceDirection(SIMD3(
                radius * cos(golden * Double(index)),
                radius * sin(golden * Double(index)), z
            )))
        }
        var selected = vertices
        var minimumChord = candidates.map { candidate in
            vertices.map { 1 - simd_dot(candidate, $0) }.min() ?? 0
        }
        while selected.count < count {
            guard let best = minimumChord.indices.max(by: {
                minimumChord[$0] < minimumChord[$1]
            }) else { break }
            let next = candidates[best]
            selected.append(next)
            for index in candidates.indices {
                minimumChord[index] = min(
                    minimumChord[index], 1 - simd_dot(candidates[index], next)
                )
            }
            minimumChord[best] = -.infinity
        }
        return selected
    }

    /// Explicit native 6/mmm IPF key: [0001] red, [10-10] green, [11-20]
    /// blue. Square-root intensity and max normalization match conventional
    /// IPF saturation while keeping the policy deterministic and dependency-free.
    static func ipfColor(direction: SIMD3<Double>) -> SIMD3<Float> {
        let value = reduceDirection(direction)
        let tilt = min(1, max(0, acos(min(1, max(0, value.z))) / (.pi / 2)))
        let azimuth = min(.pi / 6, max(0, atan2(value.y, value.x)))
        let fraction = azimuth / (.pi / 6)
        var rgb = SIMD3<Double>(
            sqrt(max(0, 1 - tilt)),
            sqrt(max(0, tilt * (1 - fraction))),
            sqrt(max(0, tilt * fraction))
        )
        let maximum = max(rgb.x, rgb.y, rgb.z)
        if maximum > 0 { rgb /= maximum }
        return SIMD3(Float(rgb.x), Float(rgb.y), Float(rgb.z))
    }
}

/// Explicit symmetry policy for orientation reporting. The current crystal
/// presets and custom editor are cubic; `.identity` is the safe fallback for
/// future non-cubic structures until their point groups are implemented.
nonisolated enum ACOMCrystalSymmetry: String, Sendable, Equatable {
    case cubic
    case hexagonal
    case identity

    var displayName: String {
        switch self {
        case .cubic: return "Cubic m-3m"
        case .hexagonal: return "Hexagonal 6/mmm"
        case .identity: return "Unreduced"
        }
    }

    func reduce(_ matrix: simd_double3x3) ->
        (matrix: simd_double3x3, disorientationRad: Float) {
        switch self {
        case .cubic:
            return CubicOrientationSymmetry.reduce(matrix)
        case .hexagonal:
            return HexagonalOrientationSymmetry.reduce(matrix)
        case .identity:
            let rotation = simd_transpose(matrix)
            let cosine = min(1, max(-1, (simd_trace(rotation) - 1) / 2))
            return (matrix, Float(acos(cosine)))
        }
    }


    func sampleFundamentalZone(count: Int) -> [SIMD3<Double>] {
        switch self {
        case .cubic: return CubicOrientationSymmetry.sampleFundamentalZone(count: count)
        case .hexagonal: return HexagonalOrientationSymmetry.sampleFundamentalZone(count: count)
        case .identity:
            guard count > 0 else { return [] }
            let golden = Double.pi * (3 - 5.0.squareRoot())
            return (0..<count).map { index in
                let z = (Double(index) + 0.5) / Double(count)
                let radius = max(0, 1 - z * z).squareRoot()
                return SIMD3(radius * cos(golden * Double(index)),
                             radius * sin(golden * Double(index)), z)
            }
        }
    }

    func ipfColor(direction: SIMD3<Double>) -> SIMD3<Float> {
        switch self {
        case .cubic: return CubicOrientationSymmetry.ipfColor(direction: direction)
        case .hexagonal: return HexagonalOrientationSymmetry.ipfColor(direction: direction)
        case .identity:
            let value = simd_normalize(direction)
            return SIMD3(Float(abs(value.x)), Float(abs(value.y)), Float(abs(value.z)))
        }
    }
}

private extension simd_double3x3 {
    nonisolated init(rows: [[Double]]) {
        self.init(columns: (
            SIMD3(rows[0][0], rows[1][0], rows[2][0]),
            SIMD3(rows[0][1], rows[1][1], rows[2][1]),
            SIMD3(rows[0][2], rows[1][2], rows[2][2])
        ))
    }
}

nonisolated struct OrientationResult: Equatable {
    /// Index into the template library (zone axis) for the best match.
    var templateIndex: Int
    var euler: EulerAngles
    /// Best in-plane rotation angle (radians), from azimuthal correlation.
    var inPlaneAngle: Float = 0
    /// Best normalized cross-correlation score.
    var score: Float
    /// Second-best score, used for reliability.
    var secondScore: Float
    var phaseID: Int
    /// Rotation angle of the deterministic cubic fundamental-zone
    /// representative, useful as a scalar orientation diagnostic.
    var symmetryDisorientationRad: Float = 0

    /// EBSD-style reliability. Higher values indicate a clearer best match.
    var reliability: Float {
        guard score > 0 else { return 0 }
        let value = 1 - (secondScore / score)
        return max(0, min(1, value))
    }

    static let empty = OrientationResult(
        templateIndex: -1,
        euler: .zero,
        inPlaneAngle: 0,
        score: 0,
        secondScore: 0,
        phaseID: -1
    )
}

nonisolated struct OrientationMap {
    let width: Int
    let height: Int
    let matchingBackend: ACOMMatchingBackend
    let symmetry: ACOMCrystalSymmetry
    let templateCount: Int
    var results: [OrientationResult]

    init(width: Int, height: Int, matchingBackend: ACOMMatchingBackend = .cpu,
         symmetry: ACOMCrystalSymmetry = .cubic, templateCount: Int = 0) {
        self.width = width
        self.height = height
        self.matchingBackend = matchingBackend
        self.symmetry = symmetry
        self.templateCount = templateCount
        self.results = Array(repeating: .empty, count: width * height)
    }

    subscript(x: Int, y: Int) -> OrientationResult {
        get { results[y * width + x] }
        set { results[y * width + x] = newValue }
    }

    var reliabilityImage: FloatImage {
        FloatImage(width: width, height: height, pixels: results.map { $0.reliability })
    }

    var scoreImage: FloatImage {
        FloatImage(width: width, height: height, pixels: results.map { $0.score })
    }

    /// In-plane rotation angle at each position, in [0, 1) (radians / 2π) —
    /// suitable for a cyclic colormap.
    var inPlaneAngleImage: FloatImage {
        let twoPi = Float(2 * Double.pi)
        return FloatImage(width: width, height: height,
                          pixels: results.map { $0.inPlaneAngle / twoPi })
    }

    /// Cyclic φ₁ and φ₂ are wrapped to [0,1); middle Φ spans [0,π].
    var phi1Image: FloatImage { cyclicEulerImage { $0.euler.phi1 } }
    var phi2Image: FloatImage { cyclicEulerImage { $0.euler.phi2 } }
    var PhiImage: FloatImage {
        let pi = Float.pi
        return FloatImage(width: width, height: height,
                          pixels: results.map { max(0, min(1, $0.euler.Phi / pi)) })
    }

    var symmetryDisorientationImage: FloatImage {
        FloatImage(width: width, height: height,
                   pixels: results.map { $0.symmetryDisorientationRad })
    }

    /// Symmetry-specific inverse-pole-figure color for sample Z (beam).
    var ipfZImage: RGBAImage {
        var rgba = [UInt8]()
        rgba.reserveCapacity(results.count * 4)
        for result in results {
            let direction = result.templateIndex >= 0
                ? result.euler.py4DSTEMOrientationMatrix.columns.2
                : SIMD3(0.0, 0.0, 0.0)
            let rgb = result.templateIndex >= 0
                ? symmetry.ipfColor(direction: direction)
                : SIMD3<Float>(repeating: 0)
            rgba.append(UInt8((max(0, min(1, rgb.x)) * 255).rounded()))
            rgba.append(UInt8((max(0, min(1, rgb.y)) * 255).rounded()))
            rgba.append(UInt8((max(0, min(1, rgb.z)) * 255).rounded()))
            rgba.append(255)
        }
        return RGBAImage(width: width, height: height, rgba: rgba)
    }

    private func cyclicEulerImage(_ angle: (OrientationResult) -> Float) -> FloatImage {
        let twoPi = 2 * Float.pi
        return FloatImage(width: width, height: height, pixels: results.map {
            var value = angle($0).truncatingRemainder(dividingBy: twoPi)
            if value < 0 { value += twoPi }
            return value / twoPi
        })
    }
}

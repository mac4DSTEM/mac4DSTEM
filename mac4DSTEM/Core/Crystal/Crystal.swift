//
//  Crystal.swift
//  Role: A crystal-structure model and kinematic diffraction generator — the
//        foundation for ACOM (automated crystal orientation mapping). Port of
//        the lattice + structure-factor math in py4DSTEM's Crystal class
//        (process/diffraction/crystal.py).
//
//  This is the first ACOM building block. It computes:
//   • the real-space lattice matrix from cell parameters (a,b,c,α,β,γ)
//   • the reciprocal lattice via the metric tensor (lat_inv = M⁻¹·lat_real)
//   • all hkl reflections within a scattering-vector cutoff k_max (1/Å)
//   • kinematic structure factors F_hkl = (1/V) Σ f_e(Z,|g|²) e^{2πi g·r}
//     and their intensities |F|²
//
//  Next ACOM steps (separate files): an orientation plan (zone-axis sampling
//  → polar templates) and orientation matching (polar correlation, in-plane
//  angle via 1D FFT). See the architecture notes.
//
//  Units: distances in Å, scattering vectors |g| in Å⁻¹ (no 2π factor, matching
//  py4DSTEM). Structure factors in Å (py4DSTEM "A" convention).
//

import Foundation
import simd

/// One atom in the unit cell.
nonisolated struct AtomSite {
    var z: Int                       // atomic number
    var fractional: SIMD3<Double>    // (x, y, z) fractional coordinates
    var occupancy: Double = 1
}

/// One kinematically-allowed reflection.
nonisolated struct Reflection {
    let h: Int, k: Int, l: Int
    let g: SIMD3<Double>             // reciprocal-space vector (Å⁻¹), Cartesian
    let gLength: Double              // |g| (Å⁻¹)
    let structureFactorRe: Double
    let structureFactorIm: Double
    var intensity: Double           // |F|²
}

nonisolated struct Crystal {

    // Cell parameters.
    let a: Double, b: Double, c: Double
    let alphaDeg: Double, betaDeg: Double, gammaDeg: Double
    let sites: [AtomSite]

    // Derived lattice matrices (rows are lattice vectors).
    let latReal: [SIMD3<Double>]     // real lattice vectors (Å)
    let latInv: [SIMD3<Double>]      // reciprocal lattice vectors (Å⁻¹)
    let volume: Double               // unit-cell volume (Å³)

    // MARK: Construction

    init(a: Double, b: Double, c: Double,
         alphaDeg: Double = 90, betaDeg: Double = 90, gammaDeg: Double = 90,
         sites: [AtomSite]) {
        self.a = a; self.b = b; self.c = c
        self.alphaDeg = alphaDeg; self.betaDeg = betaDeg; self.gammaDeg = gammaDeg
        self.sites = sites

        let alpha = alphaDeg * .pi / 180
        let beta  = betaDeg * .pi / 180
        let gamma = gammaDeg * .pi / 180
        let f = cos(beta) * cos(gamma) - cos(alpha)
        let vol = a * b * c * (1
            + 2 * cos(alpha) * cos(beta) * cos(gamma)
            - cos(alpha) * cos(alpha)
            - cos(beta) * cos(beta)
            - cos(gamma) * cos(gamma)).squareRoot()

        // Real lattice matrix (py4DSTEM convention).
        let real = [
            SIMD3<Double>(a, 0, 0),
            SIMD3<Double>(b * cos(gamma), b * sin(gamma), 0),
            SIMD3<Double>(c * cos(beta), -c * f / sin(gamma), vol / (a * b * sin(gamma))),
        ]
        self.latReal = real
        self.volume = abs(Crystal.determinant(real))

        // Reciprocal lattice: metric = real·realᵀ, lat_inv = metric⁻¹·real.
        let metric = Crystal.gram(real)
        let metricInv = Crystal.invert3x3(metric) ?? Crystal.identity3
        self.latInv = Crystal.matMul(metricInv, real)
    }

    // MARK: Reflections + structure factors

    /// All reflections with |g| ≤ kMax and |F| above `tolerance`, sorted by
    /// increasing |g|. Mirrors calculate_structure_factors.
    func reflections(kMax: Double, tolerance: Double = 1e-4) -> [Reflection] {
        // Shortest reciprocal-lattice direction, to bound the hkl tiling.
        let testDirs: [SIMD3<Double>] = [
            latInv[0], latInv[1], latInv[2],
            latInv[0] + latInv[1], latInv[0] + latInv[2], latInv[1] + latInv[2],
            latInv[0] + latInv[1] + latInv[2],
            latInv[0] - latInv[1] + latInv[2],
            latInv[0] + latInv[1] - latInv[2],
            latInv[0] - latInv[1] - latInv[2],
        ]
        let kMin = testDirs.map { length($0) }.filter { $0 > 1e-9 }.min() ?? kMax
        let numTile = Int((kMax / kMin).rounded(.up))

        var out: [Reflection] = []
        for h in -numTile...numTile {
            for k in -numTile...numTile {
                for l in -numTile...numTile {
                    if h == 0 && k == 0 && l == 0 { continue }
                    // g = h·a* + k·b* + l·c*
                    let g = Double(h) * latInv[0] + Double(k) * latInv[1] + Double(l) * latInv[2]
                    let gLen = length(g)
                    if gLen > kMax { continue }

                    // F_hkl = (1/V) Σ f_e(Z, |g|²) · occ · exp(2πi (h·x+k·y+l·z))
                    let gSq = gLen * gLen
                    var re = 0.0, im = 0.0
                    for site in sites {
                        // Unsupported elements are caught up front by
                        // `unsupportedElements`; 0 here is unreachable in practice.
                        let fe = ScatteringFactors.electronScatteringFactor(z: site.z, gSquared: gSq) ?? 0
                        let phase = 2 * Double.pi * (Double(h) * site.fractional.x
                                                   + Double(k) * site.fractional.y
                                                   + Double(l) * site.fractional.z)
                        re += fe * site.occupancy * cos(phase)
                        im += fe * site.occupancy * sin(phase)
                    }
                    re /= volume; im /= volume
                    let intensity = re * re + im * im
                    if intensity.squareRoot() <= tolerance { continue }

                    out.append(Reflection(h: h, k: k, l: l, g: g, gLength: gLen,
                                          structureFactorRe: re, structureFactorIm: im,
                                          intensity: intensity))
                }
            }
        }
        out.sort { $0.gLength < $1.gLength }
        return out
    }

    /// Atomic numbers in this crystal missing from the scattering-factor
    /// table. Non-empty → structure factors would be silently wrong; callers
    /// must check and fail loudly before generating templates.
    var unsupportedElements: [Int] {
        Array(Set(sites.map(\.z).filter { !ScatteringFactors.isSupported(z: $0) })).sorted()
    }

    // MARK: Presets

    /// Face-centered cubic (4 atoms).
    static func fcc(a: Double, z: Int) -> Crystal {
        Crystal(a: a, b: a, c: a, sites: [
            AtomSite(z: z, fractional: [0, 0, 0]),
            AtomSite(z: z, fractional: [0.5, 0.5, 0]),
            AtomSite(z: z, fractional: [0.5, 0, 0.5]),
            AtomSite(z: z, fractional: [0, 0.5, 0.5]),
        ])
    }

    /// Body-centered cubic (2 atoms).
    static func bcc(a: Double, z: Int) -> Crystal {
        Crystal(a: a, b: a, c: a, sites: [
            AtomSite(z: z, fractional: [0, 0, 0]),
            AtomSite(z: z, fractional: [0.5, 0.5, 0.5]),
        ])
    }

    /// Simple cubic (1 atom).
    static func sc(a: Double, z: Int) -> Crystal {
        Crystal(a: a, b: a, c: a, sites: [AtomSite(z: z, fractional: [0, 0, 0])])
    }

    /// Diamond cubic (8 atoms) — FCC plus a (¼,¼,¼) shifted sublattice.
    static func diamond(a: Double, z: Int) -> Crystal {
        let base: [SIMD3<Double>] = [[0, 0, 0], [0.5, 0.5, 0], [0.5, 0, 0.5], [0, 0.5, 0.5]]
        let shift = SIMD3<Double>(0.25, 0.25, 0.25)
        return Crystal(a: a, b: a, c: a,
                       sites: (base + base.map { $0 + shift }).map { AtomSite(z: z, fractional: $0) })
    }

    /// Hexagonal close-packed primitive cell in the conventional 120° basis.
    static func hcp(a: Double, c: Double, z: Int) -> Crystal {
        Crystal(
            a: a, b: a, c: c,
            alphaDeg: 90, betaDeg: 90, gammaDeg: 120,
            sites: [
                AtomSite(z: z, fractional: [0, 0, 0]),
                AtomSite(z: z, fractional: [2.0 / 3.0, 1.0 / 3.0, 0.5]),
            ]
        )
    }

    /// Cubic structure families offered for user-defined (custom) crystals.
    enum CubicStructure: String, CaseIterable, Identifiable {
        case fcc = "FCC"
        case bcc = "BCC"
        case sc = "Simple cubic"
        case diamond = "Diamond"
        var id: String { rawValue }
    }

    /// Build a single-element cubic crystal for the custom-crystal UI.
    static func cubic(_ structure: CubicStructure, a: Double, z: Int) -> Crystal {
        switch structure {
        case .fcc:     return fcc(a: a, z: z)
        case .bcc:     return bcc(a: a, z: z)
        case .sc:      return sc(a: a, z: z)
        case .diamond: return diamond(a: a, z: z)
        }
    }

    // Named materials (lattice constants in Å).
    static var aluminum: Crystal { fcc(a: 4.0495, z: 13) }
    static var gold: Crystal     { fcc(a: 4.0782, z: 79) }
    static var nickel: Crystal   { fcc(a: 3.5240, z: 28) }
    static var copper: Crystal   { fcc(a: 3.6149, z: 29) }
    static var iron: Crystal     { bcc(a: 2.8665, z: 26) }
    static var silicon: Crystal  { diamond(a: 5.4309, z: 14) }
    static var magnesium: Crystal { hcp(a: 3.2094, c: 5.2108, z: 12) }

    // MARK: - Small linear-algebra helpers (row-vector matrices)

    private static let identity3: [SIMD3<Double>] =
        [[1, 0, 0], [0, 1, 0], [0, 0, 1]]

    /// Gram matrix M·Mᵀ for row-vector matrix M.
    private static func gram(_ m: [SIMD3<Double>]) -> [SIMD3<Double>] {
        [
            SIMD3(dot(m[0], m[0]), dot(m[0], m[1]), dot(m[0], m[2])),
            SIMD3(dot(m[1], m[0]), dot(m[1], m[1]), dot(m[1], m[2])),
            SIMD3(dot(m[2], m[0]), dot(m[2], m[1]), dot(m[2], m[2])),
        ]
    }

    /// A·B for row-vector matrices (rows of the result are rows of A times B).
    private static func matMul(_ aM: [SIMD3<Double>], _ bM: [SIMD3<Double>]) -> [SIMD3<Double>] {
        func row(_ r: SIMD3<Double>) -> SIMD3<Double> {
            r.x * bM[0] + r.y * bM[1] + r.z * bM[2]
        }
        return [row(aM[0]), row(aM[1]), row(aM[2])]
    }

    private static func determinant(_ m: [SIMD3<Double>]) -> Double {
        m[0].x * (m[1].y * m[2].z - m[1].z * m[2].y)
      - m[0].y * (m[1].x * m[2].z - m[1].z * m[2].x)
      + m[0].z * (m[1].x * m[2].y - m[1].y * m[2].x)
    }

    private static func invert3x3(_ m: [SIMD3<Double>]) -> [SIMD3<Double>]? {
        let det = determinant(m)
        guard abs(det) > 1e-15 else { return nil }
        let inv = 1 / det
        // Adjugate (transpose of cofactor matrix), scaled by 1/det.
        return [
            SIMD3((m[1].y * m[2].z - m[1].z * m[2].y) * inv,
                  (m[0].z * m[2].y - m[0].y * m[2].z) * inv,
                  (m[0].y * m[1].z - m[0].z * m[1].y) * inv),
            SIMD3((m[1].z * m[2].x - m[1].x * m[2].z) * inv,
                  (m[0].x * m[2].z - m[0].z * m[2].x) * inv,
                  (m[0].z * m[1].x - m[0].x * m[1].z) * inv),
            SIMD3((m[1].x * m[2].y - m[1].y * m[2].x) * inv,
                  (m[0].y * m[2].x - m[0].x * m[2].y) * inv,
                  (m[0].x * m[1].y - m[0].y * m[1].x) * inv),
        ]
    }
}

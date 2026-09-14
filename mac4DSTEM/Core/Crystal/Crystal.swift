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
package nonisolated struct AtomSite: Sendable {
    package var z: Int                       // atomic number
    package var fractional: SIMD3<Double>    // (x, y, z) fractional coordinates
    package var occupancy: Double = 1

    // Explicit so the memberwise initializer is `package` (synthesized ones are internal). // v2.5 step 2b
    package nonisolated init(z: Int, fractional: SIMD3<Double>, occupancy: Double = 1) {
        self.z = z
        self.fractional = fractional
        self.occupancy = occupancy
    }
}

/// One kinematically-allowed reflection.
package nonisolated struct Reflection: Sendable {
    package let h: Int, k: Int, l: Int
    package let g: SIMD3<Double>             // reciprocal-space vector (Å⁻¹), Cartesian
    package let gLength: Double              // |g| (Å⁻¹)
    package let structureFactorRe: Double
    package let structureFactorIm: Double
    package var intensity: Double           // |F|²

    // Explicit so the memberwise initializer is `package` (synthesized ones are internal). // v2.5 step 2b
    package nonisolated init(h: Int, k: Int, l: Int, g: SIMD3<Double>, gLength: Double, structureFactorRe: Double, structureFactorIm: Double, intensity: Double) {
        self.h = h
        self.k = k
        self.l = l
        self.g = g
        self.gLength = gLength
        self.structureFactorRe = structureFactorRe
        self.structureFactorIm = structureFactorIm
        self.intensity = intensity
    }
}

package nonisolated struct Crystal: Sendable {

    // Cell parameters.
    package let a: Double, b: Double, c: Double
    package let alphaDeg: Double, betaDeg: Double, gammaDeg: Double
    package let sites: [AtomSite]

    // Derived lattice matrices (rows are lattice vectors).
    package let latReal: [SIMD3<Double>]     // real lattice vectors (Å)
    package let latInv: [SIMD3<Double>]      // reciprocal lattice vectors (Å⁻¹)
    package let volume: Double               // unit-cell volume (Å³)

    // MARK: Construction

    package init(a: Double, b: Double, c: Double,
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
    package func reflections(kMax: Double, tolerance: Double = 1e-4) -> [Reflection] {
        // DEVIATION (2026-09-14, Gate D): py4DSTEM bounds every index by
        // ceil(k_max / k_leng_min), the shortest of ten reciprocal test
        // directions. The exact bound is per index — h = g·a₁ because
        // aᵢ·bⱼ* = δᵢⱼ, so |h| ≤ kMax·|a₁| — and for an oblique cell the
        // shortest reciprocal direction can be LONGER than 1/|a₁| (b-unique
        // monoclinic: a* = 1/(a sin β)), so py4DSTEM's tile falls short and
        // reflections go missing with no signal. Measured on the β″-shaped
        // cell at kMax 1.6: 0 lost at β = 105.3°, 6 at 110°, 48 at 115°, 198
        // at 125°. The per-axis bound is complete for every cell and returns
        // the identical set wherever the old one was complete; the filter on
        // |g| below is what actually decides membership.
        let tile = latReal.map { max(0, Int((kMax * length($0)).rounded(.up))) }

        var out: [Reflection] = []
        for h in -tile[0]...tile[0] {
            for k in -tile[1]...tile[1] {
                for l in -tile[2]...tile[2] {
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
    package var unsupportedElements: [Int] {
        Array(Set(sites.map(\.z).filter { !ScatteringFactors.isSupported(z: $0) })).sorted()
    }

    // MARK: Presets

    /// Face-centered cubic (4 atoms).
    package static func fcc(a: Double, z: Int) -> Crystal {
        Crystal(a: a, b: a, c: a, sites: [
            AtomSite(z: z, fractional: [0, 0, 0]),
            AtomSite(z: z, fractional: [0.5, 0.5, 0]),
            AtomSite(z: z, fractional: [0.5, 0, 0.5]),
            AtomSite(z: z, fractional: [0, 0.5, 0.5]),
        ])
    }

    /// Body-centered cubic (2 atoms).
    package static func bcc(a: Double, z: Int) -> Crystal {
        Crystal(a: a, b: a, c: a, sites: [
            AtomSite(z: z, fractional: [0, 0, 0]),
            AtomSite(z: z, fractional: [0.5, 0.5, 0.5]),
        ])
    }

    /// Simple cubic (1 atom).
    package static func sc(a: Double, z: Int) -> Crystal {
        Crystal(a: a, b: a, c: a, sites: [AtomSite(z: z, fractional: [0, 0, 0])])
    }

    /// Diamond cubic (8 atoms) — FCC plus a (¼,¼,¼) shifted sublattice.
    package static func diamond(a: Double, z: Int) -> Crystal {
        let base: [SIMD3<Double>] = [[0, 0, 0], [0.5, 0.5, 0], [0.5, 0, 0.5], [0, 0.5, 0.5]]
        let shift = SIMD3<Double>(0.25, 0.25, 0.25)
        return Crystal(a: a, b: a, c: a,
                       sites: (base + base.map { $0 + shift }).map { AtomSite(z: z, fractional: $0) })
    }

    /// Hexagonal close-packed primitive cell in the conventional 120° basis.
    package static func hcp(a: Double, c: Double, z: Int) -> Crystal {
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
    package nonisolated enum CubicStructure: String, CaseIterable, Identifiable, Sendable {
        case fcc = "FCC"
        case bcc = "BCC"
        case sc = "Simple cubic"
        case diamond = "Diamond"
        package var id: String { rawValue }

        package var provenanceID: String {
            switch self {
            case .fcc: "fcc"
            case .bcc: "bcc"
            case .sc: "simple_cubic"
            case .diamond: "diamond"
            }
        }
    }

    /// Build a single-element cubic crystal for the custom-crystal UI.
    package static func cubic(_ structure: CubicStructure, a: Double, z: Int) -> Crystal {
        switch structure {
        case .fcc:     return fcc(a: a, z: z)
        case .bcc:     return bcc(a: a, z: z)
        case .sc:      return sc(a: a, z: z)
        case .diamond: return diamond(a: a, z: z)
        }
    }

    // Named materials (lattice constants in Å).
    package static var aluminum: Crystal { fcc(a: 4.0495, z: 13) }
    package static var gold: Crystal     { fcc(a: 4.0782, z: 79) }
    package static var nickel: Crystal   { fcc(a: 3.5240, z: 28) }
    package static var copper: Crystal   { fcc(a: 3.6149, z: 29) }
    package static var iron: Crystal     { bcc(a: 2.8665, z: 26) }
    package static var silicon: Crystal  { diamond(a: 5.4309, z: 14) }
    package static var magnesium: Crystal { hcp(a: 3.2094, c: 5.2108, z: 12) }

    /// β″ (Mg₅Si₆), the hardening precipitate of Al-Mg-Si alloys — the
    /// canonical experimental refinement:
    /// S. J. Andersen, H. W. Zandbergen, J. Jansen, C. Traeholt, U. Tundal,
    /// O. Reiso, "The crystal structure of the β″ phase in Al-Mg-Si alloys",
    /// Acta Materialia 46(9), 3283-3298 (1998),
    /// doi:10.1016/S1359-6454(97)00493-X. Cell from the abstract; coordinates
    /// from Table 3, SET 3 — the C2/m refinement, R = 3.16 % over 377
    /// reflections from seven data sets. Sets 1 and 2 are the exit-wave
    /// extraction and the Cm refinement and are deliberately not used.
    ///
    /// Deliberately NOT Materials Project mp-31404, the same phase under a
    /// compatible licence: it is DFT-relaxed, and relaxed volumes run a few
    /// percent high — roughly 1 % on d-spacings, which is a systematic error
    /// in exactly the quantity vector matching scores on. The Crystallography
    /// Open Database has no Mg₅Si₆ entry (checked 2026-09-11).
    ///
    /// The six published sites are expanded here under C2/m (No. 12, unique
    /// axis b) rather than stored pre-expanded, so the expansion can be read.
    /// It MUST give Mg₁₀Si₁₂ = 2 × Mg₅Si₆ = 22 atoms, the cell content the
    /// paper states; `tools/phase-vector-matching` asserts the count, because
    /// sources disagree on the axis setting (some publish a = 15.16,
    /// b = 6.74, c = 4.05 with γ = 105.3° instead) and a misread coordinate
    /// would otherwise show up only as a wrong phase map.
    ///
    /// The orientation relationship comes from the same paper and is what
    /// vector matching leans on: β″ is coherent along its NEEDLE direction —
    /// its b-axis — with a ⟨100⟩ Al direction, and b = 4.05 Å is Al's own
    /// lattice parameter. So [010] is the zone axis to sample on ⟨100⟩Al data.
    package static var betaDoublePrime: Crystal {
        // Wyckoff 4i (x, 0, z) under C2/m: (x,0,z), (−x,0,−z) and the
        // C-centred pair. The 2a site at the origin collapses to two.
        func fourI(_ z: Int, _ x: Double, _ zc: Double) -> [AtomSite] {
            [SIMD3(x, 0, zc), SIMD3(-x, 0, -zc),
             SIMD3(x + 0.5, 0.5, zc), SIMD3(-x + 0.5, 0.5, -zc)]
                .map { AtomSite(z: z, fractional: $0) }
        }
        let mg = 12, si = 14
        var sites: [AtomSite] = [
            AtomSite(z: mg, fractional: [0, 0, 0]),          // Mg1, 2a
            AtomSite(z: mg, fractional: [0.5, 0.5, 0]),
        ]
        sites += fourI(mg, 0.3459, 0.089)                    // Mg2
        sites += fourI(mg, 0.430,  0.652)                    // Mg3
        sites += fourI(si, 0.0565, 0.649)                    // Si1
        sites += fourI(si, 0.1885, 0.224)                    // Si2
        sites += fourI(si, 0.2171, 0.617)                    // Si3
        return Crystal(a: 15.16, b: 4.05, c: 6.74,
                       alphaDeg: 90, betaDeg: 105.3, gammaDeg: 90,
                       sites: sites)
    }

    /// 2H tungsten disulfide, P6₃/mmc (#194) — the literature refinement:
    /// W. J. Schutte, J. L. de Boer, F. Jellinek, "Crystal structures of
    /// tungsten disulfide and diselenide", J. Solid State Chem. 70, 207–209
    /// (1987), doi:10.1016/0022-4596(87)90057-0. Table I: a = 3.1532(4) Å,
    /// c = 12.323(5) Å, z(S) = 0.6225(6); the Results text gives W at 2(c)
    /// ±(⅓,⅔,¼) and S at 4(f) ±(⅓,⅔,z; ⅓,⅔,½−z). Sites below are that
    /// Wyckoff expansion, in the paper's own setting; the Gate B refuter
    /// reproduced every Table II interatomic distance from these sites
    /// (W–S 2.405, S–S ∥c 3.14, interlayer 3.53 Å), which is what pins the
    /// ± convention.
    ///
    /// Deliberately NOT the staged Materials Project mp-224 cell
    /// (c = 14.2024 Å): DFT-PBE without a vdW correction inflates c ~15% —
    /// entirely in the inter-layer S-plane gap, which grows ~31% while the
    /// layer itself is unchanged. Note for matching on basal-textured data
    /// (the polycrystal_2D_WS2 cube's mean pattern is pure hk0 — no (00l)
    /// ring): there the operative mp-224 error is a, +1.19%, not c.
    /// Owner decision 2026-08-31 (docs/v2-release.md §9): the measured cell
    /// is the matching reference. z(S) = 0.614 (Kalikhman 1983) is the
    /// earlier powder value this refinement explicitly corrects — do not
    /// "fix" the coordinate back; tools/ws2-crystal-test pins the difference.
    package static var tungstenDisulfide: Crystal {
        let zS = 0.6225
        return Crystal(
            a: 3.1532, b: 3.1532, c: 12.323,
            alphaDeg: 90, betaDeg: 90, gammaDeg: 120,
            sites: [
                AtomSite(z: 74, fractional: [1.0 / 3.0, 2.0 / 3.0, 0.25]),
                AtomSite(z: 74, fractional: [2.0 / 3.0, 1.0 / 3.0, 0.75]),
                AtomSite(z: 16, fractional: [1.0 / 3.0, 2.0 / 3.0, zS]),          // ⅓,⅔,z
                AtomSite(z: 16, fractional: [1.0 / 3.0, 2.0 / 3.0, 1.5 - zS]),    // ⅓,⅔,½−z  → 0.8775
                AtomSite(z: 16, fractional: [2.0 / 3.0, 1.0 / 3.0, 1.0 - zS]),    // −(⅓,⅔,z) → 0.3775
                AtomSite(z: 16, fractional: [2.0 / 3.0, 1.0 / 3.0, zS - 0.5]),    // −(⅓,⅔,½−z) → 0.1225
            ]
        )
    }

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

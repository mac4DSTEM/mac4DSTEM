//
//  Crystal.swift
//  Role: The app's phase presets and cell constructors, as `CrystalStructure`s. The lattice algebra, the kinematic
//        reflection list and the scattering factors are DiffractoKit's (`UnitCell`, `CrystalStructure
//        .kinematicReflections`, `ElectronScatteringFactors`; 2026-10-15), so this file keeps only what the kit has no
//        counterpart for: the preset lattice constants and hand-written site lists (kit item 9: the β″ list stays
//        the hand list so its sums stay bit identical), and the cubic-structure editor's cells.
//
//  Units: distances in Å, scattering vectors |g| in Å⁻¹ (no 2π factor, matching py4DSTEM). Structure factors are in
//  Å⁻² (f_e in Å over V in Å³); py4DSTEM's "A" names f_e's unit, not F's.
//

import Foundation
import simd
import DiffractoCore
import DiffractoScattering

/// The preset crystals and cell constructors. A namespace: every member returns a `CrystalStructure`.
package nonisolated enum Crystal {

    /// A cell and its atoms, with the space-group operations DETECTED from the atoms (the kit's holohedry test), as a
    /// CIF without an operation loop is read. Replaces the app's old `Crystal(a:b:c:...:sites:)`.
    package static func structure(a: Double, b: Double, c: Double,
                                  alphaDeg: Double = 90, betaDeg: Double = 90, gammaDeg: Double = 90,
                                  sites: [AtomSite]) -> CrystalStructure {
        CrystalStructure.detectingSymmetry(
            cell: UnitCell(a: a, b: b, c: c, alphaDeg: alphaDeg, betaDeg: betaDeg, gammaDeg: gammaDeg),
            sites: sites)
    }

    /// Face-centered cubic (4 atoms).
    package static func fcc(a: Double, z: Int) -> CrystalStructure {
        structure(a: a, b: a, c: a, sites: [
            AtomSite(z: z, fractional: [0, 0, 0]),
            AtomSite(z: z, fractional: [0.5, 0.5, 0]),
            AtomSite(z: z, fractional: [0.5, 0, 0.5]),
            AtomSite(z: z, fractional: [0, 0.5, 0.5]),
        ])
    }

    /// Body-centered cubic (2 atoms).
    package static func bcc(a: Double, z: Int) -> CrystalStructure {
        structure(a: a, b: a, c: a, sites: [
            AtomSite(z: z, fractional: [0, 0, 0]),
            AtomSite(z: z, fractional: [0.5, 0.5, 0.5]),
        ])
    }

    /// Simple cubic (1 atom).
    package static func sc(a: Double, z: Int) -> CrystalStructure {
        structure(a: a, b: a, c: a, sites: [AtomSite(z: z, fractional: [0, 0, 0])])
    }

    /// Diamond cubic (8 atoms) — FCC plus a (¼,¼,¼) shifted sublattice.
    package static func diamond(a: Double, z: Int) -> CrystalStructure {
        let base: [SIMD3<Double>] = [[0, 0, 0], [0.5, 0.5, 0], [0.5, 0, 0.5], [0, 0.5, 0.5]]
        let shift = SIMD3<Double>(0.25, 0.25, 0.25)
        return structure(a: a, b: a, c: a,
                       sites: (base + base.map { $0 + shift }).map { AtomSite(z: z, fractional: $0) })
    }

    /// Hexagonal close-packed primitive cell in the conventional 120° basis.
    package static func hcp(a: Double, c: Double, z: Int) -> CrystalStructure {
        structure(
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
    package static func cubic(_ structure: CubicStructure, a: Double, z: Int) -> CrystalStructure {
        switch structure {
        case .fcc:     return fcc(a: a, z: z)
        case .bcc:     return bcc(a: a, z: z)
        case .sc:      return sc(a: a, z: z)
        case .diamond: return diamond(a: a, z: z)
        }
    }

    // Named materials (lattice constants in Å).
    // DEVIATION (ADR 040, 2026-09-28): 4.0495 Å is pure Al at room temperature. The
    // Thronsen et al. (2024) CIF uses 4.04 Å; on their dataset the difference moves 5 of
    // 29 241 positions (1.81 → 1.83 %), because the {220} ring straddles kMax = 0.70 Å⁻¹
    // (√8/a = 0.6985 vs 0.7001 Å⁻¹). A CIF import carries its own a. Revisit only if a
    // second dataset disagrees.
    package static var aluminum: CrystalStructure { fcc(a: 4.0495, z: 13) }
    package static var gold: CrystalStructure     { fcc(a: 4.0782, z: 79) }
    package static var nickel: CrystalStructure   { fcc(a: 3.5240, z: 28) }
    package static var copper: CrystalStructure   { fcc(a: 3.6149, z: 29) }
    package static var iron: CrystalStructure     { bcc(a: 2.8665, z: 26) }
    package static var silicon: CrystalStructure  { diamond(a: 5.4309, z: 14) }
    package static var magnesium: CrystalStructure { hcp(a: 3.2094, c: 5.2108, z: 12) }

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
    package static var betaDoublePrime: CrystalStructure {
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
        return structure(a: 15.16, b: 4.05, c: 6.74,
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
    package static var tungstenDisulfide: CrystalStructure {
        let zS = 0.6225
        return structure(
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
}

// MARK: - Thin conveniences over the kit's types (the app's old `Reflection` and `Crystal` spellings)

extension KinematicReflection {
    // The app's old `Reflection` field names, so the template, library and matcher code that reads reflections is
    // unchanged by the switch. Read-only views of the kit's fields; nothing is computed.
    package nonisolated var h: Int { reflection.hkl.h }
    package nonisolated var k: Int { reflection.hkl.k }
    package nonisolated var l: Int { reflection.hkl.l }
    package nonisolated var g: SIMD3<Double> { reflection.g }
    package nonisolated var gLength: Double { reflection.gLength }
    package nonisolated var structureFactorRe: Double { structureFactor.real }
    package nonisolated var structureFactorIm: Double { structureFactor.imaginary }
    package nonisolated var intensity: Double { structureFactor.intensity }
}

extension CrystalStructure {
    /// Atomic numbers of this structure's sites that have no electron scattering factor (the table covers Z = 1 to 103,
    /// the kit's element list 1 to 118). `kinematicReflections` throws `KinematicError.unsupportedElements` for the
    /// same elements; this is the pre-flight the callers that must name a phase or refuse before a long job use.
    package nonisolated var unsupportedElements: [Int] {
        Array(Set(sites.map(\.z).filter { !ElectronScatteringFactors.isSupported(z: $0) })).sorted()
    }
}

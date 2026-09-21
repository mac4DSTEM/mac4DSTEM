//
//  thronsen.swift — step 3 of docs/v3-vector-matching-plan.md: the published
//  ground truth of Thronsen et al., Ultramicroscopy 255 (2024) 113861, CC BY
//  4.0, Zenodo 10.5281/zenodo.6645396. `--thronsen labels.json` runs the
//  app's shipped matcher on their dataset A (Al [001], 2xxx alloy, θ′ and T1)
//  and scores it by THEIR metric: the fraction of scan positions whose label
//  differs from the ground truth, all classes counted. Their four methods
//  land at 0.96–1.75 % (reproduced from their published maps, 2026-09-15).
//
//  The crystals are the published structures (their Table 2), expanded to
//  full cells here with the standard operator lists of P6/mmm and I-4m2 —
//  built directly rather than through `CIFImport`, which admits only cubic
//  and hexagonal cells (θ′ is tetragonal). Al is the app's own.
//
//  Zone axes along [001]Al: θ′ (001)θ′ ∥ (001)Al, [100]θ′ ∥ [100]Al — so the
//  face-on variant is θ′[001] and the two edge-on variants are θ′[100] at
//  in-plane rotations 90° apart (the library's rotation sweep covers both).
//  T1: (0001)T1 ∥ (111)Al, [1-10]Al ∥ [10-10]T1 — the T1 direction parallel
//  to [001]Al is 0.29° from [0 -4 1] in the c = 14.145 Å cell; its ZOLZ
//  reflections lie at 0.233, 0.367, 0.467, 0.493 and 0.679 Å⁻¹, and the
//  reflections their ground truth was drawn from sit at 0.454 and 0.479.
//  The four T1 variants are 90° apart in plane, covered by the sweep.
//
//  Labels follow `create_ground_truth.ipynb`: 0 Al, 1 θ′ edge-on, 2 θ′
//  face-on, 3 T1, 4 the three annotators' disagreement (4 positions).
//

import Foundation

enum Thronsen {
    /// T1, Al₂CuLi: P6/mmm, a = 4.94775 Å, c = 14.14499 Å (their Table 2).
    static let t1 = Crystal(
        a: 4.94775, b: 4.94775, c: 14.14499, alphaDeg: 90, betaDeg: 90, gammaDeg: 120,
        sites: [
            AtomSite(z: 13, fractional: [0.333333, 0.000000, 0.000000]),
            AtomSite(z: 13, fractional: [0.666667, 0.000000, 0.000000]),
            AtomSite(z: 13, fractional: [0.000000, 0.333333, 0.000000]),
            AtomSite(z: 13, fractional: [0.000000, 0.666667, 0.000000]),
            AtomSite(z: 13, fractional: [0.666667, 0.666667, 0.000000]),
            AtomSite(z: 13, fractional: [0.333333, 0.333333, 0.000000]),
            AtomSite(z: 13, fractional: [0.000000, 0.000000, 0.406200]),
            AtomSite(z: 13, fractional: [0.000000, 0.000000, 0.593800]),
            AtomSite(z: 29, fractional: [0.666667, 0.333333, 0.161200]),
            AtomSite(z: 29, fractional: [0.333333, 0.666667, 0.838800]),
            AtomSite(z: 29, fractional: [0.333333, 0.666667, 0.161200]),
            AtomSite(z: 29, fractional: [0.666667, 0.333333, 0.838800]),
            AtomSite(z: 29, fractional: [0.500000, 0.000000, 0.323700]),
            AtomSite(z: 29, fractional: [0.500000, 0.000000, 0.676300]),
            AtomSite(z: 29, fractional: [0.000000, 0.500000, 0.323700]),
            AtomSite(z: 29, fractional: [0.000000, 0.500000, 0.676300]),
            AtomSite(z: 29, fractional: [0.500000, 0.500000, 0.323700]),
            AtomSite(z: 29, fractional: [0.500000, 0.500000, 0.676300]),
            AtomSite(z: 3, fractional: [0.000000, 0.000000, 0.199300]),
            AtomSite(z: 3, fractional: [0.000000, 0.000000, 0.800700]),
            AtomSite(z: 3, fractional: [0.333333, 0.666667, 0.500000]),
            AtomSite(z: 3, fractional: [0.666667, 0.333333, 0.500000])
        ])

    /// θ′, Al₂Cu: I-4m2, a = 4.04 Å, c = 5.80 Å (their Table 2).
    static let thetaPrime = Crystal(
        a: 4.04, b: 4.04, c: 5.80,
        sites: [
            AtomSite(z: 13, fractional: [0.000000, 0.000000, 0.000000]),
            AtomSite(z: 13, fractional: [0.500000, 0.500000, 0.500000]),
            AtomSite(z: 13, fractional: [0.000000, 0.000000, 0.500000]),
            AtomSite(z: 13, fractional: [0.500000, 0.500000, 0.000000]),
            AtomSite(z: 29, fractional: [0.000000, 0.500000, 0.250000]),
            AtomSite(z: 29, fractional: [0.500000, 0.000000, 0.750000])
        ])

    /// `constrained: false` is byte-for-byte today's behaviour (every phase
    /// free). `constrained: true` (`--or`) attaches the orientation
    /// relationship stated in its own form (2026-09-15): θ′ edge-on and
    /// face-on both list their two symmetry-equivalent variants against
    /// Al's {200} in the [001] zone — Core derives the allowed azimuth per
    /// entry, so no library-frame degree list is carried by hand any more.
    /// T1 (since S2, 2026-09-21) lists the paper's `[1-10]Al ∥ [10-10]T1` as two
    /// direction pairs; before that it was free, and the free sweep took 295 of
    /// 417 edge-on positions (`known-variants-rule-2026-09-21.md`).
    static func phases(constrained: Bool) -> [PhaseDefinition] {
        let thetaRelationships: [OrientationRelationship] = constrained ? [
            OrientationRelationship(candidate: .plane(SIMD3(0, 0, 2)), matrix: .plane(SIMD3(2, 0, 0))),
            OrientationRelationship(candidate: .plane(SIMD3(0, 0, 2)), matrix: .plane(SIMD3(0, 2, 0))),
        ] : []
        let thetaFaceRelationships: [OrientationRelationship] = constrained ? [
            OrientationRelationship(candidate: .plane(SIMD3(2, 0, 0)), matrix: .plane(SIMD3(2, 0, 0))),
            OrientationRelationship(candidate: .plane(SIMD3(2, 0, 0)), matrix: .plane(SIMD3(0, 2, 0))),
        ] : []
        // T1 (S2, 2026-09-21): the paper's `[1-10]Al ∥ [10-10]T1` with `[10-10]` in the
        // three-index basis the app uses, [u−t, v−t, w] = [2 1 0]; exactly ⟂ [0 -4 1] by the
        // hexagonal metric. Two pairs against Al's ⟨110⟩ 90° apart select the four variants
        // (the comparison is mod 180), the θ′ pattern above. Derivation: S2-diagnosis.md.
        let t1Relationships: [OrientationRelationship] = constrained ? [
            OrientationRelationship(candidate: .direction(SIMD3(2, 1, 0)), matrix: .direction(SIMD3(1, -1, 0))),
            OrientationRelationship(candidate: .direction(SIMD3(2, 1, 0)), matrix: .direction(SIMD3(1, 1, 0))),
        ] : []
        return [
            PhaseDefinition(id: "al", displayName: "Al", crystal: .aluminum,
                            role: .matrix, zoneAxes: [SIMD3(0, 0, 1)]),
            // Per-phase slab (`theta-prime-slab-2026-09-21.md`): θ′ is the flat
            // plate the paper's own 0.300 Å⁻¹ describes; T1 and Al stay `nil`
            // (the library's global 0.05, itself a DEVIATION from the paper's
            // T1 value of 0.030 — unchanged here, not this slice's question).
            PhaseDefinition(id: "theta-edge", displayName: "θ′ edge-on", crystal: thetaPrime,
                            role: .candidate, zoneAxes: [SIMD3(1, 0, 0)],
                            orientationRelationships: thetaRelationships,
                            excitationSlabInvAngstrom: 0.3),
            PhaseDefinition(id: "theta-face", displayName: "θ′ face-on", crystal: thetaPrime,
                            role: .candidate, zoneAxes: [SIMD3(0, 0, 1)],
                            orientationRelationships: thetaFaceRelationships,
                            excitationSlabInvAngstrom: 0.3),
            PhaseDefinition(id: "t1", displayName: "T1", crystal: t1,
                            role: .candidate, zoneAxes: [SIMD3(0, -4, 1)],
                            orientationRelationships: t1Relationships),
        ]
    }

    /// Their reflection cutoff: the preprocessed patterns are masked beyond
    /// 0.700 Å⁻¹ (`Preprocessing/Masks/Diffraction/_sig_cutoff`), so a
    /// reference beyond it can never be matched and must not be predicted.
    static let kMaxInvAngstrom = 0.70

    /// Ground-truth labels, `{"classes": {"0": …}, "labels": [[…]]}`, row-major.
    struct Truth {
        let classes: [Int: String]
        let labels: [Int]
        let height: Int, width: Int
        init?(path: String) {
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
                  let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let classes = root["classes"] as? [String: String],
                  let rows = root["labels"] as? [[Int]], let width = rows.first?.count
            else { return nil }
            self.classes = Dictionary(uniqueKeysWithValues: classes.compactMap { k, v in Int(k).map { ($0, v) } })
            self.labels = rows.flatMap { $0 }
            self.height = rows.count; self.width = width
        }
    }

    /// The app's verdict as their label. Not indexed / no data map to −1,
    /// which counts as mislabelled against every class, as their label 4
    /// ("unknown") does in their own vector-matching map.
    static func label(of result: PhaseVectorResult, phaseNames: [String]) -> Int {
        switch result.verdict {
        case .matrix: return 0
        case .indexed:
            let name = phaseNames.indices.contains(Int(result.phaseIndex)) ? phaseNames[Int(result.phaseIndex)] : ""
            switch name {
            case "θ′ edge-on": return 1
            case "θ′ face-on": return 2
            case "T1": return 3
            default: return -1
            }
        case .notIndexed, .noData: return -1
        }
    }
}

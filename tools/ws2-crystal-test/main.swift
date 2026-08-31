import Foundation

// W4a (S14+S15 merged, 2026-08-31): the WS₂ crystal-model fixture.
//
// Ground truth is ANALYTIC — the hexagonal reciprocal metric
//   1/d² = (4/3)(h² + hk + k²)/a² + l²/c²
// evaluated for the cited cell (Schutte, de Boer, Jellinek 1987,
// J. Solid State Chem. 70, 207–209: a = 3.1532 Å, c = 12.323 Å,
// z(S) = 0.6225) — never the code under test's own output.
//
// Scope, stated (corrected by Gate B refuter 2, 2026-08-31 — the first
// version claimed "a wrong site would be caught", and six screw-preserving
// site errors were green): a wrong LATTICE is caught by checks 1-2; a wrong
// PHASE-SUM implementation by check 6 (which recomputes from the same sites,
// so it can never catch a wrong site — only a wrong reflections()); a wrong
// SITE is caught by the extinction parity (check 3) only when it breaks the
// screw, and otherwise ONLY by the intensity anchors (check 8a), which exist
// for exactly that reason. A wrong f_e table is not caught here at all — the
// table is py4DSTEM-ported and gated by its own harnesses.

/// App-layer value type `VirtualDetector`'s aperture overload needs, mirrored so
/// the production source compiles standalone (the convention every harness in
/// `tools/` that pulls the `analysis` group follows).
struct Aperture {
    var centerX: Float
    var centerY: Float
    var inner: Float
    var outer: Float
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
    exit(1)
}

func approx(_ a: Double, _ b: Double, rel: Double = 1e-6, abs absTol: Double = 1e-9) -> Bool {
    Swift.abs(a - b) <= max(absTol, rel * max(Swift.abs(a), Swift.abs(b)))
}

/// Analytic |g| for the hexagonal cell — the closed form, not the code's
/// lattice inversion.
func hexG(_ h: Int, _ k: Int, _ l: Int, a: Double, c: Double) -> Double {
    let hh = Double(h), kk = Double(k), ll = Double(l)
    let inPlane = (4.0 / 3.0) * (hh * hh + hh * kk + kk * kk) / (a * a)
    return (inPlane + ll * ll / (c * c)).squareRoot()
}

@main
enum WS2CrystalTest {
    static func main() {
        let a = 3.1532, c = 12.323

        // ── 1. The catalog entry exists, is usable, and is the cited cell ──
        guard let model = CrystalModelLibrary.model(id: "ws2_2h") else {
            fail("ws2_2h is not in CrystalModelLibrary")
        }
        guard model.validationIssues.isEmpty else {
            fail("ws2_2h fails validation: \(model.validationIssues.map(\.code))")
        }
        guard model.symmetry == .hexagonal else {
            fail("ws2_2h symmetry is .\(model.symmetry.rawValue), not .hexagonal")
        }
        let ws2 = model.crystal
        guard approx(ws2.a, a, rel: 1e-12), approx(ws2.c, c, rel: 1e-12) else {
            fail("ws2_2h cell is a=\(ws2.a), c=\(ws2.c); the Schutte 1987 cell is a=\(a), c=\(c)")
        }
        let wSites = ws2.sites.filter { $0.z == 74 }
        let sSites = ws2.sites.filter { $0.z == 16 }
        guard ws2.sites.count == 6, wSites.count == 2, sSites.count == 4 else {
            fail("ws2_2h basis is not 2 W + 4 S (got \(ws2.sites.count) sites)")
        }
        print("PASS: ws2_2h in the catalog — cited cell, 2 W + 4 S, hexagonal")

        let reflections = ws2.reflections(kMax: 2.5)
        guard !reflections.isEmpty else { fail("ws2_2h generated no reflections") }
        var byHKL: [String: Reflection] = [:]
        for r in reflections { byHKL["\(r.h),\(r.k),\(r.l)"] = r }
        func refl(_ h: Int, _ k: Int, _ l: Int) -> Reflection? { byHKL["\(h),\(k),\(l)"] }

        // ── 2. |g| against the closed-form hexagonal metric ──
        for (h, k, l) in [(0, 0, 2), (1, 0, 0), (1, 0, 1), (1, 1, 0), (1, 0, 3), (2, 0, 2)] {
            let want = hexG(h, k, l, a: a, c: c)
            guard let r = refl(h, k, l) else {
                fail("(\(h)\(k)\(l)) missing from reflections; analytic |g| = \(want)")
            }
            guard approx(r.gLength, want) else {
                fail("(\(h)\(k)\(l)) |g| = \(r.gLength), closed form says \(want)")
            }
        }
        print("PASS: six |g| values match the closed-form hexagonal metric to 1e-6")

        // ── 3. Extinctions: the 6₃ screw kills (000l) for odd l — exactly ──
        // W at z = ¼, ¾ and S in ±(z, ½−z) pairs cancel identically for odd l;
        // this is structure, not tolerance. (0002)/(0004) must survive.
        for l in [1, 3, 5] where refl(0, 0, l) != nil {
            fail("(000\(l)) present — the 6₃ screw extinction is broken; " +
                 "check the site list against Schutte Table I")
        }
        for l in [2, 4] where refl(0, 0, l) == nil {
            fail("(000\(l)) absent — an allowed basal reflection was extinguished")
        }
        print("PASS: (000l) odd extinct, (0002)/(0004) present — the 6₃ screw is real")

        // ── 4. Shell order: the c/a = 3.908 inversion Mg cannot show ──
        // For Mg (c/a 1.62) the first distinct shell is in-plane (10-10);
        // for WS₂ (c/a 3.91) it is (0002), then (0004), and only then (10-10).
        // A fixture with only near-ideal hcp would be blind to this order —
        // the S8 symmetric-constant lesson, applied to c/a.
        func distinctShells(_ crystal: Crystal, kMax: Double) -> [Double] {
            let lengths = crystal.reflections(kMax: kMax).map(\.gLength)
            var shells: [Double] = []
            for length in lengths where shells.last.map({ length > $0 * (1 + 1e-6) }) ?? true {
                shells.append(length)
            }
            return shells
        }
        let shells = distinctShells(ws2, kMax: 2.5)
        guard shells.count >= 3,
              approx(shells[0], 2.0 / c, rel: 1e-6),                 // (0002) 0.162298
              approx(shells[1], 4.0 / c, rel: 1e-6),                 // (0004) 0.324596
              approx(shells[2], hexG(1, 0, 0, a: a, c: c), rel: 1e-6) // (10-10) 0.366206
        else {
            fail("WS₂ shell order is not (0002), (0004), (10-10): got \(shells.prefix(4))")
        }
        let mgShells = distinctShells(Crystal.magnesium, kMax: 1.0)
        guard let mgFirst = mgShells.first,
              approx(mgFirst, hexG(1, 0, 0, a: 3.2094, c: 5.2108), rel: 1e-6) else {
            fail("Mg first shell is not in-plane (10-10) — the inversion check lost its control")
        }
        print("PASS: WS₂ first shell is (0002); Mg's is (10-10) — the c/a inversion is pinned")

        // ── 5. The reference-shell measurement (documents CURRENT behavior) ──
        // AppState's Q-calibration reference takes the first DISTINCT shell of
        // the full 3D list, with no l-filter and no visibility filter
        // (AppState.swift ~5038-5051). For WS₂ that is (0002) — a reflection a
        // [0001]-zone 2D specimen never shows. This check pins what the app
        // WOULD select and the mis-scale that follows if the first observed
        // ring is (10-10). It is a MEASUREMENT, not an endorsement: the open
        // item lives in docs/open-items.md, and whoever changes the selection
        // rule must update this check and that item together (safe-defaults
        // owner decision, 2026-08-31 — measure and report, do not fix here).
        let referenceShell = shells[0]
        let firstInPlane = hexG(1, 0, 0, a: a, c: c)
        let misScale = firstInPlane / referenceShell
        guard approx(referenceShell, 0.16229813, rel: 1e-5),
              approx(misScale, 2.25638, rel: 1e-3) else {
            fail("reference-shell measurement moved: shell=\(referenceShell), ratio=\(misScale) " +
                 "— if the selection rule changed, update this check AND the open item together")
        }
        print("REPORT: current reference-shell rule selects (0002) |g|=\(String(format: "%.5f", referenceShell)) Å⁻¹; " +
              "a [0001]-zone specimen shows (10-10) first — mis-scale factor \(String(format: "%.4f", misScale))")

        // ── 6. Independent phase-sum: recompute F from the sites ──
        for (h, k, l) in [(1, 0, 0), (0, 0, 2), (1, 0, 3)] {
            guard let r = refl(h, k, l) else { fail("(\(h)\(k)\(l)) missing for the F cross-check") }
            var re = 0.0, im = 0.0
            for site in ws2.sites {
                let fe = ScatteringFactors.electronScatteringFactor(
                    z: site.z, gSquared: r.gLength * r.gLength) ?? 0
                let phase = 2 * Double.pi * (Double(h) * site.fractional.x
                                           + Double(k) * site.fractional.y
                                           + Double(l) * site.fractional.z)
                re += fe * site.occupancy * cos(phase)
                im += fe * site.occupancy * sin(phase)
            }
            re /= ws2.volume; im /= ws2.volume
            guard approx(re, r.structureFactorRe, rel: 1e-9, abs: 1e-12),
                  approx(im, r.structureFactorIm, rel: 1e-9, abs: 1e-12) else {
                fail("(\(h)\(k)\(l)) F mismatch: independent sum (\(re), \(im)) vs code " +
                     "(\(r.structureFactorRe), \(r.structureFactorIm))")
            }
        }
        print("PASS: re-derived phase-sum reproduces F for (10-10), (0002), (10-13) — pins reflections(), not the sites")

        // ── 7. Symmetry equivalents carry equal intensity ──
        let star: [(Int, Int, Int)] = [(1, 0, 0), (0, 1, 0), (-1, 1, 0), (-1, 0, 0), (0, -1, 0), (1, -1, 0)]
        let intensities = star.compactMap { refl($0.0, $0.1, $0.2)?.intensity }
        guard intensities.count == 6,
              let i0 = intensities.first,
              intensities.allSatisfy({ approx($0, i0, rel: 1e-9) }) else {
            fail("the {10-10} star does not carry six equal intensities: \(intensities)")
        }
        print("PASS: the {10-10} star — six equivalents, equal intensity")

        // ── 8. Negative controls: prove each wrong variant DIFFERS here ──
        // Anti-vacuity: a control that cannot fail is not a control. Each one
        // names the model line it would break.
        func variant(zS: Double = 0.6225, a va: Double = 3.1532, c vc: Double = 12.323,
                     swapSpecies: Bool = false, sOccupancy: Double = 1.0) -> Crystal {
            let (zW, zChalc) = swapSpecies ? (16, 74) : (74, 16)
            return Crystal(
                a: va, b: va, c: vc, alphaDeg: 90, betaDeg: 90, gammaDeg: 120,
                sites: [
                    AtomSite(z: zW, fractional: [1.0 / 3.0, 2.0 / 3.0, 0.25]),
                    AtomSite(z: zW, fractional: [2.0 / 3.0, 1.0 / 3.0, 0.75]),
                    AtomSite(z: zChalc, fractional: [1.0 / 3.0, 2.0 / 3.0, zS], occupancy: sOccupancy),
                    AtomSite(z: zChalc, fractional: [1.0 / 3.0, 2.0 / 3.0, 1.5 - zS], occupancy: sOccupancy),
                    AtomSite(z: zChalc, fractional: [2.0 / 3.0, 1.0 / 3.0, 1.0 - zS], occupancy: sOccupancy),
                    AtomSite(z: zChalc, fractional: [2.0 / 3.0, 1.0 / 3.0, zS - 0.5], occupancy: sOccupancy),
                ]
            )
        }
        func intensity(_ crystal: Crystal, _ h: Int, _ k: Int, _ l: Int) -> Double {
            crystal.reflections(kMax: 1.0)
                .first { $0.h == h && $0.k == k && $0.l == l }?.intensity ?? 0
        }

        // ── 8a. Absolute intensity anchors — the site-level pin ──
        // Gate B, refuter 2 (2026-08-31): every check above is metric-only,
        // screw-parity-only, a symmetry invariant, or recomputed FROM the
        // sites — so six screw-preserving site errors, including the wrong 2H
        // polytype (W on 2a, the NbS₂-type stacking), left this whole fixture
        // green while distorting ACOM-relevant intensities 2×–200×. These two
        // ratios pin the sites through the physics. rel 1%: tight enough that
        // every demonstrated mutant reds, loose enough to survive small
        // scattering-table evolution. If they move, check the BASIS against
        // Schutte Tables I/II before touching these numbers.
        let anchor1 = intensity(ws2, 0, 0, 2) / intensity(ws2, 1, 0, 0)
        let anchor2 = intensity(ws2, 1, 0, 3) / intensity(ws2, 1, 0, 0)
        guard approx(anchor1, 2.38277, rel: 0.01), approx(anchor2, 1.72056, rel: 0.01) else {
            fail("intensity anchors moved: I(0002)/I(10-10)=\(anchor1) (want 2.38277), " +
                 "I(10-13)/I(10-10)=\(anchor2) (want 1.72056) — a site-level change")
        }
        print("PASS: intensity anchors I(0002)/I(10-10), I(10-13)/I(10-10) pin the sites")

        // Control A — z(S) = 0.614, Kalikham's powder value that Schutte 1987
        // explicitly corrects. Breaks: the zS constant in `tungstenDisulfide`.
        let kalikham = variant(zS: 0.614)
        let i103 = intensity(ws2, 1, 0, 3), i103k = intensity(kalikham, 1, 0, 3)
        guard i103 > 0, Swift.abs(i103k - i103) / i103 > 0.05 else {
            fail("control A cannot see z(S) 0.6225→0.614 on (10-13): \(i103) vs \(i103k) — vacuous control")
        }

        // Control B — the staged mp-224 DFT c = 14.2024. Breaks: the c constant.
        let mp224 = variant(c: 14.2024)
        let g002mp = mp224.reflections(kMax: 0.5).first { $0.h == 0 && $0.k == 0 && $0.l == 2 }?.gLength ?? 0
        guard Swift.abs(g002mp - 2.0 / c) / (2.0 / c) > 0.10 else {
            fail("control B cannot see c 12.323→14.2024 on (0002): \(g002mp) — vacuous control")
        }

        // Control C — species swapped (S on 2c, W on 4f). Breaks: the z
        // (atomic number) arguments on the six AtomSites.
        let swapped = variant(swapSpecies: true)
        let ratio = intensity(ws2, 0, 0, 2) / intensity(ws2, 1, 0, 0)
        let ratioSwapped = intensity(swapped, 0, 0, 2) / intensity(swapped, 1, 0, 0)
        guard ratio.isFinite, ratioSwapped.isFinite,
              Swift.abs(ratioSwapped - ratio) / ratio > 0.10 else {
            fail("control C cannot see the species swap on I(0002)/I(10-10): \(ratio) vs \(ratioSwapped) — vacuous control")
        }
        // Control D — reflections() must CONSUME site occupancy. Deleting the
        // `site.occupancy` factor from the F sum was green across the entire
        // gate (refuter 2, MUT-G): every shipped model is fully occupied, and
        // check 6 recomputes with the same factor, so both sides agreed.
        // Breaks: the `* site.occupancy` in `Crystal.reflections`.
        let halfS = variant(sOccupancy: 0.5)
        let occRatio = intensity(ws2, 0, 0, 4) / intensity(ws2, 1, 0, 0)
        let occRatioHalf = intensity(halfS, 0, 0, 4) / intensity(halfS, 1, 0, 0)
        guard occRatio.isFinite, occRatioHalf.isFinite,
              Swift.abs(occRatioHalf - occRatio) / occRatio > 0.10 else {
            fail("control D cannot see occupancy 1.0→0.5 on I(0004)/I(10-10): " +
                 "\(occRatio) vs \(occRatioHalf) — reflections() is not consuming occupancy")
        }
        print("PASS: four negative controls bite — z(S), the c constant, the species assignment, occupancy")

        print("ws2-crystal-test: all passed")
    }
}

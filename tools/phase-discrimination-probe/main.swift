//
//  main.swift -- tools/phase-discrimination-probe
//
//  THE MEASUREMENT THAT CAN KILL THE TEMPLATE-MATCHED ROUTE.
//
//  docs/v3-precipitate-classification.md proposes labelling each scan position
//  by matching its diffraction pattern against per-phase templates. Every
//  precipitate pattern in a real foil ALSO carries the matrix reflections --
//  the beam passes through matrix above and below the particle -- so the
//  question nothing has measured is:
//
//      does the best-score argmax pick the PRECIPITATE phase when the pattern
//      contains both phases, and at what mixing fraction does it flip?
//
//  Templates and the experimental image are both per-ring mean-subtracted and
//  L2-normalised (OrientationPlan.swift:138-141, OrientationMatcher.swift
//  :245-249) and then compared by a plain argmax with NO per-template
//  normalisation, so a many-reflection phase can dilute against a sparse one.
//  No fixture anywhere tests two phases against one pattern.
//
//  PRE-REGISTERED CRITERION, written before the first run: a beta'' needle is
//  ~4 nm across in a 50-100 nm foil, so the precipitate's share of the beam
//  path is roughly 0.05-0.5. If the argmax needs a fraction ABOVE 0.3 to pick
//  the precipitate, per-position template matching is NOT viable for
//  precipitates and classification must run on class-AVERAGE patterns instead.
//
//  Al fcc and Si diamond stand in for matrix and precipitate. They are the two
//  built-in cubic presets, need no CIF and no importer change, and the point
//  is the SCORING GEOMETRY -- unit-norm templates, argmax, no per-phase
//  normalisation -- which is identical whatever the two phases are.
//
import Foundation
#if canImport(DSTEMCore)
import DSTEMCore
#endif
import simd

@main
enum Probe {
    static func main() {
        let kMax = 1.6, sgWidth = 0.03, sgMax = 0.1
        let matrix = Crystal.aluminum
        let precip = Crystal.silicon

        guard let planM = try? OrientationPlan.generate(
                crystal: matrix, kMax: kMax, zoneAxisCount: 300, symmetry: .cubic),
              let planP = try? OrientationPlan.generate(
                crystal: precip, kMax: kMax, zoneAxisCount: 300, symmetry: .cubic),
              let matcherM = OrientationMatcher(plan: planM, symmetry: .cubic),
              let matcherP = OrientationMatcher(plan: planP, symmetry: .cubic)
        else { fatalError("plan/matcher construction failed") }

        // One zone axis each, projected to spots, then rendered as peaks on a
        // detector. [001] for both: the most ordinary on-axis case.
        let zone = SIMD3<Double>(0, 0, 1)
        func spots(_ c: Crystal) -> [(r: Double, azim: Double, weight: Double)] {
            OrientationPlan.project(
                reflections: c.reflections(kMax: kMax), zoneAxis: zone,
                sgWidth: sgWidth, sgMax: sgMax)
        }
        let sm = spots(matrix), sp = spots(precip)
        print("phase-discrimination-probe: matrix spots \(sm.count), precipitate spots \(sp.count)")

        let originX: Float = 64, originY: Float = 64
        let pxPerInvA = 40.0          // detector scale; only the ratio matters
        func peaks(_ s: [(r: Double, azim: Double, weight: Double)], _ scale: Double)
            -> [BraggPeak] {
            s.map { spot in
                BraggPeak(
                    x: originX + Float(spot.r * pxPerInvA * cos(spot.azim)),
                    y: originY + Float(spot.r * pxPerInvA * sin(spot.azim)),
                    intensity: Float(spot.weight * scale))
            }
        }

        print("\n  f = precipitate share of the diffracted intensity")
        print("  \("f".padding(toLength: 6, withPad: " ", startingAt: 0))"
              + "  matrixScore  precipScore   winner")
        var flip: Double?
        for i in 0...20 {
            let f = Double(i) / 20
            let all = peaks(sm, 1 - f) + peaks(sp, f)
            let rm = matcherM.match(peaks: all, originX: originX, originY: originY,
                                    invAngstromPerPixel: 1 / pxPerInvA)
            let rp = matcherP.match(peaks: all, originX: originX, originY: originY,
                                    invAngstromPerPixel: 1 / pxPerInvA)
            let winner = rp.score > rm.score ? "PRECIPITATE" : "matrix"
            if flip == nil, rp.score > rm.score { flip = f }
            print(String(format: "  %-6.2f  %11.5f  %11.5f   %@",
                         f, rm.score, rp.score, winner))
        }

        // ---- DOES MATRIX MASKING RESCUE IT? -----------------------------
        // Thronsen et al. (2023) mask the matrix reflections and the direct
        // beam out of every pattern before template matching, and leave the
        // matrix out of the template library entirely, "because Al has
        // overlapping reflections with the precipitates". Their method, not
        // their code -- no licence, so nothing is copied; the parameter below
        // is ours and is derived here rather than taken from their notebook.
        //
        // Our peak-list analogue: drop any peak lying within `maskRadius` of a
        // reflection of the MATRIX reference pattern. Everything surviving is
        // what is not matrix.
        //
        // PREDICTION, written before the run: if masking transfers, the flip
        // moves well below the unmasked 0.60 and ideally under the
        // pre-registered 0.30.
        let matrixRef = peaks(sm, 1.0)
        func maskMatrix(_ ps: [BraggPeak], radius: Float) -> [BraggPeak] {
            ps.filter { p in
                !matrixRef.contains { m in
                    (m.x - p.x) * (m.x - p.x) + (m.y - p.y) * (m.y - p.y) <= radius * radius
                }
            }
        }
        for radius in [Float(2), 4, 6] {
            var maskedFlip: Double?
            var rows: [String] = []
            for i in 0...20 {
                let f = Double(i) / 20
                let all = maskMatrix(peaks(sm, 1 - f) + peaks(sp, f), radius: radius)
                let rm = matcherM.match(peaks: all, originX: originX, originY: originY,
                                        invAngstromPerPixel: 1 / pxPerInvA)
                let rp = matcherP.match(peaks: all, originX: originX, originY: originY,
                                        invAngstromPerPixel: 1 / pxPerInvA)
                if maskedFlip == nil, rp.score > rm.score { maskedFlip = f }
                if i % 4 == 0 {
                    rows.append(String(format: "      f=%.2f  matrix %.5f  precip %.5f  peaks %d",
                                       f, rm.score, rp.score, all.count))
                }
            }
            print("\n  MASKED, matrix-reflection radius \(Int(radius)) px:")
            rows.forEach { print($0) }
            if let maskedFlip {
                print(String(format: "    -> flip at f = %.2f   (unmasked was 0.60)", maskedFlip))
                print("    Scores are f-INDEPENDENT above the flip, and that is correct, not a")
                print("    bug: with the matrix masked away the surviving pattern is pure")
                print("    precipitate, and the matcher L2-normalises, so scaling every intensity")
                print("    leaves the normalised pattern identical.")
                print("    THREE LIMITS THIS MEASUREMENT DOES NOT ESCAPE:")
                print("     - the mask here is PERFECT, built from the exact reference peak")
                print("       positions. A real mask comes from a real matrix region through")
                print("       background removal and thresholding, and is not.")
                print("     - the score FLOOR survives masking: the matrix plan still scores 0.826")
                print("       on a pattern holding none of its reflections, so the contrast is")
                print("       ~0.11, not ~1. Masking fixes the MIXING problem, not the")
                print("       wrong-phase problem.")
                print("     - masking cannot separate phases whose reflections OVERLAP: masking Al")
                print("       would mask Au with it. It works here because Si sits 218% of a radial")
                print("       bin from Al -- as does a superlattice ring against Al's first ring.")
            } else {
                print("    -> NO FLIP: masking did not rescue it at this radius.")
            }
        }

        // ---- THE SCORE FLOOR, and it may be the whole story -------------
        // The f = 0.00 row shows the precipitate plan scoring high on a
        // pattern containing NONE of its reflections. If an unrelated phase
        // scores just as high, the absolute score is nearly uninformative and
        // the argmax is comparing two large, mostly-baseline numbers.
        print("\n  CONTROL -- scores on the PURE MATRIX pattern (f = 0):")
        let pureMatrix = peaks(sm, 1.0)
        var floors: [(String, Float)] = []
        for (name, c) in [("aluminium (the true phase)", matrix),
                          ("silicon (the test precipitate)", precip),
                          ("gold fcc, a = 4.08", Crystal.gold),
                          ("copper fcc, a = 3.61", Crystal.copper)] {
            guard let pl = try? OrientationPlan.generate(
                    crystal: c, kMax: kMax, zoneAxisCount: 300, symmetry: .cubic),
                  let mt = OrientationMatcher(plan: pl, symmetry: .cubic) else { continue }
            let s = mt.match(peaks: pureMatrix, originX: originX, originY: originY,
                             invAngstromPerPixel: 1 / pxPerInvA).score
            floors.append((name, s))
            print(String(format: "    %@  %.5f", name.padding(toLength: 32, withPad: " ", startingAt: 0), s))
        }
        if let truth = floors.first?.1 {
            let others = floors.dropFirst().map(\.1)
            if let worst = others.max() {
                print(String(format: "\n  contrast = true phase - best wrong phase = %.5f - %.5f = %.5f",
                             truth, worst, truth - worst))
                if truth - worst < 0.25 {
                    print("  The score FLOOR is high: a phase whose reflections are absent still")
                    print("  scores within \(String(format: "%.2f", truth - worst)) of the true one. The absolute score is")
                    print("  therefore a weak phase discriminator, and this -- not the mixing")
                    print("  fraction alone -- is why the argmax flips so late.")
                }
            }
        }

        // ---- IS THE FLOOR A PARAMETER LIMIT? ----------------------------
        // The owner asked whether the Al/Au confusion is a property of his
        // strongly-binned (bin_4) cube. It cannot be: these peaks are analytic,
        // generated at exact positions with no detector and no binning, and
        // `nRadial` is a free parameter of OrientationPlan, not something
        // derived from the detector. So the limit should move when nRadial
        // moves. Bin width is kMax/nRadial; Al-Au (111) differ by 0.0030 A^-1,
        // so separating them predicts nRadial > 1.6/0.0030 = 533.
        print("\n  nRadial SWEEP -- scores on the PURE ALUMINIUM pattern:")
        print("    nRadial   binWidth      Al       Au    Au-Al   verdict")
        for nR in [32, 64, 128, 256, 512, 1024] {
            var s: [String: Float] = [:]
            for (nm, c) in [("Al", matrix), ("Au", Crystal.gold)] {
                guard let pl = try? OrientationPlan.generate(
                        crystal: c, kMax: kMax, nRadial: nR, zoneAxisCount: 300,
                        symmetry: .cubic),
                      let mt = OrientationMatcher(plan: pl, symmetry: .cubic) else { continue }
                s[nm] = mt.match(peaks: peaks(sm, 1.0), originX: originX, originY: originY,
                                 invAngstromPerPixel: 1 / pxPerInvA).score
            }
            guard let al = s["Al"], let au = s["Au"] else { continue }
            let verdict = al > au ? "Al wins (correct)" : "Au WINS (wrong)"
            print(String(format: "    %5d   %8.5f  %7.5f  %7.5f  %+7.5f   %@",
                         nR, kMax / Double(nR), al, au, au - al, verdict))
        }

        // ---- WHY, quantitatively ----------------------------------------
        // The polar template is sampled on nRadial bins over kMax, so two
        // phases whose reflections differ by less than one bin are the SAME
        // pattern as far as the score is concerned.
        let binWidth = kMax / 32
        print(String(format: "\n  radial bin width = kMax/nRadial = %.2f/32 = %.4f A^-1", kMax, binWidth))
        let r3 = 3.0.squareRoot()
        for (name, a) in [("Au", 4.0782), ("Cu", 3.6149), ("Si", 5.4309)] {
            let d = abs(r3 / 4.0495 - r3 / a)
            print(String(format: "    Al-%@ (111) separation %.4f A^-1 = %.0f%% of one bin",
                         name, d, d / binWidth * 100))
        }
        print("  Phases closer than one radial bin are indistinguishable by this score.")

        print("")
        if let flip {
            print(String(format: "FLIP at f = %.2f", flip))
            if flip <= 0.3 {
                print("PASS against the pre-registered criterion (flip <= 0.30):")
                print("  per-position template matching discriminates phase at a")
                print("  physically plausible precipitate fraction.")
            } else {
                print("FAIL against the pre-registered criterion (flip <= 0.30):")
                print("  the matrix wins until the precipitate dominates the pattern,")
                print("  so per-position template matching is NOT viable here and")
                print("  classification must run on class-AVERAGE patterns.")
            }
        } else {
            print("NO FLIP at any f up to 1.0 — the precipitate phase never wins,")
            print("even on a pattern containing ONLY its own reflections. That is a")
            print("stronger negative than the criterion anticipated.")
        }
    }
}

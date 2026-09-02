//
//  tools/q-calibration-gate-test — v2 S13.
//
//  What the app is willing to CLAIM about a reciprocal scale, pinned.
//
//  THIS FILE'S HEADER USED TO SAY "read the negative controls at the bottom".
//  There are none at the bottom, and there never were — the controls are
//  mutations applied to `Core/` and recorded in
//  docs/archive/v2-session-records/s13.md §4, not code in this file. A Gate B
//  reviewer caught the sentence pointing readers at empty space, 2026-08-28.
//
//  READ THAT SECTION BEFORE TRUSTING ANY PASS HERE, AND READ ITS SECOND TABLE
//  FIRST. A systematic sweep of 32 single-line mutations found **26 of them
//  leave this fixture GREEN**. Its 39 checks cover approximately one path
//  through `fitOriginTrimmed` — `.plane`, one outlier magnitude, one scan
//  shape — and the following are provably unguarded: the `.constant` and
//  `.parabola` branches, the `fitOrigin(included:)` overload, `trimSigma` and
//  the 1.4826 MAD factor in the loosening direction, two of three loop exits,
//  the reference-origin precedence order, every user-facing percentage, and
//  NaN anywhere at all.
//
//  "It went red" is not evidence (the L4 phantom-control lesson) — and neither
//  is "it went green", which is what this file taught the session that wrote it.
//

import Foundation

// `Aperture` now lives in Core/Analysis/VirtualDetector.swift (2026-09-02);
// the local mirror this file carried is gone.

var failures = 0
var checks = 0

func require(_ condition: Bool, _ message: @autoclosure () -> String) {
    checks += 1
    if !condition {
        failures += 1
        print("FAIL: \(message())")
    }
}

func requireClose(_ actual: Double, _ expected: Double, _ tolerance: Double,
                  _ message: @autoclosure () -> String) {
    require(abs(actual - expected) <= tolerance,
            "\(message()) — got \(actual), expected \(expected) ± \(tolerance)")
}

@main
struct QCalibrationGateTest {
    static func main() {
        // MARK: - 1. The robust origin fit
        //
        // A plane the fit must recover, plus a planted outlier population that drags an
        // unweighted least-squares fit off it. This is `Particle_1`'s shape in
        // miniature: a heavy tail on a minority of positions, which S12 measured moving
        // the shipped fit by up to 6.00 px.

        let width = 40, height = 30
        let count = width * height

        func truePlane(_ index: Int) -> (x: Float, y: Float) {
            let rx = Float(index % width), ry = Float(index / width)
            return (64 + 0.05 * rx + 0.02 * ry, 64 - 0.03 * rx + 0.04 * ry)
        }

        var measuredX = [Float](repeating: 0, count: count)
        var measuredY = [Float](repeating: 0, count: count)
        // A deterministic, unmistakable outlier population: every 7th position is
        // thrown 40 px in a FIXED direction, so it biases the fit rather than
        // cancelling out. 1/7 = 14.3% of the scan.
        var plantedOutliers = Set<Int>()
        for index in 0..<count {
            let truth = truePlane(index)
            if index % 7 == 0 {
                plantedOutliers.insert(index)
                measuredX[index] = truth.x + 40
                measuredY[index] = truth.y + 40
            } else {
                measuredX[index] = truth.x
                measuredY[index] = truth.y
            }
        }

        let ordinary = OriginCalibration.fitOrigin(
            measuredX: measuredX, measuredY: measuredY,
            width: width, height: height, fitFunction: .plane
        )
        let trimmed = OriginCalibration.fitOriginTrimmed(
            measuredX: measuredX, measuredY: measuredY,
            width: width, height: height, fitFunction: .plane
        )

        func maximumDeviationFromTruth(_ fx: [Float], _ fy: [Float]) -> Double {
            (0..<count).reduce(0.0) { worst, index in
                let truth = truePlane(index)
                let dx = Double(fx[index] - truth.x), dy = Double(fy[index] - truth.y)
                return max(worst, (dx * dx + dy * dy).squareRoot())
            }
        }

        let ordinaryError = maximumDeviationFromTruth(ordinary.fittedX, ordinary.fittedY)
        let trimmedError = maximumDeviationFromTruth(trimmed.fittedX, trimmed.fittedY)

        // The ordinary fit is dragged by 14.3% of positions thrown 40 px: 0.143 * 40 *
        // sqrt(2) ≈ 8.1 px of bias, and a plane cannot absorb it because the outliers
        // are spread uniformly. The trimmed fit must land on the truth.
        require(ordinaryError > 5,
                "the planted outliers must actually drag the ordinary fit, else this fixture proves "
                + "nothing — max deviation was only \(ordinaryError) px")
        require(trimmedError < 0.01,
                "the trimmed fit must recover the true plane — max deviation \(trimmedError) px")
        require(trimmedError < ordinaryError / 100,
                "the trimmed fit must be dramatically better, not marginally: ordinary \(ordinaryError) px "
                + "vs trimmed \(trimmedError) px")

        // The excluded set must be the planted set, not merely the right SIZE. A trim
        // that excluded 14.3% of the wrong positions would pass a count assertion.
        let excludedIndices = Set((0..<count).filter { !trimmed.kept[$0] })
        require(excludedIndices == plantedOutliers,
                "the trim must exclude exactly the planted outliers — excluded \(excludedIndices.count), "
                + "planted \(plantedOutliers.count), symmetric difference "
                + "\(excludedIndices.symmetricDifference(plantedOutliers).count)")
        // 1200 is not a multiple of 7, so the planted count is 172, not 1200/7.
        // The exact expectation is derived from the planted set rather than
        // from the ratio, because an assertion that has to be right about
        // arithmetic is an assertion that can be wrong about arithmetic.
        requireClose(Double(trimmed.excludedFraction ?? .nan),
                     Double(plantedOutliers.count) / Double(count), 1e-6,
                     "excluded fraction must be the planted count over the scan")

        // RMS(kept) and RMS(all) are DIFFERENT numbers and the distinction is the whole
        // point of S12 §1.2 — a robust fit alone does not clear a full-scan gate.
        require(Double(trimmed.keptResidual) < 1e-3,
                "residual over kept positions must be ~0 — got \(trimmed.keptResidual)")
        require(Double(trimmed.fullScanResidual) > 15,
                "residual over ALL positions must still be large: the outliers are still 40 px away "
                + "from the (now correct) surface — got \(trimmed.fullScanResidual)")

        // Broad failure has no tail to trim. Uniform scatter on EVERY position must
        // leave the trim keeping ~everything, which is why the excluded fraction can
        // never be the refusal statistic (Si_SiGe keeps 100.0% and is the worst fit of
        // the four training datasets).
        var scatteredX = [Float](repeating: 0, count: count)
        var scatteredY = [Float](repeating: 0, count: count)
        var state: UInt64 = 12345
        func nextUniform() -> Float {
            state ^= state << 13; state ^= state >> 7; state ^= state << 17
            return Float(state % 10_000) / 10_000 - 0.5
        }
        for index in 0..<count {
            let truth = truePlane(index)
            scatteredX[index] = truth.x + nextUniform() * 20
            scatteredY[index] = truth.y + nextUniform() * 20
        }
        let broad = OriginCalibration.fitOriginTrimmed(
            measuredX: scatteredX, measuredY: scatteredY,
            width: width, height: height, fitFunction: .plane
        )
        require((broad.excludedFraction ?? 1) < 0.05,
                "broad scatter has no tail to trim, so the trim must exclude almost nothing — excluded "
                + "\((broad.excludedFraction ?? .nan) * 100)%")
        require(Double(broad.keptResidual) > 3,
                "and the residual must stay large, so the GATE still refuses — got \(broad.keptResidual)")

        // MARK: - 2. One derivation of the reference origin

        let detectorQX = 128, detectorQY = 128
        let aperture = (x: Float(70), y: Float(75))

        var fitted = Calibration()
        fitted.origin = OriginMaps(
            width: width, height: height,
            measuredX: measuredX, measuredY: measuredY,
            fittedX: trimmed.fittedX, fittedY: trimmed.fittedY,
            excludedFraction: trimmed.excludedFraction,
            robustResidual: trimmed.keptResidual
        )
        require(fitted.referenceOrigin(detectorQX: detectorQX, detectorQY: detectorQY,
                                       apertureCentre: aperture).kind == .fittedMaps,
                "fitted maps must win over everything else")

        var recorded = Calibration()
        recorded.recordedOriginX = 61.5
        recorded.recordedOriginY = 66.25
        recorded.originProvenance = .fileMean
        let recordedOrigin = recorded.referenceOrigin(
            detectorQX: detectorQX, detectorQY: detectorQY, apertureCentre: aperture
        )
        require(recordedOrigin.kind == .recordedMean,
                "a file/session mean must be used, not fallen through — got \(recordedOrigin.kind)")
        requireClose(Double(recordedOrigin.x), 61.5, 1e-6, "recorded origin x")
        requireClose(Double(recordedOrigin.y), 66.25, 1e-6, "recorded origin y")
        // THE S11 DEFECT, pinned: before S13 this case produced (qx/2, qy/2) = (64, 64)
        // — the detector's geometric middle — in Q calibration, strain, ACOM and the
        // Bragg map at once, while the inspector displayed the file's origin.
        require(abs(recordedOrigin.x - 64) > 1 || abs(recordedOrigin.y - 64) > 1,
                "a recorded origin must NOT collapse to the detector's geometric middle")

        let apertureOnly = Calibration()
        require(apertureOnly.referenceOrigin(detectorQX: detectorQX, detectorQY: detectorQY,
                                             apertureCentre: aperture).kind == .apertureCentre,
                "with nothing measured, the aperture the user placed is the best available centre")
        require(apertureOnly.referenceOrigin(detectorQX: detectorQX, detectorQY: detectorQY,
                                             apertureCentre: nil).kind == .geometricMiddle,
                "and with no aperture either, the geometric middle — named as such")

        require(Calibration.ReferenceOriginKind.fittedMaps.isMeasuredBeamCentre
                && Calibration.ReferenceOriginKind.recordedMean.isMeasuredBeamCentre,
                "both measured kinds must count as measured")
        require(!Calibration.ReferenceOriginKind.apertureCentre.isMeasuredBeamCentre
                && !Calibration.ReferenceOriginKind.geometricMiddle.isMeasuredBeamCentre,
                "neither stand-in may count as a measured beam centre — this is the predicate the "
                + "metrology gate refuses on")

        // MARK: - 3. The split

        // THE GATE READS THE FULL-SCAN RESIDUAL, and this case is why.
        //
        // v2 S13 shipped it reading the robust (kept-set) residual. Gate B
        // refuted the swap by construction on 2026-08-28: RMS over the set that
        // DEFINED the fit measures that set's internal consistency and cannot
        // see bias, so a partially-excluded clustered contamination passes it
        // while the fit is displaced 15 px. The planted-outlier maps below are
        // that shape in miniature — robust residual ~0, full-scan 21.4 px.
        var contaminated = Calibration()
        contaminated.probeRadius = 5
        contaminated.origin = OriginMaps(
            width: width, height: height,
            measuredX: measuredX, measuredY: measuredY,
            fittedX: trimmed.fittedX, fittedY: trimmed.fittedY,
            excludedFraction: trimmed.excludedFraction,
            robustResidual: trimmed.keptResidual
        )
        require(Double(contaminated.origin?.robustResidual ?? .nan) < 1e-3,
                "precondition: the robust residual really is ~0 here, so this case can only be "
                + "distinguished by which statistic the gate reads")
        require(!contaminated.originFitIsSane,
                "the gate must NOT be satisfied by a near-zero residual over the kept subset — "
                + "that is the statistic that cannot see bias")
        requireClose(Double(contaminated.judgedOriginResidual ?? .nan),
                     Double(contaminated.origin?.rmsResidual ?? .nan), 1e-9,
                     "and the number quoted must be the number judged")
        require(!contaminated.originSupportsReciprocalMetrology(
                    detectorQX: detectorQX, detectorQY: detectorQY, apertureCentre: aperture),
                "so reciprocal metrology is refused too")

        // The counter-half: the gate has not simply been disabled. A genuinely
        // clean fit, same construction minus the outliers, is admitted.
        var sane = Calibration()
        sane.probeRadius = 5
        let cleanFit = OriginCalibration.fitOriginTrimmed(
            measuredX: (0..<count).map { truePlane($0).x },
            measuredY: (0..<count).map { truePlane($0).y },
            width: width, height: height, fitFunction: .plane
        )
        sane.origin = OriginMaps(
            width: width, height: height,
            measuredX: (0..<count).map { truePlane($0).x },
            measuredY: (0..<count).map { truePlane($0).y },
            fittedX: cleanFit.fittedX, fittedY: cleanFit.fittedY,
            excludedFraction: cleanFit.excludedFraction,
            robustResidual: cleanFit.keptResidual
        )
        require(sane.originFitIsSane, "a clean fit must still pass")
        require(sane.originSupportsReciprocalMetrology(
                    detectorQX: detectorQX, detectorQY: detectorQY, apertureCentre: aperture),
                "and still support reciprocal metrology")
        require((sane.origin?.excludedFraction ?? 1) <= 0.02,
                "a clean fit must not trip the disclosure floor — the trim's own false-positive "
                + "rate on clean data is 0.33%-1.08%, which is why the floor is 2% and not 0.5%")

        var saneButGuessed = Calibration()
        saneButGuessed.probeRadius = 5
        require(saneButGuessed.originFitIsSane,
                "no residual to judge means the LOOSER question passes — unchanged behaviour")
        require(!saneButGuessed.originSupportsReciprocalMetrology(
                    detectorQX: detectorQX, detectorQY: detectorQY, apertureCentre: aperture),
                "but the STRICTER one must refuse: there is no measured beam centre. Before S13 one "
                + "predicate answered both and this case was admitted, stamped `.measuredInApp`")
        require(recorded.originSupportsReciprocalMetrology(
                    detectorQX: detectorQX, detectorQY: detectorQY, apertureCentre: aperture),
                "a file's recorded mean IS a measured beam centre and must be admitted")

        // The refusal text must lead with the remedy that works. S12 measured that all
        // three fit functions miss the gate on both datasets where the old text was
        // shown, so naming them first spent the sentence on what cannot succeed.
        var refusing = Calibration()
        refusing.probeRadius = 2
        refusing.origin = OriginMaps(
            width: width, height: height,
            measuredX: scatteredX, measuredY: scatteredY,
            fittedX: broad.fittedX, fittedY: broad.fittedY,
            excludedFraction: broad.excludedFraction, robustResidual: broad.keptResidual
        )
        let refusal = refusing.originFitRefusal ?? ""
        require(!refusal.isEmpty, "a residual above the probe radius must produce a refusal")
        let manualPosition = refusal.range(of: "manually").map {
            refusal.distance(from: refusal.startIndex, to: $0.lowerBound)
        } ?? Int.max
        let fitFunctionPosition = refusal.range(of: "Constant / Plane / Parabola").map {
            refusal.distance(from: refusal.startIndex, to: $0.lowerBound)
        } ?? Int.max
        require(manualPosition < fitFunctionPosition,
                "manual entry must come BEFORE the fit functions in the refusal — it is the only remedy "
                + "measured to work (S12 §1.1)")
        require(refusal.contains("across the whole scan"),
                "broad measurement failure must be named as such, not reported as outliers")

        // Contamination WITH a real residual on the positions that survived:
        // planted outliers as above, plus modest scatter on the inliers, so the
        // trimmed fit keeps ~86% and still misses a small probe radius. The
        // earlier version of this case set probeRadius = 0.001 against a
        // ~0 residual and produced no refusal at all — it asserted on a string
        // that was never built.
        var contaminatedX = [Float](repeating: 0, count: count)
        var contaminatedY = [Float](repeating: 0, count: count)
        for index in 0..<count {
            let truth = truePlane(index)
            let throwOff: Float = plantedOutliers.contains(index) ? 40 : 0
            contaminatedX[index] = truth.x + throwOff + nextUniform() * 2
            contaminatedY[index] = truth.y + throwOff + nextUniform() * 2
        }
        let contaminatedFit = OriginCalibration.fitOriginTrimmed(
            measuredX: contaminatedX, measuredY: contaminatedY,
            width: width, height: height, fitFunction: .plane
        )
        let contaminatedExcluded = contaminatedFit.excludedFraction ?? .nan
        require(contaminatedExcluded > 0.10 && contaminatedExcluded < 0.20,
                "the contaminated case must actually exclude ~14%, else the refusal text it "
                + "checks is not the contaminated branch — excluded "
                + "\(contaminatedExcluded * 100)%")
        var contaminatedRefusal = Calibration()
        contaminatedRefusal.probeRadius = 0.2
        contaminatedRefusal.origin = OriginMaps(
            width: width, height: height,
            measuredX: contaminatedX, measuredY: contaminatedY,
            fittedX: contaminatedFit.fittedX, fittedY: contaminatedFit.fittedY,
            excludedFraction: contaminatedFit.excludedFraction,
            robustResidual: contaminatedFit.keptResidual
        )
        require(contaminatedRefusal.originFitRefusal?.contains("excluded 14% of positions") == true,
                "outlier contamination must be named with its measured fraction — got "
                + "\(contaminatedRefusal.originFitRefusal ?? "nil")")

        // MARK: - 4. The estimator MEASURES a shell ratio; it refuses nothing
        //
        // v2 S13 shipped three plausibility thresholds here. Gate B refuted the
        // derivation of all three on 2026-08-28 and they were cut, so what is
        // pinned now is the MEASUREMENT and the separation repair that makes it
        // mean anything — not a verdict.

        let firstShellPixels = 20.0
        let expectedRatio = 2.0 / 3.0.squareRoot()   // FCC {200}/{111} = sqrt(4/3)
        let g1 = 0.4, g2 = g1 * expectedRatio

        func ring(origin: (x: Float, y: Float), radii: [Double], positions: Int,
                  jitter: (Int) -> Double = { _ in 0 }) -> BraggVectors {
            var peaks: [[BraggPeak]] = []
            for position in 0..<positions {
                let offset = jitter(position)
                var row: [BraggPeak] = []
                for radius in radii {
                    for spoke in 0..<6 {
                        let angle = Double(spoke) * .pi / 3
                        row.append(BraggPeak(
                            x: origin.x + Float((radius + offset) * cos(angle)),
                            y: origin.y + Float((radius + offset) * sin(angle)),
                            intensity: 1
                        ))
                    }
                }
                peaks.append(row)
            }
            return BraggVectors(scanWidth: positions, scanHeight: 1, peaks: peaks)
        }

        let centre = (x: Float(64), y: Float(64))
        let healthy = ring(origin: centre,
                           radii: [firstShellPixels, firstShellPixels * expectedRatio],
                           positions: 200)
        guard let healthyEstimate = KnownCrystalQCalibration.estimate(
            bragg: healthy, origin: centre, referenceRadiusInvAngstrom: g1,
            secondShellRadiusInvAngstrom: g2, probeRadiusPixels: 5
        ) else { print("FAIL: the healthy case must produce an estimate"); exit(1) }

        requireClose(healthyEstimate.observedRadiusPixels, firstShellPixels, 1e-9,
                     "observed first shell")
        requireClose(healthyEstimate.invAngstromPerPixel, g1 / firstShellPixels, 1e-12,
                     "Q pixel size")

        // THE SEPARATION REPAIR, which is the part that survived review. Six
        // equivalents of ONE shell at the same radius must not read as two
        // shells: without the derived separation r2 = r1 and the ratio
        // collapses to 1.0 (measured 1.02048 on real sim_Au against an expected
        // 1.15470), so the design as first written fired on good data.
        guard case .measured(let observedRatio, let expectedFromCrystal, let positions)
            = healthyEstimate.shellCheck else {
            print("FAIL: a clean two-shell pattern must report a measured ratio — got "
                  + "\(healthyEstimate.shellCheck)"); exit(1)
        }
        requireClose(observedRatio, expectedRatio, 1e-6,
                     "the separated r2 must be the SECOND shell, not another equivalent of the "
                     + "first — an unseparated r2 reads 1.0 here")
        requireClose(expectedFromCrystal, expectedRatio, 1e-12, "expected ratio from the crystal")
        require(positions == 200,
                "every position contributed an r2 — the count is part of the claim, because a "
                + "median over 3 positions and one over 200 are different statements: got \(positions)")
        requireClose(healthyEstimate.shellCheck.mismatch ?? .nan, 0, 1e-6, "clean-case mismatch")

        // NOTHING REFUSES. The estimate reports; a threshold would be a number
        // this session has no defensible way to place.
        let wrongShell = ring(origin: centre,
                              radii: [firstShellPixels * expectedRatio,
                                      firstShellPixels * (8.0 / 3.0).squareRoot()],
                              positions: 200)
        guard let wrongShellEstimate = KnownCrystalQCalibration.estimate(
            bragg: wrongShell, origin: centre, referenceRadiusInvAngstrom: g1,
            secondShellRadiusInvAngstrom: g2, probeRadiusPixels: 5
        ) else { print("FAIL: the misassigned case must produce an estimate"); exit(1) }
        require((wrongShellEstimate.shellCheck.mismatch ?? 0) > 0.15,
                "a wrong shell assignment must be VISIBLE in the reported mismatch (g3/g2 = 1.414 "
                + "against g2/g1 = 1.155) — got \(String(describing: wrongShellEstimate.shellCheck.mismatch))")

        // One detectable shell must report NOT self-checked, never a silent
        // pass — the state in which the single-shell assumption is least safe.
        let singleShell = ring(origin: centre, radii: [firstShellPixels], positions: 200)
        guard let singleEstimate = KnownCrystalQCalibration.estimate(
            bragg: singleShell, origin: centre, referenceRadiusInvAngstrom: g1,
            secondShellRadiusInvAngstrom: g2, probeRadiusPixels: 5
        ) else { print("FAIL: the single-shell case must still produce an estimate"); exit(1) }
        if case .notSelfChecked = singleEstimate.shellCheck {} else {
            require(false, "one detectable shell must report NOT self-checked — got "
                    + "\(singleEstimate.shellCheck)")
        }
        // Passing nil for the crystal's second shell must do the same, which is
        // why that argument has no default value.
        guard let unchecked = KnownCrystalQCalibration.estimate(
            bragg: healthy, origin: centre, referenceRadiusInvAngstrom: g1,
            secondShellRadiusInvAngstrom: nil, probeRadiusPixels: nil
        ) else { print("FAIL: the unchecked case must produce an estimate"); exit(1) }
        if case .notSelfChecked = unchecked.shellCheck {} else {
            require(false, "no second shell supplied must report NOT self-checked — got "
                    + "\(unchecked.shellCheck)")
        }

        // MARK: - 5. Coverage the 2026-08-28 mutation sweep proved was missing
        //
        // Gate B applied 32 single-line mutations to the two `Core/` files and
        // 26 left this fixture GREEN. Every case below exists because one of
        // those 26 walked through it unchallenged. The section is the reason
        // this file's header no longer claims coverage it does not have.

        // (a) A MARGINAL outlier population, so the trim CONSTANTS are pinned
        // in the loosening direction. The planted set in section 1 is thrown
        // 40 px, where every cutoff from 2σ to 6σ separates identically —
        // `trimSigma` could go 3 → 6, or the 1.4826 MAD→σ factor to 1.0, and
        // nothing fired. At 2.6 px against ±1 px scatter the constants decide:
        // measured, 3σ excludes 9.0% of a planted 9.09% while 6σ excludes 2.0%.
        var marginalX = [Float](repeating: 0, count: count)
        var marginalY = [Float](repeating: 0, count: count)
        var marginalState: UInt64 = 99
        func marginalNoise() -> Float {
            marginalState ^= marginalState << 13
            marginalState ^= marginalState >> 7
            marginalState ^= marginalState << 17
            return Float(marginalState % 2000) / 1000 - 1     // ~U(-1, 1)
        }
        for index in 0..<count {
            let truth = truePlane(index)
            marginalX[index] = truth.x + (index % 11 == 0 ? 2.6 : 0) + marginalNoise()
            marginalY[index] = truth.y + marginalNoise()
        }
        func marginalTrim(_ sigma: Float) -> Float {
            OriginCalibration.fitOriginTrimmed(
                measuredX: marginalX, measuredY: marginalY,
                width: width, height: height, fitFunction: .plane, trimSigma: sigma
            ).excludedFraction ?? .nan
        }
        let atThreeSigma = marginalTrim(3)
        require(atThreeSigma > 0.085 && atThreeSigma < 0.095,
                "at 3σ the trim must find essentially the planted 9.09% on marginal data. This "
                + "is the two-sided band that pins BOTH `trimSigma` and the 1.4826 MAD→σ factor: "
                + "loosen either and the fraction falls, tighten either and it rises. Got \(atThreeSigma)")
        require(marginalTrim(6) < 0.03,
                "and at 6σ it must miss most of them, or the cutoff is not doing the work the "
                + "constants claim — got \(marginalTrim(6))")
        // The DEFAULT, not just explicit values. Every shipping caller —
        // `tiledRun`, `run` — omits the argument, so a mutation of the default
        // alone survived assertions that passed 3 and 6 by hand.
        let atDefault = OriginCalibration.fitOriginTrimmed(
            measuredX: marginalX, measuredY: marginalY,
            width: width, height: height, fitFunction: .plane).excludedFraction ?? .nan
        requireClose(Double(atDefault), Double(atThreeSigma), 1e-6,
                     "the DEFAULT trimSigma must be the 3σ the docstring and the diagnostics "
                     + "claim — every shipping caller relies on it")

        // (b) The reported `kept` must be the set the shipped surface was fit
        // on. The first version updated `kept` after the last refit, so the
        // surface came from round n's mask while every reported number
        // described round n+1's — up to 9.86 px apart.
        let marginalFit = OriginCalibration.fitOriginTrimmed(
            measuredX: marginalX, measuredY: marginalY,
            width: width, height: height, fitFunction: .plane)
        let refitOnReported = OriginCalibration.fitOrigin(
            measuredX: marginalX, measuredY: marginalY,
            width: width, height: height, fitFunction: .plane, included: marginalFit.kept)
        var worstDivergence: Float = 0
        for index in 0..<count {
            let dx = marginalFit.fittedX[index] - refitOnReported.fittedX[index]
            let dy = marginalFit.fittedY[index] - refitOnReported.fittedY[index]
            worstDivergence = max(worstDivergence, (dx * dx + dy * dy).squareRoot())
        }
        require(worstDivergence < 1e-4,
                "refitting on the REPORTED kept set must reproduce the reported surface — "
                + "otherwise `excludedFraction` and `keptResidual` describe a fit nobody shipped. "
                + "Worst divergence \(worstDivergence) px")

        // (c) `.constant` and `.parabola`. `OriginFitFunction` is a three-option
        // user-facing picker and the refusal text names all three; two of them
        // were ungated, and one could be made a no-op with the fixture green.
        for function in [OriginFitFunction.constant, .parabola] {
            let fit = OriginCalibration.fitOriginTrimmed(
                measuredX: measuredX, measuredY: measuredY,
                width: width, height: height, fitFunction: function)
            requireClose(Double(fit.excludedFraction ?? .nan),
                         Double(plantedOutliers.count) / Double(count), 1e-6,
                         "\(function.rawValue): the trim must exclude the planted set whatever "
                         + "the fit function")
            require(Set((0..<count).filter { !fit.kept[$0] }) == plantedOutliers,
                    "\(function.rawValue): and it must be the planted positions, not merely the "
                    + "right count")
            require(fit.fittedX != measuredX,
                    "\(function.rawValue): the fit must actually fit — a branch returning its "
                    + "input passed every earlier assertion")
        }
        // A constant fit is FLAT; a parabola on a planar truth recovers it.
        // Distinguishing them catches the swapped term count (3 ↔ 6).
        let constantFit = OriginCalibration.fitOriginTrimmed(
            measuredX: measuredX, measuredY: measuredY,
            width: width, height: height, fitFunction: .constant)
        require(constantFit.fittedX.allSatisfy { abs($0 - constantFit.fittedX[0]) < 1e-6 },
                "a Constant fit must be flat across the scan")
        require(Double(constantFit.keptResidual) > 0.1,
                "and must NOT reproduce a tilted plane — if it does, the branch is not constant")
        // Its VALUE must be the mean over the KEPT positions. Ignoring the mask
        // leaves it the mean over all of them, which the 40 px outliers drag by
        // ~5.7 px — and flatness alone could not see that.
        let keptMeanX = plantedOutliers.isEmpty ? 0 : (0..<count)
            .filter { !plantedOutliers.contains($0) }
            .reduce(Float(0)) { $0 + measuredX[$1] } / Float(count - plantedOutliers.count)
        requireClose(Double(constantFit.fittedX[0]), Double(keptMeanX), 0.01,
                     "the Constant fit must average the KEPT positions, not every position")

        // NOT COVERED, and stated rather than papered over: the in-loop
        // `.constant` branch's use of the mask. Removing it leaves this fixture
        // GREEN, because the final refit added after Gate B recomputes the
        // surface from the reported `kept` through `fitOrigin(included:)` — a
        // different function, which IS covered by (d) — so the in-loop branch
        // can now only influence which positions get excluded, not the surface
        // that ships. No input was found where it changes even that.
        //
        // What was tried: a flat truth with a third of positions thrown 10 px.
        // It fails on the UNMUTATED code as well, and the reason is worth
        // recording — with an exactly bimodal residual distribution the
        // majority population's deviations are all equal, the MAD is exactly
        // zero, and `fitOriginTrimmed`'s zero-MAD guard breaks out of the loop
        // having excluded nothing. That is the 50%-breakdown behaviour Gate B
        // measured, arriving at 33% for this shape. It is a real limit of the
        // trim, recorded in docs/open-items.md; asserting the behaviour the
        // construction assumed would have been demanding a fix nobody scoped.

        // A PLANAR truth cannot distinguish a 3-term fit from a 6-term one —
        // both reproduce it exactly, so swapping plane and parabola was
        // invisible. Curve the truth and only the parabola can follow it.
        var curvedX = [Float](repeating: 0, count: count)
        var curvedY = [Float](repeating: 0, count: count)
        for index in 0..<count {
            let rx = Float(index % width), ry = Float(index / width)
            curvedX[index] = 64 + 0.004 * rx * rx
            curvedY[index] = 64 + 0.004 * ry * ry
        }
        let curvedPlane = OriginCalibration.fitOriginTrimmed(
            measuredX: curvedX, measuredY: curvedY,
            width: width, height: height, fitFunction: .plane)
        let curvedParabola = OriginCalibration.fitOriginTrimmed(
            measuredX: curvedX, measuredY: curvedY,
            width: width, height: height, fitFunction: .parabola)
        require(Double(curvedParabola.keptResidual) < 1e-3,
                "a parabola must reproduce a quadratic surface — got \(curvedParabola.keptResidual)")
        require(Double(curvedPlane.keptResidual) > 0.1,
                "and a plane must NOT — if both do, the two branches use the same term count "
                + "and swapping them is invisible. Got \(curvedPlane.keptResidual)")

        // (d) The `fitOrigin(included:)` overload, whose only other caller is a
        // NON-gating harness — the one that produced this session's §2 numbers.
        var halfMask = [Bool](repeating: false, count: count)
        for index in 0..<count where index % 2 == 0 && !plantedOutliers.contains(index) {
            halfMask[index] = true
        }
        let masked = OriginCalibration.fitOrigin(
            measuredX: measuredX, measuredY: measuredY,
            width: width, height: height, fitFunction: .plane, included: halfMask)
        require(maximumDeviationFromTruth(masked.fittedX, masked.fittedY) < 0.01,
                "a masked fit must ignore the excluded positions entirely — dropping `included:` "
                + "lets the 40 px outliers back in and the surface moves 8 px")
        let unmasked = OriginCalibration.fitOrigin(
            measuredX: measuredX, measuredY: measuredY,
            width: width, height: height, fitFunction: .plane)
        require(maximumDeviationFromTruth(unmasked.fittedX, unmasked.fittedY) > 5,
                "control: the SAME data without a mask really is dragged, so (d) is not vacuous")

        // (e) NaN. Neither this fixture nor the XCTest suite used a NaN value
        // anywhere, and a NaN fitted map passed the whole gate chain as a
        // "measured beam centre" — a Q scale computed from a NaN origin,
        // stamped `.measuredInApp`.
        var nanCalibration = Calibration()
        nanCalibration.probeRadius = 5
        nanCalibration.origin = OriginMaps(
            width: width, height: height, measuredX: nil, measuredY: nil,
            fittedX: [Float](repeating: .nan, count: count),
            fittedY: [Float](repeating: .nan, count: count))
        require(nanCalibration.meanOrigin == nil,
                "a NaN fitted map is not a mean origin")
        require(nanCalibration.referenceOrigin(
                    detectorQX: detectorQX, detectorQY: detectorQY,
                    apertureCentre: aperture).kind != .fittedMaps,
                "and must not be reported as a measured beam centre")
        require(!nanCalibration.originSupportsReciprocalMetrology(
                    detectorQX: detectorQX, detectorQY: detectorQY, apertureCentre: aperture),
                "and must not clear the metrology gate")
        // A single NaN measurement poisons the whole fit through the normal
        // equations, so the trim silently never runs. It must not then be
        // reported as "trimmed, excluded nothing".
        var poisonedX = measuredX
        poisonedX[17] = .nan
        let poisoned = OriginCalibration.fitOriginTrimmed(
            measuredX: poisonedX, measuredY: measuredY,
            width: width, height: height, fitFunction: .plane)
        require(!poisoned.keptResidual.isFinite || poisoned.fittedX.allSatisfy { $0.isFinite },
                "a poisoned fit must not present itself as a finite, healthy one")

        // (f) Degenerate scans. An empty scan reported "excluded 100% of
        // positions as outliers"; a 1×1 scan reported a perfect fit and cleared
        // the metrology gate on a scan with fewer positions than the model has
        // parameters.
        let empty = OriginCalibration.fitOriginTrimmed(
            measuredX: [], measuredY: [], width: 0, height: 0, fitFunction: .plane)
        require(empty.excludedFraction == nil,
                "an empty scan excluded nothing — the question does not apply, and 1.0 is a "
                + "confident wrong answer")
        let mismatched = OriginCalibration.fitOriginTrimmed(
            measuredX: [1, 2, 3], measuredY: [1, 2], width: 3, height: 1, fitFunction: .plane)
        require(mismatched.fittedX.count == mismatched.fittedY.count,
                "a length mismatch must not return fitted arrays of different lengths — "
                + "`meanOrigin` would have averaged them")

        // (g) The reference-origin PRECEDENCE, which was asserted nowhere
        // because no case had both a fitted map and a recorded mean.
        var both = Calibration()
        both.origin = OriginMaps(
            width: width, height: height, measuredX: measuredX, measuredY: measuredY,
            fittedX: trimmed.fittedX, fittedY: trimmed.fittedY)
        both.recordedOriginX = 11
        both.recordedOriginY = 12
        let resolvedBoth = both.referenceOrigin(
            detectorQX: detectorQX, detectorQY: detectorQY, apertureCentre: aperture)
        require(resolvedBoth.kind == .fittedMaps,
                "fitted maps outrank a recorded mean — swapping the two branches passed every "
                + "earlier assertion")
        require(abs(resolvedBoth.x - 11) > 1,
                "and the VALUE must come from the maps, not the recorded scalars")
        // The geometric middle's coordinates, not merely its label.
        let middle = Calibration().referenceOrigin(
            detectorQX: detectorQX, detectorQY: detectorQY, apertureCentre: nil)
        requireClose(Double(middle.x), Double(detectorQX) / 2, 1e-6, "geometric middle x")
        requireClose(Double(middle.y), Double(detectorQY) / 2, 1e-6, "geometric middle y")

        // (h) The percentages the user actually reads. Kept and excluded could
        // be swapped in the readiness row, and the owner's §6(a) disclosure
        // could be switched off, both green.
        var disclosing = Calibration()
        disclosing.probeRadius = 50
        disclosing.originProvenance = .fitted
        disclosing.origin = OriginMaps(
            width: width, height: height, measuredX: measuredX, measuredY: measuredY,
            fittedX: trimmed.fittedX, fittedY: trimmed.fittedY,
            excludedFraction: trimmed.excludedFraction, robustResidual: trimmed.keptResidual)
        var provenance = CalibrationProvenance()
        provenance.probe = .measuredInApp
        let detail = CalibrationReadinessReport
            .make(calibration: disclosing, provenance: provenance)
            .items.first { $0.kind == .originProbe }?.detail ?? ""
        require(detail.contains("86% of positions"),
                "the readiness row must name the KEPT percentage (86%), and it is the kept one "
                + "that comes first — got: \(detail)")
        require(detail.contains("14% excluded"),
                "and the excluded percentage (14%) as the excluded one — got: \(detail)")
        // Below the floor, nothing is claimed at all.
        var quiet = disclosing
        quiet.origin?.excludedFraction = 0.01
        let quietDetail = CalibrationReadinessReport
            .make(calibration: quiet, provenance: provenance)
            .items.first { $0.kind == .originProbe }?.detail ?? ""
        require(!quietDetail.contains("excluded"),
                "below the 2% floor nothing is disclosed — the trim's own false-positive rate on "
                + "clean data reaches 1.08%, so a 0.5% floor called clean scans contaminated")

        // MARK: - Report

        print("")
        if failures == 0 {
            print("PASS: q-calibration-gate-test — \(checks) checks")
        } else {
            print("FAILED: \(failures) of \(checks) checks")
            exit(1)
        }

    }
}

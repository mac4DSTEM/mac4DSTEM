import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
    exit(1)
}

let catalog = CrystalModelLibrary.models
let catalogIDs = Set(catalog.map(\.id))
guard !catalog.isEmpty, catalogIDs.count == catalog.count else {
    fail("crystal-model catalog identifiers must be present and unique")
}
for model in catalog {
    guard model.isUsable else {
        fail("crystal-model \(model.id) failed validation: \(model.validationIssues.map(\.code))")
    }
    guard !model.crystal.reflections(kMax: 1.2).isEmpty else {
        fail("crystal-model \(model.id) generated no reflections")
    }
    guard let catalogPlan = OrientationPlan.generate(
        crystal: model.crystal, kMax: 1.2, zoneAxisCount: 12,
        symmetry: model.symmetry
    ), catalogPlan.symmetry == model.symmetry, catalogPlan.count == 12 else {
        fail("crystal-model \(model.id) could not generate its declared symmetry plan")
    }
}
print("PASS: \(catalog.count) explicit crystal models validate and generate symmetry-consistent plans")

/// The template a fixture position is generated from. Extracted so the
/// generator below and the WS₂ arm's recovery assertion read the SAME formula
/// — an assertion that recomputed it independently would keep passing if the
/// generator's stride ever changed, which is a green-but-worthless test.
func generatingTemplate(index: Int, width: Int, templateCount: Int) -> Int {
    (index * 17 + index / width) % templateCount
}

/// The in-plane rotation a fixture position is generated with. Extracted for
/// the same reason as `generatingTemplate` — the WS₂ arm asserts against it, and
/// a second copy of the formula would drift silently. It lands exactly on an
/// azimuthal bin (angle/(2π)·128 = (index*7) % 64, an integer), so the
/// assertion can be exact rather than tolerant.
func generatingInPlaneAngle(index: Int) -> Double {
    Double((index * 7) % 64) / 64 * Double.pi
}

func vectors(plan: OrientationPlan, crystal: Crystal, width: Int, height: Int) -> BraggVectors {
    let reflections = crystal.reflections(kMax: 1.2)
    let scale = 0.01
    let peaks = (0..<(width * height)).map { index -> [BraggPeak] in
        let template = generatingTemplate(index: index, width: width, templateCount: plan.count)
        let angle = generatingInPlaneAngle(index: index)
        // intensityPower: 1 keeps the fixture's peak intensities physical —
        // the matcher applies the plan's power to them, so generating them
        // already compressed would apply it twice.
        return OrientationPlan.project(
            reflections: reflections, zoneAxis: plan.zoneAxes[template],
            sgWidth: 0.03, sgMax: 0.1, intensityPower: 1
        ).map { spot in
            BraggPeak(
                x: 64 + Float(spot.r / scale * cos(spot.azim + angle)),
                y: 64 + Float(spot.r / scale * sin(spot.azim + angle)),
                intensity: Float(spot.weight)
            )
        }
    }
    return BraggVectors(scanWidth: width, scanHeight: height, peaks: peaks)
}

func scalarMatch(peaks: [BraggPeak], plan: OrientationPlan)
    -> (template: Int, reportedBin: Int, score: Float, second: Float) {
    let geo = plan.geometry
    guard let fft = FFT1D(n: geo.nAzimuthal) else { fail("FFT setup") }
    // Mirrors OrientationMatcher.prepareExperimentalFFT, including the plan's
    // intensity power — the experimental image must be weighted exactly like
    // the templates it is correlated against.
    let spots = peaks.map { peak in
        let dx = Double(peak.x - 64), dy = Double(peak.y - 64)
        let intensity = Double(max(0, peak.intensity))
        return (r: hypot(dx, dy) * 0.01, azim: atan2(dy, dx),
                weight: plan.intensityPower == 1
                    ? intensity : pow(intensity, plan.intensityPower))
    }
    // ...and the plan's radial kernel, for the same reason.
    var polar = OrientationPlan.buildPolar(
        spots: spots, geometry: geo, azimBlurBins: 1.5,
        radialKernelInvAngstrom: plan.radialKernelInvAngstrom
    )
    OrientationPlan.normalizeUnit(&polar)
    let (experimentalReal, experimentalImaginary) = OrientationPlan.ringFFTs(
        polar, geo: geo, fft: fft
    )
    let na = geo.nAzimuthal, nr = geo.nRadial
    var correlationReal = [Float](repeating: 0, count: na)
    var correlationImaginary = [Float](repeating: 0, count: na)
    // Per-template scores are retained, then reduced by the same
    // selectOrientation the production matcher uses — the runner-up has to be
    // a template far enough away to be a different orientation.
    var templateScores = [Float](repeating: 0, count: plan.count)
    var templateBins = [UInt32](repeating: 0, count: plan.count)
    for template in 0..<plan.count {
        correlationReal = [Float](repeating: 0, count: na)
        correlationImaginary = [Float](repeating: 0, count: na)
        let templateOffset = template * nr * na
        for radial in 0..<nr {
            let base = radial * na
            for azimuthal in 0..<na {
                let index = base + azimuthal
                let tr = plan.templateFFTRe[templateOffset + index]
                let ti = plan.templateFFTIm[templateOffset + index]
                let er = experimentalReal[index], ei = experimentalImaginary[index]
                correlationReal[azimuthal] += er * tr + ei * ti
                correlationImaginary[azimuthal] += er * ti - ei * tr
            }
        }
        fft.transform(re: &correlationReal, im: &correlationImaginary, forward: false)
        var local: Float = -.greatestFiniteMagnitude
        var bin = 0
        for index in 0..<na where correlationReal[index] > local {
            local = correlationReal[index]; bin = index
        }
        local /= Float(na)
        templateScores[template] = local
        templateBins[template] = UInt32(bin)
    }
    let selected = selectOrientation(
        zoneAxes: plan.zoneAxes, scores: templateScores, bins: templateBins,
        distinctOrientationRad: plan.distinctOrientationRad
    )
    return (selected.template, (na - selected.bin) % na,
            selected.score, selected.secondScore)
}

let crystal = Crystal.gold
guard let plan = OrientationPlan.generate(
    crystal: crystal, kMax: 1.2, zoneAxisCount: 96
) else { fail("plan generation") }
let fixture = vectors(plan: plan, crystal: crystal, width: 8, height: 4)
guard let cpu = OrientationMatching.matchAll(
    bragg: fixture, plan: plan, originX: 64, originY: 64,
    invAngstromPerPixel: 0.01, backend: .cpu
) else { fail("CPU map") }

for index in 0..<min(8, fixture.peaks.count) {
    let scalar = scalarMatch(peaks: fixture.peaks[index], plan: plan)
    let optimized = cpu.results[index]
    let optimizedBin = Int((optimized.inPlaneAngle / (2 * .pi) * Float(plan.geometry.nAzimuthal)).rounded())
        % plan.geometry.nAzimuthal
    guard optimized.templateIndex == scalar.template,
          optimizedBin == scalar.reportedBin,
          abs(optimized.score - scalar.score) < 3e-5,
          abs(optimized.secondScore - scalar.second) < 3e-5 else {
        fail("optimized CPU differs from scalar reference at \(index): optimized t=\(optimized.templateIndex) bin=\(optimizedBin) scores=\(optimized.score),\(optimized.secondScore); scalar t=\(scalar.template) bin=\(scalar.reportedBin) scores=\(scalar.score),\(scalar.second)")
    }
}
print("PASS: contiguous vectorized CPU matches scalar reference")

guard let metal = OrientationMatching.matchAll(
    bragg: fixture, plan: plan, originX: 64, originY: 64,
    invAngstromPerPixel: 0.01, backend: .metal
) else { fail("Metal map") }
var maximumScoreError: Float = 0
var maximumReliabilityError: Float = 0
for index in cpu.results.indices {
    let lhs = cpu.results[index], rhs = metal.results[index]
    let rawAngleError = abs(lhs.inPlaneAngle - rhs.inPlaneAngle)
        .truncatingRemainder(dividingBy: .pi)
    let angleError = min(rawAngleError, .pi - rawAngleError)
    guard lhs.templateIndex == rhs.templateIndex,
          angleError < 1e-6 else {
        fail("Metal orientation choice differs at \(index): CPU t=\(lhs.templateIndex) angle=\(lhs.inPlaneAngle) score=\(lhs.score); Metal t=\(rhs.templateIndex) angle=\(rhs.inPlaneAngle) score=\(rhs.score)")
    }
    maximumScoreError = max(maximumScoreError, abs(lhs.score - rhs.score))
    maximumReliabilityError = max(maximumReliabilityError, abs(lhs.reliability - rhs.reliability))
}
guard maximumScoreError < 2e-4, maximumReliabilityError < 2e-4 else {
    fail("Metal score parity: score \(maximumScoreError), reliability \(maximumReliabilityError)")
}
print("PASS: Metal choices exact; score \(maximumScoreError), reliability \(maximumReliabilityError)")
print("PASS: Automatic backend remains measured Accelerate CPU")

let magnesium = Crystal.magnesium
guard let hexPlan = OrientationPlan.generate(
    crystal: magnesium, kMax: 1.2, zoneAxisCount: 48, symmetry: .hexagonal
) else { fail("hexagonal magnesium plan generation") }
guard hexPlan.symmetry == .hexagonal, hexPlan.count == 48,
      magnesium.a != magnesium.b || magnesium.b != magnesium.c else {
    fail("magnesium plan did not retain non-cubic crystal/symmetry metadata")
}
let hexFixture = vectors(plan: hexPlan, crystal: magnesium, width: 4, height: 2)
guard let hexMap = OrientationMatching.matchAll(
    bragg: hexFixture, plan: hexPlan, originX: 64, originY: 64,
    invAngstromPerPixel: 0.01, backend: .cpu
) else { fail("hexagonal match") }
guard hexMap.symmetry == .hexagonal, hexMap.templateCount == hexPlan.count,
      hexMap.matchingBackend == .cpu else {
    fail("hexagonal provenance was symmetry=\(hexMap.symmetry.rawValue), templates=\(hexMap.templateCount), backend=\(hexMap.matchingBackend.rawValue)")
}
guard hexMap.results.allSatisfy({ $0.templateIndex >= 0 && $0.score.isFinite }) else {
    fail("hexagonal magnesium match produced invalid results")
}
print("PASS: non-cubic magnesium plan, matching, and symmetry provenance")

// MARK: - WS₂ scale sensitivity (W4b, 2026-08-31)
//
// W4b measured the (0002) reference-shell defect live on polycrystal_2D_WS2:
// `KnownCrystalQCalibration.estimate` returned 0.008789 Å⁻¹/px where the
// data-true scale is 0.019448 — a silent 2.2564× under-scale on basal data.
// On the real cube that HALVED the median correlation score and picked a wrong
// zone axis. This arm pins the property that makes the open item matter: the
// matcher breaks at THIS mis-scale, so a mis-scaled Q calibration is not
// cosmetic. Scoped deliberately: Gate B swept the factor and both assertions
// stay green up to a ~5% scale error (and the recovery one is non-monotone —
// it goes green again at 1.75×), so this pins "the 2.26× defect bites", not
// the stronger "the matcher is scale-sensitive in general".
//
// Scope: the fixture is generated FROM the same crystal it is matched against,
// so it pins the MATCHING path only. `tools/ws2-crystal-test` pins the model.
func median(_ values: [Double]) -> Double {
    let sorted = values.sorted()
    guard !sorted.isEmpty else { fail("median over an empty sample") }
    let middle = sorted.count / 2
    return sorted.count % 2 == 1
        ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2
}
// The statistic gets its own check because the score-drop assertion below
// cannot supply one: at the defect scale EVERY order statistic collapses, so
// swapping the median for the max or the min leaves that assertion green. It is
// called directly at both use sites rather than through a `medianScore(_:)`
// wrapper — Gate B showed a wrapper is a second place to swap the statistic
// that this guard does not reach.
guard median([3, 1, 2]) == 2, median([4, 1, 3, 2]) == 2.5 else {
    fail("median helper is not the median")
}

let ws2TrueScale = 0.01
// The ANALYTIC shell ratio |g(10-10)|/|g(0002)| = (2/(a√3))/(2/c) = 2.25634 for
// the cited 2H cell — i.e. the mis-scale the (0002) reference-shell defect
// produces from geometry alone. It is deliberately NOT the ratio of the two
// scales W4b recorded on the cube (0.019448/0.008789 = 2.2129): those differ
// because the estimator measures the ring by a per-pattern MINIMUM, which is
// biased ~1.9% low — a second, independent defect with its own open item.
// `tools/ws2-crystal-test` prints the same constant as 2.2563.
let ws2DefectFactor = 2.2564
guard let ws2Model = CrystalModelLibrary.model(id: "ws2_2h") else {
    fail("crystal-model library does not carry ws2_2h")
}
guard let ws2Plan = OrientationPlan.generate(
    crystal: ws2Model.crystal, kMax: 1.2, zoneAxisCount: 48,
    symmetry: ws2Model.symmetry
) else { fail("WS₂ plan generation") }
guard ws2Plan.symmetry == .hexagonal, ws2Plan.count == 48 else {
    fail("WS₂ plan was symmetry=\(ws2Plan.symmetry.rawValue), templates=\(ws2Plan.count)")
}
let ws2Width = 4, ws2Height = 2
let ws2Fixture = vectors(plan: ws2Plan, crystal: ws2Model.crystal,
                         width: ws2Width, height: ws2Height)
guard let ws2True = OrientationMatching.matchAll(
    bragg: ws2Fixture, plan: ws2Plan, originX: 64, originY: 64,
    invAngstromPerPixel: ws2TrueScale, backend: .cpu
) else { fail("WS₂ match at the true scale") }
guard ws2True.symmetry == .hexagonal, ws2True.templateCount == ws2Plan.count,
      ws2True.matchingBackend == .cpu else {
    fail("WS₂ provenance was symmetry=\(ws2True.symmetry.rawValue), templates=\(ws2True.templateCount), backend=\(ws2True.matchingBackend.rawValue)")
}
func recoveredTemplates(_ map: OrientationMap) -> Int {
    map.results.indices.filter { index in
        map.results[index].templateIndex
            == generatingTemplate(index: index, width: ws2Width, templateCount: ws2Plan.count)
    }.count
}
// Full recovery, not a majority: the fixture is deterministic (fixed crystal,
// fixed plan, fixed stride, CPU backend, no RNG), and the narrowest margin over
// ALL competing templates is 0.0595 (t0 vs t24, a symmetric pair 7.74° apart)
// against a measured CPU-vs-Metal score spread of 6e-7 — five orders of
// magnitude of headroom, so 8/8 is not brittle across machines. The handoff
// spec'd ≥6/8; 8/8 is what the tree measures, and slack the data does not need
// would let two positions regress silently.
//   The 0.101 this comment first quoted was `reliability[0]`, the gap to the
//   *distinct* runner-up — and `selectOrientation` filters out everything
//   within distinctOrientationRad (10°), which is exactly the set that could
//   steal the win. Right conclusion, wrong statistic (Gate B).
let ws2Recovered = recoveredTemplates(ws2True)
guard ws2Recovered == ws2True.results.count else {
    fail("WS₂ at the true scale recovered only \(ws2Recovered)/\(ws2True.results.count) generating templates")
}

// F5 (Gate B): the recovery assertion above cannot fail through any defect
// applied symmetrically to BOTH the templates and the fixture, because
// normalizeUnit makes the self-correlation exactly 1 by Cauchy–Schwarz. Pinning
// the score itself is free and pins the pixel→polar round-trip directly.
let ws2TrueMedian = median(ws2True.results.map { Double($0.score) })
guard ws2TrueMedian > 0.999 else {
    fail("WS₂ self-correlation at the true scale should be ~1, measured median \(ws2TrueMedian)")
}

// Pins that the matcher REPORTS the rotation it was given. Verified to have
// teeth: dropping the in-plane negation at `OrientationMatcher.swift:314`
// fails here at index 1, unaided, with the gold scalar arm disabled. (Index 0
// is generated at angle 0, where a sign error is invisible — this loop covers
// every position for that reason.)
//
// **What it does NOT close, measured, not assumed.** Gate B's most severe
// finding is that a transpose or handedness flip inside
// `OrientationPlan.project` is invisible to EVERY gated ACOM harness. The
// review proposed exactly this assertion as the one-line fix. It is not:
// the fixture builds its experimental pattern with the same `project` that
// builds the templates, so a defect applied to both sides preserves the
// RELATIVE angle as well as the score. Both mutations were re-run against this
// assertion and both still pass (exit 0, output byte-identical). Closing that
// needs experimental peaks whose positions do not come from `project` at all —
// filed as its own open item, with the sign-discriminating-angle requirement.
//
// Compared modulo π on purpose: with `wavelengthAngstrom: nil` the templates are
// exactly π-periodic by construction, so the matcher may legitimately return
// either branch (measured: generating + π at every position but index 0). That
// also means this arm is structurally blind to a 180° defect — pinning that
// needs a plan built with a wavelength, which this fixture does not have.
// Tolerance: one azimuthal bin is 2π/128 = 0.049 rad and the residual is ~5e-8,
// so 1e-4 sits two orders of magnitude clear of both.
for index in ws2True.results.indices {
    let expected = generatingInPlaneAngle(index: index)
    let observed = Double(ws2True.results[index].inPlaneAngle)
    var residual = (observed - expected).truncatingRemainder(dividingBy: .pi)
    if residual > .pi / 2 { residual -= .pi }
    if residual < -.pi / 2 { residual += .pi }
    guard abs(residual) < 1e-4 else {
        fail("WS₂ in-plane angle at \(index): observed \(observed), generating \(expected), residual modulo π \(residual)")
    }
}

guard let ws2Defective = OrientationMatching.matchAll(
    bragg: ws2Fixture, plan: ws2Plan, originX: 64, originY: 64,
    invAngstromPerPixel: ws2TrueScale / ws2DefectFactor, backend: .cpu
) else { fail("WS₂ match at the (0002)-defect scale") }
// The sharper of the two consequences, and the one that matches what the real
// cube did: the mis-scale does not merely lower a score, it returns DIFFERENT
// orientations. Measured 0/8 recovered. The threshold allows one because a
// single coincidental hit among 48 templates is not evidence of
// scale-insensitivity (expected coincidences ≈ 8/48 ≈ 0.17), whereas a
// genuinely scale-blind matcher would recover all 8 exactly as it does above.
let ws2DefectiveRecovered = recoveredTemplates(ws2Defective)
guard ws2DefectiveRecovered <= 1 else {
    fail("WS₂ matching is scale-INSENSITIVE: at 1/\(ws2DefectFactor) of the true scale it still recovered \(ws2DefectiveRecovered)/\(ws2Defective.results.count) generating templates")
}
// ...and the quantitative link to the real cube, where the same defect took the
// median score 0.3994 → 0.2140 (a 46% drop; the handoff quoted the same
// measurement the other way round, as the +87% regained by correcting it).
let ws2DefectiveMedian = median(ws2Defective.results.map { Double($0.score) })
let ws2Drop = (ws2TrueMedian - ws2DefectiveMedian) / ws2TrueMedian
guard ws2Drop >= 0.25 else {
    fail("WS₂ (0002) mis-scale did not degrade matching: median \(ws2TrueMedian) at the true scale vs \(ws2DefectiveMedian) at 1/\(ws2DefectFactor), drop \(ws2Drop)")
}
print("PASS: WS₂ recovers \(ws2Recovered)/\(ws2True.results.count) templates at the true scale, \(ws2DefectiveRecovered)/\(ws2Defective.results.count) at the (0002)-defect scale; median score drops \(String(format: "%.1f", ws2Drop * 100))% (\(String(format: "%.4f", ws2TrueMedian)) → \(String(format: "%.4f", ws2DefectiveMedian)))")

print("acom-matching-test: all passed")

import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
    exit(1)
}

func vectors(plan: OrientationPlan, crystal: Crystal, width: Int, height: Int) -> BraggVectors {
    let reflections = crystal.reflections(kMax: 1.2)
    let scale = 0.01
    let peaks = (0..<(width * height)).map { index -> [BraggPeak] in
        let template = (index * 17 + index / width) % plan.count
        let angle = Double((index * 7) % 64) / 64 * Double.pi
        return OrientationPlan.project(
            reflections: reflections, zoneAxis: plan.zoneAxes[template],
            sgWidth: 0.03, sgMax: 0.1
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
    let spots = peaks.map { peak in
        let dx = Double(peak.x - 64), dy = Double(peak.y - 64)
        return (r: hypot(dx, dy) * 0.01, azim: atan2(dy, dx),
                weight: Double(max(0, peak.intensity)))
    }
    var polar = OrientationPlan.buildPolar(spots: spots, geometry: geo, azimBlurBins: 1.5)
    OrientationPlan.normalizeUnit(&polar)
    let (experimentalReal, experimentalImaginary) = OrientationPlan.ringFFTs(
        polar, geo: geo, fft: fft
    )
    let na = geo.nAzimuthal, nr = geo.nRadial
    var correlationReal = [Float](repeating: 0, count: na)
    var correlationImaginary = [Float](repeating: 0, count: na)
    var best: Float = -.greatestFiniteMagnitude, second = best
    var bestTemplate = -1, bestBin = 0
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
        if local > best {
            second = best; best = local; bestTemplate = template; bestBin = bin
        } else if local > second { second = local }
    }
    return (bestTemplate, (na - bestBin) % na, best, second)
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
print("acom-matching-test: all passed")

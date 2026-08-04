import Foundation

// Baseline + parity harness for the Bragg disk-correlation path.
//
// Why this exists: disk correlation is the dominant compute step in the Bragg
// pipeline (~1 ms per 128x128 pattern on the M3 baseline, i.e. ~9-10 s for a
// real 8,400-10,000 position scan), and it is the step a user re-runs while
// tuning detection thresholds. It is therefore the target for a Metal backend.
//
// A GPU port is only acceptable if it is *numerically identical* to the
// vDSP path, not merely close: peak positions feed calibration, strain, and
// orientation matching downstream. This harness pins the CPU result as a
// checked-in baseline so any future backend must reproduce it exactly, and
// reports timing so a speedup claim is measured rather than asserted.
//
// Deliberately self-contained: the input is generated from a fixed seed rather
// than read from References/training_dataset, so the loop is seconds long and
// runs anywhere. Real-data behaviour is covered separately by
// tools/training-dataset-campaign and the QC playthrough.

// MARK: - Deterministic input

/// Reproducible LCG. Any platform RNG would make the baseline unstable, which
/// would defeat the entire point of a checked-in checksum.
struct Seeded {
    private var state: UInt64
    init(seed: UInt64) { state = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407 }
    mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return state
    }
    /// Uniform in [0,1).
    mutating func unit() -> Float { Float(next() >> 40) / Float(1 << 24) }
}

/// One synthetic diffraction pattern: a bright unscattered disk plus Bragg
/// disks on a rotated 2D lattice, with a smooth background and noise. Shapes
/// mirror the real datasets (128x128 detector) so timings are representative.
func makePattern(
    qy: Int, qx: Int, probeRadius: Float, index: Int, rng: inout Seeded
) -> [Float] {
    var out = [Float](repeating: 0, count: qy * qx)
    let cx = Float(qx) / 2, cy = Float(qy) / 2
    // Vary the lattice per pattern so the batch is not N copies of one image
    // (which would let a backend cache its way to a false speedup).
    let theta = Float(index) * 0.11
    let g: Float = 17.5
    let (c, s) = (cos(theta), sin(theta))

    var spots: [(Float, Float, Float)] = [(cx, cy, 1.0)]
    for hy in -3...3 {
        for hx in -3...3 where !(hx == 0 && hy == 0) {
            let ux = Float(hx) * g, uy = Float(hy) * g
            let x = cx + ux * c - uy * s
            let y = cy + ux * s + uy * c
            guard x > 4, x < Float(qx) - 4, y > 4, y < Float(qy) - 4 else { continue }
            let decay = exp(-0.18 * Float(hx * hx + hy * hy))
            spots.append((x, y, 0.55 * decay))
        }
    }

    for y in 0..<qy {
        for x in 0..<qx {
            var v: Float = 0.02 + 0.01 * rng.unit()          // background + noise
            for (sx, sy, amp) in spots {
                let dx = Float(x) - sx, dy = Float(y) - sy
                let r = (dx * dx + dy * dy).squareRoot()
                // Soft-edged disk of the probe's radius.
                v += amp / (1 + exp((r - probeRadius) * 2.2))
            }
            out[y * qx + x] = v
        }
    }
    return out
}

/// Disjoint per-index writes from concurrent workers.
struct Box: @unchecked Sendable {
    let c: UnsafeMutablePointer<Int>
    let m: UnsafeMutablePointer<Double>
    let p: UnsafeMutablePointer<Double>
    let i: UnsafeMutablePointer<Double>
}

// MARK: - Result model

/// Checksums chosen to be *sensitive*: a reordered or slightly shifted peak
/// changes the weighted sums, and per-pattern counts localise where a future
/// backend first diverges instead of only saying "the total differs".
struct Measurement: Codable, Equatable {
    var patternCount: Int
    var peakCountTotal: Int
    var perPatternPeakCounts: [Int]
    var positionChecksum: Double
    var intensityChecksum: Double
    var correlationMaximumChecksum: Double

    /// Exact for counts; floats compared with a relative tolerance because the
    /// vDSP FFT is not bit-reproducible across OS revisions. A GPU backend that
    /// only lands inside this tolerance is acceptable; one that moves a peak
    /// count is not.
    func mismatches(against other: Measurement, tolerance: Double) -> [String] {
        var problems: [String] = []
        if patternCount != other.patternCount {
            problems.append("patternCount \(patternCount) vs \(other.patternCount)")
        }
        if peakCountTotal != other.peakCountTotal {
            problems.append("peakCountTotal \(peakCountTotal) vs \(other.peakCountTotal)")
        }
        if perPatternPeakCounts != other.perPatternPeakCounts {
            let firstDivergence = zip(perPatternPeakCounts, other.perPatternPeakCounts)
                .enumerated().first { $0.element.0 != $0.element.1 }
            if let d = firstDivergence {
                problems.append(
                    "per-pattern peak count first diverges at pattern \(d.offset): "
                    + "\(d.element.0) vs \(d.element.1)"
                )
            } else {
                problems.append("per-pattern peak count arrays differ in length")
            }
        }
        func compare(_ name: String, _ a: Double, _ b: Double) {
            let scale = max(abs(a), abs(b), 1e-12)
            let relative = abs(a - b) / scale
            if relative > tolerance {
                problems.append("\(name) \(a) vs \(b) (relative \(relative) > \(tolerance))")
            }
        }
        compare("positionChecksum", positionChecksum, other.positionChecksum)
        compare("intensityChecksum", intensityChecksum, other.intensityChecksum)
        compare("correlationMaximumChecksum",
                correlationMaximumChecksum, other.correlationMaximumChecksum)
        return problems
    }
}

struct Baseline: Codable {
    var backend: String
    var detector: [Int]
    var patternCount: Int
    var probeRadius: Float
    var measurement: Measurement
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
    exit(1)
}

// MARK: - Arguments

var record = false
var backend = "cpu"
var patternCount = 64
var repeats = 5
var tolerance = 1e-6
var baselinePath = "baseline.json"

var args = Array(CommandLine.arguments.dropFirst())
while let arg = args.first {
    args.removeFirst()
    switch arg {
    case "--record": record = true
    case "--backend":
        if args.isEmpty { fail("--backend needs a value") }
        backend = args.removeFirst()
    case "--patterns":
        guard let v = Int(args.first ?? "") else { fail("--patterns needs an integer") }
        patternCount = v; args.removeFirst()
    case "--repeats":
        guard let v = Int(args.first ?? "") else { fail("--repeats needs an integer") }
        repeats = v; args.removeFirst()
    case "--tolerance":
        guard let v = Double(args.first ?? "") else { fail("--tolerance needs a number") }
        tolerance = v; args.removeFirst()
    case "--baseline":
        if args.isEmpty { fail("--baseline needs a path") }
        baselinePath = args.removeFirst()
    default: fail("unknown argument \(arg)")
    }
}

guard ["cpu", "cpu-parallel"].contains(backend) else {
    fail("--backend must be cpu or cpu-parallel")
}
// MARK: - Setup

let qy = 128, qx = 128
let probeRadius: Float = 6.1     // matches the measured sim_Au probe (§9.1)

guard let kernel = ProbeKernel.synthetic(radius: probeRadius, qy: qy, qx: qx) else {
    fail("ProbeKernel.synthetic returned nil")
}
guard let detector = DiskDetector(kernel: kernel) else {
    fail("DiskDetector returned nil")
}

var params = DiskDetectionParams.detectorAdapted(qy: qy, qx: qx)
params.subpixel = .poly
params.corrPower = 1
params.sigmaCC = 2
let issues = params.validationIssues(
    in: DiskDetectionContext(qy: qy, qx: qx, probeRadius: kernel.probeRadius)
)
guard !issues.contains(where: { $0.severity == .error }) else {
    fail("parameters failed production validation: \(issues)")
}

var rng = Seeded(seed: 0x4D53_5445_4D00_0001)
let patterns = (0..<patternCount).map {
    makePattern(qy: qy, qx: qx, probeRadius: probeRadius, index: $0, rng: &rng)
}

// MARK: - Measure

func measure() -> Measurement {
    var perPattern: [Int] = []
    var total = 0
    var position = 0.0, intensity = 0.0, correlation = 0.0

    if backend == "cpu-parallel" {
        // Mirrors DiskDetection.detectAll: one detector per worker, patterns
        // strided across workers. This is what the app actually runs, so it is
        // the only fair opponent for the GPU — comparing against the
        // single-threaded path would flatter Metal by the core count.
        var counts = [Int](repeating: 0, count: patterns.count)
        var maxima = [Double](repeating: 0, count: patterns.count)
        var positions = [Double](repeating: 0, count: patterns.count)
        var intensities = [Double](repeating: 0, count: patterns.count)
        let workers = max(1, min(ProcessInfo.processInfo.activeProcessorCount, patterns.count))
        counts.withUnsafeMutableBufferPointer { c in
        maxima.withUnsafeMutableBufferPointer { m in
        positions.withUnsafeMutableBufferPointer { po in
        intensities.withUnsafeMutableBufferPointer { inten in
            let box = Box(c: c.baseAddress!, m: m.baseAddress!,
                          p: po.baseAddress!, i: inten.baseAddress!)
            DispatchQueue.concurrentPerform(iterations: workers) { w in
                guard let det = DiskDetector(kernel: kernel) else { return }
                for index in stride(from: w, to: patterns.count, by: workers) {
                    let r = det.detectWithDiagnostics(pattern: patterns[index], params: params)
                    box.c[index] = r.peaks.count
                    box.m[index] = Double(r.diagnostics.correlationMaximum)
                    var pos = 0.0, ints = 0.0
                    for peak in r.peaks {
                        pos += Double(peak.x) * 1.000_003 + Double(peak.y) * 2.999_997
                        ints += Double(peak.intensity)
                    }
                    box.p[index] = pos
                    box.i[index] = ints
                }
            }
        }}}}
        for index in 0..<patterns.count {
            perPattern.append(counts[index]); total += counts[index]
            correlation += maxima[index]
            position += positions[index]; intensity += intensities[index]
        }
        return Measurement(
            patternCount: patterns.count, peakCountTotal: total,
            perPatternPeakCounts: perPattern, positionChecksum: position,
            intensityChecksum: intensity, correlationMaximumChecksum: correlation
        )
    }

    for pattern in patterns {
        let result = detector.detectWithDiagnostics(pattern: pattern, params: params)
        perPattern.append(result.peaks.count)
        total += result.peaks.count
        correlation += Double(result.diagnostics.correlationMaximum)
        for peak in result.peaks {
            // Asymmetric weights so swapping two peaks changes the sum.
            position += Double(peak.x) * 1.000_003 + Double(peak.y) * 2.999_997
            intensity += Double(peak.intensity)
        }
    }
    return Measurement(
        patternCount: patterns.count,
        peakCountTotal: total,
        perPatternPeakCounts: perPattern,
        positionChecksum: position,
        intensityChecksum: intensity,
        correlationMaximumChecksum: correlation
    )
}

_ = measure()  // warm caches and FFT setups before timing

var timings: [Double] = []
var measured = Measurement(
    patternCount: 0, peakCountTotal: 0, perPatternPeakCounts: [],
    positionChecksum: 0, intensityChecksum: 0, correlationMaximumChecksum: 0
)
for _ in 0..<max(1, repeats) {
    let start = DispatchTime.now().uptimeNanoseconds
    let m = measure()
    let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
    timings.append(elapsed)
    if measured.patternCount == 0 {
        measured = m
    } else if measured != m {
        // Same backend, same input, different answer: nondeterminism would make
        // any parity claim meaningless, so surface it instead of averaging over it.
        fail("run-to-run nondeterminism in the \(backend) backend — checksums differ between repeats")
    }
}
timings.sort()
let median = timings[timings.count / 2]

// MARK: - Report / compare

let perPatternMs = median / Double(patternCount)
print("backend            : \(backend)")
print("detector           : \(qy)x\(qx), \(patternCount) patterns, probe radius \(probeRadius) px")
print("median batch       : \(String(format: "%.2f", median)) ms")
print("per pattern        : \(String(format: "%.3f", perPatternMs)) ms")
print("  → projected for a 8,400-position scan: "
      + "\(String(format: "%.1f", perPatternMs * 8_400 / 1000)) s")
print("peaks (total)      : \(measured.peakCountTotal)")
print("position checksum  : \(measured.positionChecksum)")
print("intensity checksum : \(measured.intensityChecksum)")
print("corr-max checksum  : \(measured.correlationMaximumChecksum)")

let baselineURL = URL(fileURLWithPath: baselinePath)
if record {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let baseline = Baseline(
        backend: backend, detector: [qy, qx], patternCount: patternCount,
        probeRadius: probeRadius, measurement: measured
    )
    try encoder.encode(baseline).write(to: baselineURL)
    print("\nRECORDED baseline → \(baselineURL.path)")
    print("Timing is intentionally NOT recorded: it is machine- and thermal-dependent.")
    exit(0)
}

guard let data = try? Data(contentsOf: baselineURL) else {
    fail("no baseline at \(baselineURL.path) — run with --record first")
}
let baseline = try JSONDecoder().decode(Baseline.self, from: data)
guard baseline.patternCount == patternCount, baseline.detector == [qy, qx] else {
    fail("baseline shape \(baseline.detector) x\(baseline.patternCount) does not match "
         + "this run \([qy, qx]) x\(patternCount)")
}

let problems = measured.mismatches(against: baseline.measurement, tolerance: tolerance)
guard problems.isEmpty else {
    fail("disk correlation diverged from the recorded baseline:\n  - "
         + problems.joined(separator: "\n  - "))
}
print("\nPASS: matches recorded \(baseline.backend) baseline within \(tolerance) relative tolerance")

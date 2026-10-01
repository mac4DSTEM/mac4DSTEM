//
//  main.swift — tools/parallax-ptycho-real-probe (2026-09-30). `diagnostic`.
//
//  What parallax and single-slice ptychography really cost on ONE real cube,
//  headless: the TRUE peak memory and the time per stage, beside each
//  estimator's own number. It measures and reports; it tunes and decides
//  nothing, and it changes no file under mac4DSTEM/.
//
//    probe <h5> preprocess
//    probe <h5> align
//    probe <h5> kde <auto|factor>
//    probe <h5> ptycho <gd|dmap>
//    options: --kv 200  --origin com|x,y  --probe-radius <px>  --repeat 2  --limit-gib 48  --abort-gib 40
//             --defocus <A>  --c12a <A>  --c12b <A>   (ptycho: the probe's defocus and astigmatism; py4DSTEM's `defocus`, 0 = in focus)
//
//  ONE stage per process: a footprint is a lifetime maximum. Every stage with a
//  memory option is driven three ways — (1) limit = 1 byte, to read the
//  estimator's own number out of its `memoryLimit(bytes:limit:)` refusal;
//  (2) the DEFAULT options, exactly as the app runs them (the 1 GiB limits);
//  (3) when (2) refuses, the limit raised to --limit-gib. A stage whose default
//  run passes is measured as that run. Prerequisite stages (preprocess before
//  align, etc.) get the same treatment and are held for the next stage.
//  A background thread samples phys_footprint every 50 ms and aborts the
//  process (exit 3) past --abort-gib.
//
//  The app's option values are mirrored from App/AppState+PhaseContrast.swift
//  (align: upsampleFactor 8 per level, loop until the schedule completes; KDE:
//  defaults of PhaseContrastProduct; ptychography: PtychographySettings).
//

import Foundation
import Darwin

// MARK: - logging and memory

func log(_ s: String) {
    FileHandle.standardOutput.write(Data((s + "\n").utf8))
}

func footprintBytes() -> UInt64 {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
    let kr = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
        }
    }
    return kr == KERN_SUCCESS ? UInt64(info.phys_footprint) : 0
}

func gb(_ bytes: UInt64) -> String { String(format: "%.3f GB", Double(bytes) / 1_073_741_824) }
func gb(_ bytes: Int) -> String { gb(UInt64(max(0, bytes))) }

/// phys_footprint sampled every 50 ms; `lap()` returns the peak since the last lap.
final class Sampler: @unchecked Sendable {
    private let lock = NSLock()
    private var lifetime: UInt64 = 0
    private var window: UInt64 = 0
    private let abortBytes: UInt64

    init(abortGiB: Double) {
        abortBytes = UInt64(abortGiB * 1_073_741_824)
        let thread = Thread { [self] in
            while true {
                let f = footprintBytes()
                lock.lock()
                if f > lifetime { lifetime = f }
                if f > window { window = f }
                lock.unlock()
                if f > abortBytes {
                    log("ABORT: phys_footprint \(gb(f)) passed the \(gb(abortBytes)) guard")
                    exit(3)
                }
                usleep(50_000)
            }
        }
        thread.qualityOfService = .userInteractive
        thread.start()
    }

    func lap() -> UInt64 {
        lock.lock(); defer { lock.unlock() }
        let f = footprintBytes()
        let peak = max(window, f)
        window = f
        return peak
    }

    var lifetimePeak: UInt64 {
        lock.lock(); defer { lock.unlock() }
        return max(lifetime, footprintBytes())
    }
}

nonisolated(unsafe) var sampler: Sampler! = nil

func now() -> Double { Double(DispatchTime.now().uptimeNanoseconds) / 1e9 }

struct Measure {
    var seconds: Double
    var before: UInt64
    var after: UInt64
    var peak: UInt64
}

/// Runs `body`, logs seconds and the footprint before/after/window-peak.
func measured<T>(_ name: String, _ body: () async throws -> T) async throws -> (T, Measure) {
    _ = sampler.lap()
    let before = footprintBytes()
    let t0 = now()
    let value = try await body()
    let seconds = now() - t0
    let after = footprintBytes()
    let peak = sampler.lap()
    let m = Measure(seconds: seconds, before: before, after: after, peak: max(peak, before))
    log(String(format: "MEASURE %@: %.2f s  footprint before %@  after %@  stage peak %@",
               name, seconds, gb(before), gb(after), gb(m.peak)))
    return (value, m)
}

func stats(_ pixels: [Float]) -> String {
    var lo = Float.infinity, hi = -Float.infinity, sum = 0.0, nan = 0, zeros = 0
    for p in pixels {
        if p.isNaN || p.isInfinite { nan += 1; continue }
        lo = min(lo, p); hi = max(hi, p); sum += Double(p)
        if p == 0 { zeros += 1 }
    }
    let n = pixels.count - nan
    return String(format: "n %d  min %.6g  max %.6g  mean %.6g  nonfinite %d  zeros %d",
                  pixels.count, lo, hi, n > 0 ? sum / Double(n) : .nan, nan, zeros)
}

func fail(_ m: String) -> Never { log("FAIL: \(m)"); exit(1) }

// MARK: - saving the products (--out <dir>): float32 .npy, written with no dependency

nonisolated(unsafe) var outDirectory: String? = nil

/// Writes `pixels` as a little-endian float32 NumPy v1.0 file `<outDirectory>/<name>.npy`, row-major `shape`.
func saveNPY(_ name: String, _ pixels: [Float], shape: [Int]) {
    guard let dir = outDirectory else { return }
    precondition(shape.reduce(1, *) == pixels.count, "npy shape does not match the pixel count")
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    let shapeText = shape.count == 1 ? "(\(shape[0]),)" : "(" + shape.map(String.init).joined(separator: ", ") + ")"
    var header = "{'descr': '<f4', 'fortran_order': False, 'shape': \(shapeText), }"
    while (10 + header.utf8.count + 1) % 64 != 0 { header += " " }
    header += "\n"
    var data = Data([0x93]) + Data("NUMPY".utf8) + Data([1, 0])
    var headerLength = UInt16(header.utf8.count).littleEndian
    data.append(Data(bytes: &headerLength, count: 2))
    data.append(Data(header.utf8))
    pixels.withUnsafeBufferPointer { data.append(Data(buffer: $0)) }
    let path = dir + "/" + name + ".npy"
    do { try data.write(to: URL(fileURLWithPath: path)); log("SAVED \(path) shape \(shape)") }
    catch { log("SAVE FAILED \(path): \(error)") }
}

/// A small JSON of scalars beside the arrays: `<outDirectory>/<name>.json`.
func saveJSON(_ name: String, _ values: [String: Any]) {
    guard let dir = outDirectory else { return }
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    let path = dir + "/" + name + ".json"
    if let data = try? JSONSerialization.data(withJSONObject: values, options: [.prettyPrinted, .sortedKeys]) {
        try? data.write(to: URL(fileURLWithPath: path)); log("SAVED \(path)")
    }
}

// MARK: - the estimator ladder

struct Ladder<T> {
    var value: T
    var estimate: Int?          // the estimator's own bytes, read from the limit=1 refusal
    var defaultLimit: Int?      // the limit in the default options
    var defaultRefused: Bool
    var measure: Measure
}

/// (1) limit = probeLimit → the estimator's bytes; (2) default options; (3) raised limit if (2) refused.
func ladder<T>(
    _ name: String,
    probeLimit: Int = 1,
    raisedLimit: Int,
    defaultLimit: Int,
    refusal: (Error) -> (bytes: Int, limit: Int)?,
    run: (Int) async throws -> T
) async throws -> Ladder<T> {
    var estimate: Int?
    do {
        _ = try await run(probeLimit)
        log("LADDER \(name): limit=\(probeLimit) did NOT refuse (no estimate read)")
    } catch {
        if let r = refusal(error) {
            estimate = r.bytes
            log("LADDER \(name): estimator says \(gb(r.bytes)) (\(r.bytes) bytes) [read at limit \(r.limit)]")
        } else {
            log("LADDER \(name): probe failed with a different error: \(error)")
        }
    }
    do {
        let (value, m) = try await measured("\(name) [default options, limit \(gb(defaultLimit))]") { try await run(defaultLimit) }
        log("LADDER \(name): default limit \(gb(defaultLimit)) PASSED (no refusal)")
        return Ladder(value: value, estimate: estimate, defaultLimit: defaultLimit, defaultRefused: false, measure: m)
    } catch {
        guard let r = refusal(error) else { throw error }
        log("LADDER \(name): default REFUSED: estimate \(gb(r.bytes)) > limit \(gb(r.limit)); message: \(error.localizedDescription)")
        let (value, m) = try await measured("\(name) [limit raised to \(gb(raisedLimit))]") { try await run(raisedLimit) }
        return Ladder(value: value, estimate: estimate ?? r.bytes, defaultLimit: defaultLimit, defaultRefused: true, measure: m)
    }
}

func summary<T>(_ stage: String, _ l: Ladder<T>, extra: String = "") {
    let est = l.estimate.map { UInt64($0) } ?? 0
    let denominator = Double(est + l.measure.before)
    let ratio = denominator > 0 ? Double(l.measure.peak) / denominator : .nan
    let delta = l.measure.peak > l.measure.before ? l.measure.peak - l.measure.before : 0
    log(String(format: "SUMMARY stage=%@ estimator=%@ default_limit=%@ default_refused=%@ footprint_before=%@ stage_peak=%@ delta=%@ seconds=%.2f peak/(est+before)=%.3f delta/est=%.3f %@",
               stage, gb(est), gb(l.defaultLimit ?? 0), l.defaultRefused ? "yes" : "no",
               gb(l.measure.before), gb(l.measure.peak), gb(delta), l.measure.seconds, ratio,
               est > 0 ? Double(delta) / Double(est) : .nan, extra))
}

// MARK: - entry


@main
enum ParallaxPtychoRealProbe {
    static func main() async {
        do { try await run() } catch { log("FAIL: \(error)"); exit(1) }
    }

    static func run() async throws {
        var args = Array(CommandLine.arguments.dropFirst())
        func option(_ name: String) -> String? {
            guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
            let v = args[i + 1]; args.removeSubrange(i...(i + 1)); return v
        }
        let kv = Double(option("--kv") ?? "200") ?? 200
        let originOption = option("--origin") ?? "com"
        let radiusOption = option("--probe-radius")
        let repeats = Int(option("--repeat") ?? "2") ?? 2
        let limitGiB = Double(option("--limit-gib") ?? "48") ?? 48
        let abortGiB = Double(option("--abort-gib") ?? "40") ?? 40
        // Calibration of the cube (defaults = the 051 cube this probe was first written for).
        let qPixel = Double(option("--q") ?? "0.03564271") ?? 0.03564271          // Å⁻¹ per detector pixel
        let rPixel = Double(option("--r") ?? "100.32583") ?? 100.32583            // Å per scan step
        let rotationDegrees = Double(option("--rotation-deg") ?? "0") ?? 0         // R–Q rotation fed to the calibration (as a user would set it)
        let transposeQR = (option("--transpose") ?? "0") == "1"
        outDirectory = option("--out")
        // Ptychography options; nil = the app's own defaults (SingleslicePtychographyOptions()).
        let ptyIterations = option("--iterations").flatMap { Int($0) }
        let ptyStepSize = option("--step-size").flatMap { Float($0) }
        let ptyNormalizationMinimum = option("--norm-min").flatMap { Float($0) }
        // Lane R2 (2026-10-01): py4DSTEM clamps |object| <= 1 on EVERY iteration for a complex object
        // (ptychographic_constraints.py `_object_threshold_constraint`, applied unconditionally by `_object_constraints`);
        // the app exposes the same clamp as `constrainObjectAmplitude`, default off. `--constrain-amplitude 1` matches py4DSTEM.
        let ptyConstrainAmplitude = (option("--constrain-amplitude") ?? "0") == "1"
        // The probe the ptychography starts from (lane R1, 2026-09-30): py4DSTEM's `defocus` (C10 = -defocus) and the parallax fit's
        // cartesian astigmatism, all in Å; default 0 = the in-focus aperture. The parallax fit of THIS cube reports C1 = +663.6, so
        // its implied defocus is -663.6 (py4DSTEM's forward model C10 = -defocus, utils.py:159-160; convention_check.py).
        let ptyAberrations = PtychographyProbeAberrations(
            defocusAngstrom: option("--defocus").flatMap { Double($0) } ?? 0,
            c12aAngstrom: option("--c12a").flatMap { Double($0) } ?? 0,
            c12bAngstrom: option("--c12b").flatMap { Double($0) } ?? 0
        )
        guard args.count >= 2 else {
            fail("usage: probe <h5> preprocess | align | kde <auto|factor> | ptycho <gd|dmap>  [--kv 200] [--origin com|x,y] [--probe-radius px] [--repeat 2] [--limit-gib 48] [--abort-gib 40] [--q 1/A per px] [--r A per px] [--rotation-deg d] [--transpose 0|1] [--out dir] [--iterations n] [--step-size s] [--norm-min m] [--constrain-amplitude 0|1] [--defocus A] [--c12a A] [--c12b A]")
        }
        let path = args[0], stage = args[1]
        let raised = Int(limitGiB * 1_073_741_824)
        sampler = Sampler(abortGiB: abortGiB)
        log("probe \(stage) \(args.dropFirst(2).joined(separator: " ")) on \(path)")
        log("raised limit \(gb(raised)), abort guard \(abortGiB) GiB, repeat \(repeats)")
        log("process start footprint \(gb(footprintBytes()))")

        // --- dataset, origin, calibration (not a measured stage) ---
        let reader = try H5Reader(path: path)
        let d = try await reader.discoverPrimaryDataset()
        let view = LoadView(fullExtentOf: d)
        log("dataset \(d.ry) x \(d.rx) x \(d.qy) x \(d.qx)  (file calibration: \(String(describing: await reader.pixelCalibration())))")
        let detectorCount = d.qy * d.qx
        var mean = [Double](repeating: 0, count: detectorCount)
        for y in 0..<d.ry {
            let tile = try await reader.readScanTile(view, yRange: y..<(y + 1))
            for x in 0..<d.rx {
                let base = x * detectorCount
                for q in 0..<detectorCount { mean[q] += Double(tile.pixels[base + q]) }
            }
        }
        let scanCount = Double(d.ry * d.rx)
        mean = mean.map { $0 / scanCount }
        var sum = 0.0, cx = 0.0, cy = 0.0
        for r in 0..<d.qy { for c in 0..<d.qx {
            let v = mean[r * d.qx + c]; sum += v; cx += v * Double(c); cy += v * Double(r)
        } }
        let com = (x: Float(cx / sum), y: Float(cy / sum))
        let peakMean = mean.max() ?? 1
        let diskPixels = mean.filter { $0 >= 0.5 * peakMean }.count
        let measuredRadius = Float((Double(diskPixels) / .pi).squareRoot())
        var origin = com
        if originOption != "com" {
            let parts = originOption.split(separator: ",").compactMap { Float($0) }
            guard parts.count == 2 else { fail("--origin com|x,y") }
            origin = (x: parts[0], y: parts[1])
        }
        let probeRadius = radiusOption.flatMap { Float($0) } ?? measuredRadius
        log(String(format: "origin (x col, y row) = (%.4f, %.4f) [%@]; mean-pattern CoM (%.4f, %.4f); probe radius %.2f px [%@]",
                   origin.x, origin.y, originOption == "com" ? "centre of mass of the mean pattern" : "given",
                   com.x, com.y, probeRadius, radiusOption == nil ? "sqrt(area of pixels >= 0.5*max / pi)" : "given"))
        mean = []

        var calibration = Calibration(originProvenance: .manual)
        calibration.qPixelSize = qPixel; calibration.qPixelUnits = "Å⁻¹"
        calibration.rPixelSize = rPixel; calibration.rPixelUnits = "Å"
        calibration.rotationRad = Float(rotationDegrees * Double.pi / 180); calibration.transposeQR = transposeQR
        let physical = try ParallaxPhysicalCalibration.resolve(
            calibration: calibration, apertureCenterX: origin.x, apertureCenterY: origin.y,
            acceleratingVoltageKV: kv
        )
        log(String(format: "calibration: Q %.8f 1/A per px, R %.6f A per px, %.0f kV (lambda %.6f A), rotation %.4f deg, transpose %@, origin (qx row %.4f, qy col %.4f)",
                   physical.reciprocalSamplingInvAngstrom, physical.scanSamplingAngstrom, kv,
                   physical.wavelengthAngstrom, rotationDegrees, transposeQR ? "true" : "false", physical.originQX, physical.originQY))
        log("baseline footprint before any stage \(gb(footprintBytes()))")
        let baseline = footprintBytes()

        func preprocessLadder() async throws -> Ladder<ParallaxPreprocessResult> {
            try await ladder("preprocess", raisedLimit: raised,
                             defaultLimit: ParallaxPreprocessOptions().maxStackBytes,
                             refusal: { e in
                if case ParallaxPreprocessor.PreprocessError.stackTooLarge(let b, let l) = e { return (b, l) }
                return nil
            }, run: { limit in
                var o = ParallaxPreprocessOptions(); o.maxStackBytes = limit
                return try await ParallaxPreprocessor.run(source: reader, view: view, calibration: physical, options: o)
            })
        }
        func describePre(_ p: ParallaxPreprocessResult) -> String {
            String(format: "BF px %d, stack %d x %d x %d (%@ per stack, %@ resident), lambda %.5f A, max angle %.2f mrad, initial error %.5f; incoherentBF: %@",
                   p.brightFieldPixelCount, p.brightFieldPixelCount, p.stackHeight, p.stackWidth,
                   gb(p.stackByteCount), gb(p.residentStackByteCount),
                   p.calibration.wavelengthAngstrom, p.maximumProbeAngleMrad, p.initialError, stats(p.incoherentBF))
        }
        func alignLoop(_ pre: ParallaxPreprocessResult, limit: Int) async throws -> ParallaxAlignmentResult {
            let schedule = ParallaxAligner.defaultBinSchedule(detectorIndices: pre.detectorIndices)
            var prior: ParallaxAlignmentResult? = nil
            var options = ParallaxAlignmentOptions()
            options.upsampleFactor = 8          // as AppState.alignParallaxNextLevel
            options.maxWorkingBytes = limit
            while (prior?.completedBins.count ?? 0) < schedule.count {
                let previous = prior
                let level = (previous?.completedBins.count ?? 0) + 1
                _ = sampler.lap()
                let t0 = now()
                let next = try await Task.detached(priority: .userInitiated) {
                    try ParallaxAligner.alignNextLevel(preprocessing: pre, previous: previous, options: options)
                }.value
                log(String(format: "  align level %d/%d bin %d: %.2f s, %d groups, max shift %.3f px, error %.5f, peak %@",
                           level, schedule.count, next.alignmentBin, now() - t0, next.groups.count,
                           next.maximumShiftPixels, next.currentError, gb(sampler.lap())))
                prior = next
            }
            return prior!
        }
        /// Fits the aberrations exactly as AppState.fitParallaxAberrations does, prints them, saves the aligned BF.
        func saveAlignedBF(_ pre: ParallaxPreprocessResult, _ a: ParallaxAlignmentResult) {
            saveNPY("app_alignedBF_padded", a.alignedBF, shape: [a.stackHeight, a.stackWidth])
            var meta: [String: Any] = ["stackHeight": a.stackHeight, "stackWidth": a.stackWidth, "scanHeight": a.scanHeight, "scanWidth": a.scanWidth,
                                       "paddedTop": (a.stackHeight - a.scanHeight) / 2, "paddedLeft": (a.stackWidth - a.scanWidth) / 2,
                                       "errorHistory": a.errorHistory.map { Double($0) }, "complete": a.isComplete]
            do {
                let fit = try ParallaxAberrationFitter.fitHigherOrder(preprocessing: pre, alignment: a)
                let low = fit.lowOrder
                log(String(format: "FIT lowOrder: C1 %.4f A, C12a %.4f, C12b %.4f, rotation %.6f rad = %.4f deg, rms residual %.5f A, transpose %@",
                           low.c1Angstrom, low.c12aAngstrom, low.c12bAngstrom, low.rotationRad, low.rotationRad * 180 / .pi,
                           low.rmsResidualAngstrom, low.forceTranspose ? "true" : "false"))
                log("FIT higherOrder: terms \(fit.terms.map { "(\($0.radialOrder),\($0.angularOrder),\($0.component))" }) coefficients(A) \(fit.coefficientsAngstrom.map { String(format: "%.4f", $0) }) rms \(fit.rmsResidualAngstrom)")
                meta["lowOrder"] = ["c1Angstrom": low.c1Angstrom, "c12aAngstrom": low.c12aAngstrom, "c12bAngstrom": low.c12bAngstrom,
                                    "rotationRad": low.rotationRad, "rotationDeg": low.rotationRad * 180 / .pi, "rmsResidualAngstrom": low.rmsResidualAngstrom,
                                    "transpose": low.forceTranspose]
                meta["higherOrderTerms"] = fit.terms.map { [$0.radialOrder, $0.angularOrder, $0.component] }
                meta["higherOrderCoefficientsAngstrom"] = fit.coefficientsAngstrom
                meta["higherOrderRmsAngstrom"] = fit.rmsResidualAngstrom
            } catch { log("FIT FAILED: \(error)") }
            saveJSON("app_align", meta)
        }
        func describeAlign(_ a: ParallaxAlignmentResult) -> String {
            "bins \(a.completedBins) of \(a.alignmentSchedule), complete \(a.isComplete), errors \(a.errorHistory.map { String(format: "%.5f", $0) }), max shift \(a.maximumShiftPixels) px; alignedBF: \(stats(a.alignedBF)); shiftedStack \(gb(a.shiftedStack.count * 4)) + masks \(gb(a.shiftedMasks.count * 4))"
        }

        switch stage {
        case "preprocess":
            // The ladder is run once for the estimator and the default verdict; its result is dropped; repeats follow.
            var l = Optional(try await preprocessLadder())
            log("RESULT preprocess: \(describePre(l!.value))")
            summary("preprocess", l!)
            l = nil   // release the first result: the repeats measure whether the footprint comes back
            log("LEAK preprocess: first result released, footprint \(gb(footprintBytes()))")
            try await leakRepeats(name: "preprocess", repeats: repeats - 1, baseline: baseline) {
                let p = try await ParallaxPreprocessor.run(
                    source: reader, view: view, calibration: physical,
                    options: { var o = ParallaxPreprocessOptions(); o.maxStackBytes = raised; return o }())
                log("  repeat result: BF px \(p.brightFieldPixelCount), incoherentBF \(stats(p.incoherentBF)), alive footprint \(gb(footprintBytes()))")
            }
            release(l)

        case "align":
            let pre = try await preprocessLadder()
            log("RESULT preprocess: \(describePre(pre.value))")
            summary("preprocess(prereq)", pre)
            var l = Optional(try await ladder("align(all levels)", raisedLimit: raised,
                                     defaultLimit: ParallaxAlignmentOptions().maxWorkingBytes,
                                     refusal: { e in
                if case ParallaxAligner.AlignmentError.memoryLimit(let b, let l) = e { return (b, l) }
                return nil
            }, run: { limit in try await alignLoop(pre.value, limit: limit) }))
            log("RESULT align: \(describeAlign(l!.value))")
            summary("align", l!, extra: "resident_prereq=\(gb(pre.value.residentStackByteCount))")
            saveAlignedBF(pre.value, l!.value)
            l = nil   // release the first result before the repeats
            log("LEAK \("align"): first result released, footprint \(gb(footprintBytes()))")
            try await leakRepeats(name: "align", repeats: repeats - 1, baseline: baseline) {
                let a = try await alignLoop(pre.value, limit: raised)
                log("  repeat result: alive footprint \(gb(footprintBytes())); alignedBF \(stats(a.alignedBF))")
            }
            release(l)

        case "kde":
            guard args.count >= 3 else { fail("kde needs <auto|factor>") }
            let factor: Double? = args[2] == "auto" ? nil : Double(args[2])
            if args[2] != "auto", factor == nil { fail("kde factor") }
            let pre = try await preprocessLadder()
            log("RESULT preprocess: \(describePre(pre.value))")
            summary("preprocess(prereq)", pre)
            let aligned = try await ladder("align(prereq)", raisedLimit: raised,
                                           defaultLimit: ParallaxAlignmentOptions().maxWorkingBytes,
                                           refusal: { e in
                if case ParallaxAligner.AlignmentError.memoryLimit(let b, let l) = e { return (b, l) }
                return nil
            }, run: { limit in try await alignLoop(pre.value, limit: limit) })
            log("RESULT align: \(describeAlign(aligned.value))")
            summary("align(prereq)", aligned)
            func kde(_ limit: Int) async throws -> ParallaxSubpixelResult {
                var o = ParallaxSubpixelOptions()     // app defaults (PhaseContrastProduct): sigma 0.125, no lowpass, no Lanczos, no position correction
                o.upsampleFactor = factor
                o.maxWorkingBytes = limit
                let p = pre.value, a = aligned.value
                return try await Task.detached(priority: .userInitiated) {
                    try ParallaxSubpixelReconstructor.reconstruct(preprocessing: p, alignment: a, options: o)
                }.value
            }
            func describeKDE(_ r: ParallaxSubpixelResult) -> String {
                String(format: "factor %.4f (BF limit %.3f, DF limit %.3f), padded %d x %d (paddedBF %@), output %d x %d px, %.5f A/px, croppedBF: %@",
                       r.upsampleFactor, r.brightFieldUpsampleLimit, r.darkFieldUpsampleLimit, r.paddedHeight, r.paddedWidth,
                       gb(r.paddedBF.count * 4), r.croppedBF.width, r.croppedBF.height, r.outputSamplingAngstrom, stats(r.croppedBF.pixels))
            }
            var l = Optional(try await ladder("kde \(args[2])", raisedLimit: raised,
                                     defaultLimit: ParallaxSubpixelOptions().maxWorkingBytes,
                                     refusal: { e in
                if case ParallaxSubpixelReconstructor.ReconstructionError.memoryLimit(let b, let l) = e { return (b, l) }
                return nil
            }, run: { limit in try await kde(limit) }))
            log("RESULT kde: \(describeKDE(l!.value))")
            saveNPY("app_kde_\(args[2])_croppedBF", l!.value.croppedBF.pixels, shape: [l!.value.croppedBF.height, l!.value.croppedBF.width])
            saveJSON("app_kde_\(args[2])", ["factor": l!.value.upsampleFactor, "width": l!.value.croppedBF.width, "height": l!.value.croppedBF.height,
                                            "outputSamplingAngstrom": l!.value.outputSamplingAngstrom, "paddedHeight": l!.value.paddedHeight, "paddedWidth": l!.value.paddedWidth])
            let resident = pre.value.residentStackByteCount + aligned.value.shiftedStack.count * 4 + aligned.value.shiftedMasks.count * 4
            summary("kde \(args[2])", l!, extra: "resident_prereq_arrays=\(gb(resident))")
            l = nil   // release the first result before the repeats
            log("LEAK \("kde \(args[2])"): first result released, footprint \(gb(footprintBytes()))")
            try await leakRepeats(name: "kde \(args[2])", repeats: repeats - 1, baseline: baseline) {
                let r = try await kde(raised)
                log("  repeat result: alive footprint \(gb(footprintBytes())); \(describeKDE(r))")
            }
            release(l)

        case "ptycho":
            guard args.count >= 3, ["gd", "dmap"].contains(args[2]) else { fail("ptycho needs gd|dmap") }
            let method: SingleslicePtychographyMethod = args[2] == "gd" ? .gradientDescent : .differenceMapAlternatingProjections
            let amplitudeBytes = d.ry * d.rx * d.qy * d.qx * MemoryLayout<Float>.stride
            // Two guards in prepare(): amplitudes alone, then amplitudes + object canvas + probe. A limit equal to the
            // amplitude bytes passes the first and refuses the second, which reads the estimator's final number.
            let prepared = try await ladder("ptycho prepare", probeLimit: amplitudeBytes, raisedLimit: raised,
                                            defaultLimit: PtychographyPreparationOptions().maxResidentBytes,
                                            refusal: { e in
                if case SingleslicePtychography.ReconstructionError.memoryLimit(let b, let l) = e { return (b, l) }
                return nil
            }, run: { limit in
                var o = PtychographyPreparationOptions(); o.maxResidentBytes = limit
                return try await PtychographyPreparer.prepare(source: reader, view: view, calibration: physical,
                                                              probeRadiusPixels: probeRadius, aberrations: ptyAberrations, options: o)
            })
            let input = prepared.value
            log("ptycho probe: defocus \(ptyAberrations.defocusAngstrom) A, C12a \(ptyAberrations.c12aAngstrom) A, C12b \(ptyAberrations.c12bAngstrom) A")
            log("RESULT ptycho prepare: scan \(input.scanHeight) x \(input.scanWidth), detector \(input.detectorHeight) x \(input.detectorWidth), amplitudes \(gb(input.amplitudes.count * 4)) (\(stats(Array(input.amplitudes.prefix(4_000_000))))[first 4M]), object canvas \(input.initialObject.width) x \(input.initialObject.height), probe \(input.initialProbe.width) x \(input.initialProbe.height), sampling \(input.objectSamplingRowAngstrom) x \(input.objectSamplingColumnAngstrom) A/px")
            summary("ptycho prepare", prepared)
            func reconstruct(_ limit: Int) async throws -> SingleslicePtychographyResult {
                var o = SingleslicePtychographyOptions()    // PtychographySettings defaults: 8 iterations, step 0.5, ...
                o.method = method
                if let v = ptyIterations { o.iterations = v }
                if let v = ptyStepSize { o.stepSize = v }
                if let v = ptyNormalizationMinimum { o.normalizationMinimum = v }
                o.constrainObjectAmplitude = ptyConstrainAmplitude
                o.maxWorkingBytes = limit
                return try await Task.detached(priority: .userInitiated) {
                    try SingleslicePtychography.reconstruct(input: input, options: o)
                }.value
            }
            func describePty(_ r: SingleslicePtychographyResult) -> String {
                "method \(r.options.method.rawValue), iterations \(r.options.iterations), errors \(r.errorHistory.map { String(format: "%.6f", $0) }), object canvas \(r.object.width) x \(r.object.height), probe \(r.probe.width) x \(r.probe.height), objectPhase(cropped): \(stats(r.objectPhase().pixels)); objectAmplitude(cropped): \(stats(r.objectAmplitude().pixels)); probeAmplitude: \(stats(r.probeAmplitude().pixels))"
            }
            var l = Optional(try await ladder("ptycho reconstruct \(args[2])", raisedLimit: raised,
                                     defaultLimit: SingleslicePtychographyOptions().maxWorkingBytes,
                                     refusal: { e in
                if case SingleslicePtychography.ReconstructionError.memoryLimit(let b, let l) = e { return (b, l) }
                return nil
            }, run: { limit in try await reconstruct(limit) }))
            log("RESULT ptycho reconstruct: \(describePty(l!.value))")
            do {
                let r = l!.value
                let tag = "app_ptycho_\(args[2])"
                let ph = r.objectPhase(), am = r.objectAmplitude()
                saveNPY("\(tag)_objectPhase", ph.pixels, shape: [ph.height, ph.width])
                saveNPY("\(tag)_objectAmplitude", am.pixels, shape: [am.height, am.width])
                let pa = r.probeAmplitude(), pp = r.probePhase()
                saveNPY("\(tag)_probeAmplitude", pa.pixels, shape: [pa.height, pa.width])
                saveNPY("\(tag)_probePhase", pp.pixels, shape: [pp.height, pp.width])
                saveJSON(tag, ["iterations": r.options.iterations, "stepSize": Double(r.options.stepSize), "normalizationMinimum": Double(r.options.normalizationMinimum),
                               "method": r.options.method.rawValue, "errorHistory": r.errorHistory.map { Double($0) },
                               "constrainObjectAmplitude": r.options.constrainObjectAmplitude,
                               "objectSamplingRowAngstrom": r.objectSamplingRowAngstrom, "objectSamplingColumnAngstrom": r.objectSamplingColumnAngstrom,
                               "objectCroppedHeight": ph.height, "objectCroppedWidth": ph.width, "canvasHeight": r.object.height, "canvasWidth": r.object.width,
                               "rotationDegrees": rotationDegrees, "transpose": transposeQR,
                               "defocusAngstrom": ptyAberrations.defocusAngstrom, "c12aAngstrom": ptyAberrations.c12aAngstrom,
                               "c12bAngstrom": ptyAberrations.c12bAngstrom])
            }
            summary("ptycho reconstruct \(args[2])", l!, extra: "resident_input=\(gb(input.amplitudes.count * 4))")
            l = nil   // release the first result before the repeats
            log("LEAK \("ptycho \(args[2])"): first result released, footprint \(gb(footprintBytes()))")
            try await leakRepeats(name: "ptycho \(args[2])", repeats: repeats - 1, baseline: baseline) {
                let r = try await reconstruct(raised)
                log("  repeat result: alive footprint \(gb(footprintBytes())); \(describePty(r))")
            }
            release(l)

        default:
            fail("unknown stage \(stage)")
        }
        log("LIFETIME sampler peak footprint \(gb(sampler.lifetimePeak)); end footprint \(gb(footprintBytes()))")
        log("DONE")
    }

    @inline(never) static func release<T>(_ v: T) { _ = v }

    /// Runs `body` `repeats` more times; reports the footprint after each has been released (a leak shows as growth).
    static func leakRepeats(name: String, repeats: Int, baseline: UInt64,
                            body: () async throws -> Void) async throws {
        log("LEAK \(name): footprint at repeat start \(gb(footprintBytes())), baseline \(gb(baseline))")
        for i in 1...max(1, repeats) where repeats > 0 {
            let (_, m) = try await measured("\(name) repeat \(i)") { try await body() }
            log("LEAK \(name): after repeat \(i) released: footprint \(gb(footprintBytes())) (before it: \(gb(m.before)))")
        }
    }
}

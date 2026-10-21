//
//  DiskDetectorKitTests.swift
//  DiskDetector on CuboBragg (CuboKit 0.6.0, `BraggPrecision.single`): the app's detector is a facade over the kit's
//  `BraggDetector`. Three layers:
//    - a regression fixture of the former in-app Float detector's peaks and funnels on 256 x 256 synthetic patterns
//      (Fixtures/DiskDetector/kit-switch-baseline.json, generated from the code before the switch);
//    - the facade against the kit's Double definition (pinned to py4DSTEM at 1e-9 px) within the written Float32 tolerance;
//    - the funnel, the non-finite fill and the learned path's correlation surface.
//

import XCTest
// The kit and the app both have BraggPeak, ProbeKernel and BraggVectors: import only the kit types this file names.
import struct CuboBragg.BraggDetector
import struct CuboBragg.BraggDiskOptions
import struct CuboVirtual.DetectorImage
import DSTEMCore
@testable import mac4DSTEM

enum DiskKitFixture {
    /// SplitMix64, so the patterns do not depend on the platform's generator.
    struct Rng {
        var s: UInt64
        mutating func next() -> Double {
            s &+= 0x9E3779B97F4A7C15
            var z = s
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            z ^= z >> 31
            return Double(z >> 11) / Double(1 << 53)
        }
    }

    /// Soft-edged disks at sub-pixel centres plus uniform noise.
    static func pattern(q: Int, seed: UInt64) -> [Float] {
        var rng = Rng(s: seed)
        let c = Double(q) / 2
        var centres: [(Double, Double, Double)] = [(c, c, 1.0)]
        for k in 0..<6 {
            let a = Double(k) * 1.0471975512 + rng.next() * 0.1
            let r = Double(q) * (0.18 + 0.1 * rng.next())
            centres.append((c + r * cos(a) + rng.next(), c + r * sin(a) + rng.next(), 0.2 + 0.5 * rng.next()))
        }
        var out = [Float](repeating: 0, count: q * q)
        for y in 0..<q {
            for x in 0..<q {
                var v = 0.003 * rng.next()
                for (cx, cy, h) in centres {
                    let d = ((Double(x) - cx) * (Double(x) - cx) + (Double(y) - cy) * (Double(y) - cy)).squareRoot()
                    v += h / (1 + exp(1.6 * (d - 5)))
                }
                out[y * q + x] = Float(v)
            }
        }
        return out
    }

    static func kernel(q: Int) throws -> ProbeKernel {
        try XCTUnwrap(ProbeKernel.synthetic(radius: 5, qy: q, qx: q))
    }

    static func base() -> DiskDetectionParams {
        var p = DiskDetectionParams()
        p.minPeakSpacing = 20
        p.edgeBoundary = 10; p.minRelativeIntensity = 0.05
        return p
    }

    struct Case { let name: String; let q: Int; let params: DiskDetectionParams; let pattern: [Float] }

    static func cases() -> [Case] {
        let p0 = pattern(q: 256, seed: 1), p1 = pattern(q: 256, seed: 2)
        var nan = p1
        nan[100 * 256 + 100] = .nan; nan[40 * 256 + 200] = .infinity; nan[0] = -.infinity
        var multicorr = base(); multicorr.subpixel = .multicorr
        var half = base(); half.corrPower = 0.5
        var phase = base(); phase.corrPower = 0
        var smoothDP = base(); smoothDP.sigmaDP = 1.5
        var pixel = base(); pixel.subpixel = .pixel
        var capped = base(); capped.maxNumPeaks = 3; capped.minRelativeIntensity = 0.05
        return [
            Case(name: "poly", q: 256, params: base(), pattern: p0),
            Case(name: "poly-second", q: 256, params: base(), pattern: p1),
            Case(name: "multicorr", q: 256, params: multicorr, pattern: p0),
            Case(name: "power-half", q: 256, params: half, pattern: p0),
            Case(name: "power-zero", q: 256, params: phase, pattern: p0),
            Case(name: "sigma-dp", q: 256, params: smoothDP, pattern: p0),
            Case(name: "pixel", q: 256, params: pixel, pattern: p0),
            Case(name: "capped", q: 256, params: capped, pattern: p0),
            Case(name: "non-finite", q: 256, params: base(), pattern: nan),
            Case(name: "odd-125", q: 125, params: base(), pattern: pattern(q: 125, seed: 3)),
        ]
    }
}

final class DiskDetectorKitTests: XCTestCase {

    private struct Baseline: Decodable {
        struct Case: Decodable {
            let name: String
            let peaks: [[Double]]
            let funnel: [Int]
            let correlationMaximum: Double
        }
        let cases: [Case]
    }

    private func baseline() throws -> [String: Baseline.Case] {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/DiskDetector/kit-switch-baseline.json")
        let decoded = try JSONDecoder().decode(Baseline.self, from: Data(contentsOf: url))
        return Dictionary(uniqueKeysWithValues: decoded.cases.map { ($0.name, $0) })
    }

    private func kitOptions(_ p: DiskDetectionParams) -> BraggDiskOptions {
        var o = BraggDiskOptions.mac4DSTEM
        o.correlationPower = Double(p.corrPower); o.patternSigma = Double(p.sigmaDP); o.correlationSigma = Double(p.sigmaCC)
        o.subpixel = p.subpixel == .pixel ? .pixel : p.subpixel == .poly ? .parabolic : .multicorr
        o.upsampleFactor = p.upsampleFactor
        o.minimumAbsoluteIntensity = Double(p.minAbsoluteIntensity); o.minimumRelativeIntensity = Double(p.minRelativeIntensity)
        o.relativeToPeak = p.relativeToPeak; o.minimumPeakSpacing = Double(p.minPeakSpacing)
        o.edgeBoundary = p.edgeBoundary; o.maximumPeaks = p.maxNumPeaks
        return o   // .double: the numerical definition, pinned to py4DSTEM at 1e-9 px
    }

    /// Regression against the former in-app Float detector (generated from the code before the switch): same peak
    /// count and funnel, positions within the Float32 gap of the two paths. The tolerance is written from the measured
    /// gap (the former detector sat 1.8e-4 px from py4DSTEM, the kit's `.single` 1.3e-5 px): 2e-4 px, 2e-5 relative on
    /// intensities. The phase-correlation case (corrPower 0) is noise-dominated; only its strongest seven peaks are held.
    func testMatchesTheFormerDetectorOnSyntheticPatterns() throws {
        let former = try baseline()
        var worst = 0.0
        for c in DiskKitFixture.cases() {
            let old = try XCTUnwrap(former[c.name], c.name)
            let det = try XCTUnwrap(DiskDetector(kernel: DiskKitFixture.kernel(q: c.q)))
            let r = det.detectWithDiagnostics(pattern: c.pattern, params: c.params)
            let d = r.diagnostics
            let isNoise = c.name == "power-zero"
            let keep = isNoise ? 7 : old.peaks.count
            XCTAssertGreaterThanOrEqual(r.peaks.count, min(keep, old.peaks.count), c.name)
            if !isNoise {
                XCTAssertEqual(r.peaks.count, old.peaks.count, c.name)
                XCTAssertEqual([d.localMaximumCount, d.afterAbsoluteThresholdCount, d.afterRelativeThresholdCount, d.afterSpacingCount,
                                d.acceptedCount, d.wasCountLimited ? 1 : 0, d.relativeReferenceWasAvailable ? 1 : 0, d.nonFinitePixelCount],
                               old.funnel, "\(c.name) funnel")
                XCTAssertEqual(Double(d.correlationMaximum), old.correlationMaximum, accuracy: 2e-5 * old.correlationMaximum, c.name)
            }
            for (k, o) in old.peaks.prefix(keep).enumerated() where k < r.peaks.count {
                let p = r.peaks[k]
                let gap = max(abs(Double(p.x) - o[0]), abs(Double(p.y) - o[1]))
                worst = max(worst, gap)
                XCTAssertLessThan(gap, 2e-4, "\(c.name) peak \(k) position")
                XCTAssertEqual(Double(p.intensity), o[2], accuracy: max(2e-5 * abs(o[2]), 1e-7), "\(c.name) peak \(k) intensity")
            }
        }
        print("DISKKIT worst position gap to the former detector \(worst) px")
    }

    /// The facade against the kit's Double definition (py4DSTEM at 1e-9 px): the written gap is 2.5e-5 px on positions
    /// (the kit measures 1.3e-5 for `.single`), 5e-6 relative on intensities. The former Float detector sat 5.3e-5 px
    /// away on these patterns (the next test), so this fails on it.
    func testAgreesWithTheKitsDoubleDefinitionWithinTheFloat32Tolerance() throws {
        var worst = 0.0, worstIntensity = 0.0
        for name in ["poly", "multicorr", "sigma-dp", "non-finite", "odd-125"] {
            let c = try XCTUnwrap(DiskKitFixture.cases().first { $0.name == name })
            let det = try XCTUnwrap(DiskDetector(kernel: DiskKitFixture.kernel(q: c.q)))
            let image = try DetectorImage(detectorRows: c.q, detectorColumns: c.q, values: c.pattern.map(Double.init), path: .cpu)
            let kernel = try DiskKitFixture.kernel(q: c.q)
            let reference = try BraggDetector(kernel: DetectorImage(
                detectorRows: c.q, detectorColumns: c.q, values: kernel.kernel.map(Double.init), path: .cpu))
            let expected = try reference.detect(image, options: kitOptions(c.params))
            let got = det.detect(pattern: c.pattern, params: c.params)
            XCTAssertEqual(got.count, expected.count, name)
            for (g, e) in zip(got, expected) {
                worst = max(worst, abs(Double(g.x) - e.column), abs(Double(g.y) - e.row))
                worstIntensity = max(worstIntensity, abs(Double(g.intensity) - e.intensity) / abs(e.intensity))
                XCTAssertEqual(Double(g.x), e.column, accuracy: 2.5e-5, "\(name) x")
                XCTAssertEqual(Double(g.y), e.row, accuracy: 2.5e-5, "\(name) y")
                XCTAssertEqual(Double(g.intensity), e.intensity, accuracy: 5e-6 * abs(e.intensity) + 1e-7, "\(name) intensity")
            }
        }
        print("DISKKIT facade gap to the definition \(worst) px, \(worstIntensity) relative intensity")
    }

    /// The former detector's own gap to the Double definition, from the baseline fixture: wider than the new tolerance,
    /// which is why the previous test could not have passed on it (measured, printed).
    func testTheFormerDetectorWasOutsideTheFloat32ToleranceOfTheDefinition() throws {
        let former = try baseline()
        var worst = 0.0
        for name in ["poly", "multicorr", "sigma-dp"] {
            let c = try XCTUnwrap(DiskKitFixture.cases().first { $0.name == name })
            let kernel = try DiskKitFixture.kernel(q: c.q)
            let reference = try BraggDetector(kernel: DetectorImage(
                detectorRows: c.q, detectorColumns: c.q, values: kernel.kernel.map(Double.init), path: .cpu))
            let expected = try reference.detect(
                DetectorImage(detectorRows: c.q, detectorColumns: c.q, values: c.pattern.map(Double.init), path: .cpu),
                options: kitOptions(c.params))
            for (o, e) in zip(try XCTUnwrap(former[name]).peaks, expected) {
                worst = max(worst, abs(o[0] - e.column), abs(o[1] - e.row))
            }
        }
        print("DISKKIT former detector worst gap to the definition \(worst) px")
        XCTAssertGreaterThan(worst, 2.5e-5)
    }

    func testPointerAndArrayEntriesAgreeAndAnEntryCanBeSharedAcrossThreads() throws {
        let c = try XCTUnwrap(DiskKitFixture.cases().first { $0.name == "poly" })
        let det = try XCTUnwrap(DiskDetector(kernel: DiskKitFixture.kernel(q: c.q)))
        let a = det.detect(pattern: c.pattern, params: c.params)
        let b = c.pattern.withUnsafeBufferPointer { det.detect(pattern: $0.baseAddress!, params: c.params) }
        XCTAssertEqual(a.map(\.x), b.map(\.x)); XCTAssertEqual(a.map(\.intensity), b.map(\.intensity))
        let results = Results()
        DispatchQueue.concurrentPerform(iterations: 8) { _ in
            results.add(det.detect(pattern: c.pattern, params: c.params).map(\.x))
        }
        XCTAssertEqual(results.all.count, 8)
        for r in results.all { XCTAssertEqual(r, a.map(\.x), "a shared detector must give the same peaks on every thread") }
    }

    func testNonFinitePixelsAreCountedAndFilled() throws {
        let c = try XCTUnwrap(DiskKitFixture.cases().first { $0.name == "non-finite" })
        let det = try XCTUnwrap(DiskDetector(kernel: DiskKitFixture.kernel(q: c.q)))
        let r = det.detectWithDiagnostics(pattern: c.pattern, params: c.params)
        XCTAssertEqual(r.diagnostics.nonFinitePixelCount, 3)
        XCTAssertEqual(r.peaks.count, 7, "the NaN pattern must not lose its peaks (D019)")
    }

    /// The learned detector's inputs: the raw correlation and its sigmaCC-smoothed copy on the detector grid, equal to the
    /// kit's Double definition within the Float32 gap (1e-5 of the maximum), the smoothed maximum on the central disk.
    func testCorrelationSurfaceMatchesTheKitDefinition() throws {
        let c = try XCTUnwrap(DiskKitFixture.cases().first { $0.name == "poly" })
        let det = try XCTUnwrap(DiskDetector(kernel: DiskKitFixture.kernel(q: c.q)))
        let (raw, smoothed) = c.pattern.withUnsafeBufferPointer { det.correlation(pattern: $0.baseAddress!, params: c.params) }
        XCTAssertEqual(raw.count, 256 * 256); XCTAssertEqual(smoothed.count, 256 * 256)
        let kernel = try DiskKitFixture.kernel(q: c.q)
        let reference = try BraggDetector(kernel: DetectorImage(
            detectorRows: 256, detectorColumns: 256, values: kernel.kernel.map(Double.init), path: .cpu))
        let expected = try reference.correlate(
            DetectorImage(detectorRows: 256, detectorColumns: 256, values: c.pattern.map(Double.init), path: .cpu),
            options: kitOptions(c.params))
        let top = expected.real.max()!
        for i in raw.indices { XCTAssertEqual(Double(raw[i]), expected.real[i], accuracy: 1e-5 * top); if abs(Double(raw[i]) - expected.real[i]) > 1e-5 * top { break } }
        let argmax = smoothed.indices.max { smoothed[$0] < smoothed[$1] }!
        XCTAssertEqual(argmax / 256, 128, accuracy: 1); XCTAssertEqual(argmax % 256, 128, accuracy: 1)
        XCTAssertTrue(smoothed.allSatisfy { $0.isFinite })
    }

    /// Measurement, not a gate: ms per pattern at 256 x 256, poly, serial and on 8 workers (`print`).
    func testReportsTheCostPerPattern() throws {
        let kernel = try DiskKitFixture.kernel(q: 256)
        let pats = (0..<8).map { DiskKitFixture.pattern(q: 256, seed: UInt64(10 + $0)) }
        let params = DiskKitFixture.base()
        let det = try XCTUnwrap(DiskDetector(kernel: kernel))
        _ = det.detect(pattern: pats[0], params: params)
        var t0 = Date()
        for i in 0..<256 { _ = det.detect(pattern: pats[i % 8], params: params) }
        let serial = Date().timeIntervalSince(t0) / 256 * 1000
        t0 = Date()
        let total = 4096
        DispatchQueue.concurrentPerform(iterations: 8) { w in
            let d = DiskDetector(kernel: kernel)!
            for i in 0..<(total / 8) { _ = d.detect(pattern: pats[(w + i) % 8], params: params) }
        }
        let wall = Date().timeIntervalSince(t0) / Double(total) * 1000
        print("DISKTIMING serial ms/pattern \(serial) parallel8 wall ms/pattern \(wall)")
    }
}

private final class Results: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [[Float]] = []
    func add(_ r: [Float]) { lock.lock(); storage.append(r); lock.unlock() }
    var all: [[Float]] { lock.lock(); defer { lock.unlock() }; return storage }
}

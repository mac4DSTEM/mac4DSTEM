//
//  LearnedWindowedFixture.swift
//  A synthetic float diffraction pattern above the model's 256-px frame, with a known lattice of disks,
//  and the recall / precision score of a learned detection against it (D098 dose scale, D004 seam bands;
//  docs/archive/v4/learned-windows-D098-D004-gateD-2026-09-30.md). Deterministic: SplitMix64, no system randomness.
//
//  A float pattern whose maximum is <= 1 is a fraction of a 20 000-count beam (`simulate.to_counts`), so the
//  fixture is a float32 pattern with the direct beam at 0.9: exactly the case D098 concerns.
//

import XCTest
import Metal
import DSTEMCore
@testable import mac4DSTEM

struct WindowedFixture {
    struct Site { var x: Float; var y: Float; var intensity: Float }

    let qy: Int, qx: Int
    let radius: Float
    let beam: (x: Float, y: Float)
    var pixels: [Float]
    var probe: [Float]
    var sites: [Site]            // every non-beam disk drawn (the truth)

    /// One deterministic 64-bit stream.
    struct Rng {
        var s: UInt64
        mutating func next() -> UInt64 {
            s &+= 0x9E37_79B9_7F4A_7C15
            var z = s
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
        mutating func uniform() -> Double { Double(next() >> 11) / Double(1 << 53) }
        mutating func gaussian() -> Double {
            let u = max(uniform(), 1e-12), v = uniform()
            return (-2 * log(u)).squareRoot() * cos(2 * .pi * v)
        }
    }

    /// Soft-edged flat disk profile, as the training render's `flat` term.
    static func profile(_ d: Float, radius r: Float) -> Float { 0.5 * (1 - tanhf((d - r) / 0.8)) }

    /// `qy × qx` pattern: a square lattice of pitch `pitch` rotated `angle` degrees about `beam`, intensity falling
    /// with distance, the beam at 0.9, plus `extra` disks at the given (x, y) (kept only if >= 45 px from every
    /// other disk). Poisson-like noise at the 20 000-count nominal beam; the maximum stays <= 1.
    static func make(qy: Int, qx: Int, beam: (x: Float, y: Float), pitch: Float = 80, angle: Float = 12,
                     radius: Float = 12, extra: [(x: Float, y: Float)] = [], seed: UInt64 = 1) -> WindowedFixture {
        var sites: [Site] = []
        let a = angle * .pi / 180
        let a1 = (x: pitch * cosf(a), y: pitch * sinf(a)), a2 = (x: -pitch * sinf(a), y: pitch * cosf(a))
        let m = radius + 4
        for i in -30...30 { for j in -30...30 where !(i == 0 && j == 0) {
            let x = beam.x + Float(i) * a1.x + Float(j) * a2.x, y = beam.y + Float(i) * a1.y + Float(j) * a2.y
            guard x >= m, x < Float(qx) - m, y >= m, y < Float(qy) - m else { continue }
            let d = hypotf(x - beam.x, y - beam.y)
            sites.append(Site(x: x, y: y, intensity: 0.1 + 0.4 * expf(-d / 300)))
        } }
        for e in extra where e.x >= m && e.x < Float(qx) - m && e.y >= m && e.y < Float(qy) - m {
            let near = sites.contains { hypotf($0.x - e.x, $0.y - e.y) < 45 } || hypotf(beam.x - e.x, beam.y - e.y) < 45
            if !near { sites.append(Site(x: e.x, y: e.y, intensity: 0.35)) }
        }
        var expected = [Float](repeating: 0.002, count: qy * qx)      // a faint pedestal, in fractions of the beam
        func draw(_ cx: Float, _ cy: Float, _ inten: Float) {
            let w = Int(radius) + 4
            for y in max(Int(cy) - w, 0)..<min(Int(cy) + w + 1, qy) {
                for x in max(Int(cx) - w, 0)..<min(Int(cx) + w + 1, qx) {
                    expected[y * qx + x] += inten * profile(hypotf(Float(x) - cx, Float(y) - cy), radius: radius)
                }
            }
        }
        draw(beam.x, beam.y, 0.9)
        for s in sites { draw(s.x, s.y, s.intensity) }
        var rng = Rng(s: seed)
        var pixels = [Float](repeating: 0, count: qy * qx)
        let dose: Float = LearnedDiskDetector.nominalBeamCounts
        for i in pixels.indices {
            let mean = expected[i] * dose
            pixels[i] = max(mean + mean.squareRoot() * Float(rng.gaussian()), 0) / dose
        }
        var probe = [Float](repeating: 0, count: qy * qx)
        let w = Int(radius) + 6
        for y in max(Int(beam.y) - w, 0)..<min(Int(beam.y) + w + 1, qy) {
            for x in max(Int(beam.x) - w, 0)..<min(Int(beam.x) + w + 1, qx) {
                probe[y * qx + x] = profile(hypotf(Float(x) - beam.x, Float(y) - beam.y), radius: radius)
            }
        }
        return WindowedFixture(qy: qy, qx: qx, radius: radius, beam: beam, pixels: pixels, probe: probe, sites: sites)
    }

    /// The scan-1x1 cube buffer.
    func buffer() throws -> (MTLBuffer, DatasetDescriptor) {
        let b = try XCTUnwrap(MetalEngine.shared.device.makeBuffer(bytes: pixels, length: pixels.count * MemoryLayout<Float>.stride))
        return (b, DatasetDescriptor(filePath: "/synthetic/windowed.h5", datasetPath: "/d", shape: [1, 1, qy, qx], dtypeDescription: "float32", chunkShape: nil))
    }

    static func params(qy: Int, qx: Int) -> DiskDetectionParams {
        var p = DiskDetectionParams()
        p.sigmaCC = 2; p.subpixel = .poly; p.minPeakSpacing = 20
        p.edgeBoundary = max(2, min(qy, qx) / 24); p.maxNumPeaks = 500
        return p
    }

    func detect(_ learned: LearnedDiskDetector, params: DiskDetectionParams? = nil) async throws -> BraggVectors {
        let (buf, d) = try buffer()
        let p = params ?? Self.params(qy: qy, qx: qx)
        let out = await learned.detectAll(cube: buf, descriptor: d, probe: DiffractionPattern(qy: qy, qx: qx, pixels: probe),
                                          probeCentre: beam, probeRadius: radius, params: p)
        return try XCTUnwrap(out)
    }

    struct Score {
        var truth = 0, detections = 0, matched = 0, bandTruth = 0, bandMatched = 0
        var recall: Double { truth == 0 ? 0 : Double(matched) / Double(truth) }
        var precision: Double { detections == 0 ? 0 : Double(matched) / Double(detections) }
        var bandRecall: Double { bandTruth == 0 ? .nan : Double(bandMatched) / Double(bandTruth) }
        var line: String {
            String(format: "truth %d detections %d matched %d recall %.4f precision %.4f | band truth %d matched %d bandRecall %.4f",
                   truth, detections, matched, recall, precision, bandTruth, bandMatched, bandRecall)
        }
    }

    /// Recall / precision at `tol` px. The scored truth is the beam plus every drawn disk farther than `edge` px
    /// from the detector's own edges (the edge rule rejects those on purpose). `band` marks truth disks whose
    /// x or y lies in one of the intervals: the D004 seam bands.
    func score(_ peaks: [BraggPeak], edge: Int, tol: Float = 2, bandX: [Range<Float>] = [], bandY: [Range<Float>] = []) -> Score {
        var s = Score()
        var truth = sites.map { (x: $0.x, y: $0.y) } + [(x: beam.x, y: beam.y)]
        truth = truth.filter { $0.x >= Float(edge) && $0.x < Float(qx - edge) && $0.y >= Float(edge) && $0.y < Float(qy - edge) }
        var used = Set<Int>()
        s.truth = truth.count; s.detections = peaks.count
        for t in truth {
            let inBand = bandX.contains { $0.contains(t.x) } || bandY.contains { $0.contains(t.y) }
            if inBand { s.bandTruth += 1 }
            var best = -1; var bestD = tol
            for (i, p) in peaks.enumerated() where !used.contains(i) {
                let d = hypotf(p.x - t.x, p.y - t.y)
                if d <= bestD { bestD = d; best = i }
            }
            if best >= 0 { used.insert(best); s.matched += 1; if inBand { s.bandMatched += 1 } }
        }
        return s
    }
}

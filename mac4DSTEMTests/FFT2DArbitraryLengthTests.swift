//
//  FFT2DArbitraryLengthTests.swift
//  The FFT speedup session (2026-09-01, docs/s22-ux-design.md §6 HANDOFF 1).
//
//  FFT2D must be the EXACT N-point DFT for every length, because disk
//  detection's circular correlation, DPC's integration and the parallax /
//  ptychography paths all assume py4DSTEM's un-padded NumPy semantics. Until
//  this session a length vDSP does not support (250 = 2·5³ is the case that
//  cost 14 minutes on calibrationData_circularProbe.h5) fell to an O(N²)
//  scalar loop. It is now a Bluestein transform. These tests pin it against a
//  Double-precision direct DFT — the only reference that does not share an
//  implementation with the thing under test.
//

import XCTest
import DSTEMCore
@testable import mac4DSTEM

final class FFT2DArbitraryLengthTests: XCTestCase {

    // MARK: - Reference: direct DFT in Double, separable, no FFT anywhere

    /// Exact (to Double rounding) 2D DFT of a row-major [ny * nx] grid.
    private func directDFT(
        re: [Float], im: [Float], nx: Int, ny: Int, forward: Bool
    ) -> (re: [Double], im: [Double]) {
        let sign: Double = forward ? -1 : 1
        func line(_ xr: [Double], _ xi: [Double]) -> ([Double], [Double]) {
            let n = xr.count
            var outR = [Double](repeating: 0, count: n)
            var outI = [Double](repeating: 0, count: n)
            for k in 0..<n {
                var sr = 0.0, si = 0.0
                for j in 0..<n {
                    // Reduce j·k mod n first so the angle stays small in Double.
                    let angle = sign * 2 * Double.pi * Double((j * k) % n) / Double(n)
                    let c = cos(angle), s = sin(angle)
                    sr += xr[j] * c - xi[j] * s
                    si += xr[j] * s + xi[j] * c
                }
                outR[k] = sr; outI[k] = si
            }
            return (outR, outI)
        }
        var r = re.map(Double.init), i = im.map(Double.init)
        for y in 0..<ny {
            let rowR = Array(r[y * nx..<(y + 1) * nx])
            let rowI = Array(i[y * nx..<(y + 1) * nx])
            let (tr, ti) = line(rowR, rowI)
            r.replaceSubrange(y * nx..<(y + 1) * nx, with: tr)
            i.replaceSubrange(y * nx..<(y + 1) * nx, with: ti)
        }
        for x in 0..<nx {
            let colR = (0..<ny).map { r[$0 * nx + x] }
            let colI = (0..<ny).map { i[$0 * nx + x] }
            let (tr, ti) = line(colR, colI)
            for y in 0..<ny { r[y * nx + x] = tr[y]; i[y * nx + x] = ti[y] }
        }
        return (r, i)
    }

    /// Deterministic pseudo-random grid — a lattice of soft disks plus noise,
    /// the shape a detector pattern actually has, so the error budget below is
    /// measured on representative energy distributions, not on white noise.
    private func grid(nx: Int, ny: Int, seed: UInt64) -> (re: [Float], im: [Float]) {
        var state = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        func unit() -> Float {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Float(state >> 40) / Float(1 << 24)
        }
        var re = [Float](repeating: 0, count: nx * ny)
        var im = [Float](repeating: 0, count: nx * ny)
        for y in 0..<ny {
            for x in 0..<nx {
                var v: Float = 0.02 + 0.01 * unit()
                let dx = Float(x) - Float(nx) / 2, dy = Float(y) - Float(ny) / 2
                v += 1 / (1 + exp(((dx * dx + dy * dy).squareRoot() - 4) * 2))
                re[y * nx + x] = v
                im[y * nx + x] = 0.1 * unit()
            }
        }
        return (re, im)
    }

    /// Max |error| over the grid, relative to the largest reference magnitude.
    private func relativeMaxError(
        _ re: [Float], _ im: [Float], against ref: (re: [Double], im: [Double])
    ) -> Double {
        // Gate B (2026-09-02): `max(0.0, .nan)` is 0.0, so an all-NaN output
        // scored "error 0.0" here and passed four tests. Non-finite is infinite
        // error, not zero.
        guard re.allSatisfy(\.isFinite), im.allSatisfy(\.isFinite) else { return .infinity }
        var maxErr = 0.0, maxMag = 0.0
        for i in 0..<re.count {
            let er = Double(re[i]) - ref.re[i], ei = Double(im[i]) - ref.im[i]
            maxErr = max(maxErr, (er * er + ei * ei).squareRoot())
            maxMag = max(maxMag, (ref.re[i] * ref.re[i] + ref.im[i] * ref.im[i]).squareRoot())
        }
        return maxErr / maxMag
    }

    // MARK: - The case that cost 14 minutes

    func testForward250x250MatchesTheDirectDFT() throws {
        // 250 = 2·5³: no radix-2 setup, no exact radix-3/5 plan, and
        // vDSP_DFT_zop_CreateSetup returns nil (it needs f·2ⁿ, f ∈ {1,3,5,15}).
        // Bluestein is the only path left, so this test IS the 250 path.
        let fft = try XCTUnwrap(FFT2D(nx: 250, ny: 250))
        var (re, im) = grid(nx: 250, ny: 250, seed: 1)
        let reference = directDFT(re: re, im: im, nx: 250, ny: 250, forward: true)
        fft.transform(re: &re, im: &im, forward: true)
        let error = relativeMaxError(re, im, against: reference)
        // Measured 2026-09-01 (Release, standalone): 8.5e-8 — the same order
        // as vDSP's native 128×128 path (4.6e-8) and the radix-5 plan at
        // 125×125 (9.8e-8). The retired Float-angle scalar loop measured
        // 2.1e-5 on a 250-line (next test), so the bound sits where every
        // exact path passes and the old loop would not.
        XCTAssertLessThan(error, 2e-6, "250×250 forward relative max error \(error)")
    }

    func testTheRetiredScalarLoopWasLessAccurateThanBluestein() throws {
        // Evidence for re-pinning tools/disk-correlation-parity/baseline-250.json:
        // the pre-change baseline was recorded on the scalar loop, whose Float
        // angle 2π·j·k/N reaches ~1560 rad at N = 250 and carries ~1e-4 rad of
        // rounding. Bluestein's chirp is built in Double from n² mod 2N. The
        // 5e-6 relative shift the parity gate saw on the correlation checksums
        // is the OLD reference's error, not the new path's — this test makes
        // that claim measurable instead of asserted (measured: scalar 2.1e-5,
        // Bluestein 7.4e-8 on this line). The scalar loop is reproduced
        // verbatim from the retired code.
        let n = 250
        let (gre, gim) = grid(nx: n, ny: 1, seed: 7)
        let reference = directDFT(re: gre, im: gim, nx: n, ny: 1, forward: true)
        var scalarRe = [Float](repeating: 0, count: n)
        var scalarIm = [Float](repeating: 0, count: n)
        for k in 0..<n {
            var sumRe: Float = 0, sumIm: Float = 0
            for j in 0..<n {
                let angle = -1 * 2 * Float.pi * Float(j * k) / Float(n)
                let cosine = cos(angle), sine = sin(angle)
                sumRe += gre[j] * cosine - gim[j] * sine
                sumIm += gre[j] * sine + gim[j] * cosine
            }
            scalarRe[k] = sumRe; scalarIm[k] = sumIm
        }
        let scalarError = relativeMaxError(scalarRe, scalarIm, against: reference)
        let fft = try XCTUnwrap(FFT2D(nx: n, ny: 1))
        var re = gre, im = gim
        fft.transform(re: &re, im: &im, forward: true)
        let bluesteinError = relativeMaxError(re, im, against: reference)
        XCTAssertLessThan(bluesteinError, scalarError,
                          "Bluestein \(bluesteinError) should beat the scalar loop \(scalarError)")
        XCTAssertGreaterThan(scalarError, 1e-6,
                             "the retired loop's error \(scalarError) is the reason the 250 baseline moved")
    }

    func testInverseRoundTripAt250x250RecoversTheInput() throws {
        let fft = try XCTUnwrap(FFT2D(nx: 250, ny: 250))
        let (originalRe, originalIm) = grid(nx: 250, ny: 250, seed: 3)
        var re = originalRe, im = originalIm
        fft.transform(re: &re, im: &im, forward: true)
        fft.transform(re: &re, im: &im, forward: false)   // scaleInverse: true
        XCTAssertTrue(re.allSatisfy(\.isFinite) && im.allSatisfy(\.isFinite), "non-finite output")
        var maxErr: Float = 0
        for i in 0..<re.count {
            maxErr = max(maxErr, abs(re[i] - originalRe[i]), abs(im[i] - originalIm[i]))
        }
        XCTAssertLessThan(maxErr, 1e-5, "round-trip max abs error \(maxErr)")
    }

    func testUnscaledInverseKeepsTheVDSPConvention() throws {
        // `scaleInverse: false` must return N·x, exactly as vDSP's unnormalized
        // inverse does on the radix-2 path — MatrixDFTCorrelation and the
        // ptychography code rely on the two paths agreeing.
        let nx = 250, ny = 6
        let fft = try XCTUnwrap(FFT2D(nx: nx, ny: ny))
        let (originalRe, originalIm) = grid(nx: nx, ny: ny, seed: 5)
        var re = originalRe, im = originalIm
        fft.transform(re: &re, im: &im, forward: true)
        fft.transform(re: &re, im: &im, forward: false, scaleInverse: false)
        let n = Float(nx * ny)
        XCTAssertTrue(re.allSatisfy(\.isFinite) && im.allSatisfy(\.isFinite), "non-finite output")
        var maxErr: Float = 0
        for i in 0..<re.count {
            maxErr = max(maxErr, abs(re[i] / n - originalRe[i]), abs(im[i] / n - originalIm[i]))
        }
        XCTAssertLessThan(maxErr, 1e-5)
    }

    // MARK: - Other lengths no native path serves

    func testSmallUnsupportedLengthsMatchTheDirectDFTBothWays() throws {
        // 7 (prime), 6 = 3·2 and 10 = 5·2 (f·2ⁿ with n < 3, which vDSP_DFT
        // rejects), 12 = 3·2², 14 = 7·2, 254 = 2·127 (a realistic cropped
        // detector edge), 65 / 129 (2N−1 needs the NEXT power of two), and
        // 66 / 130 — the pair that actually pins the convolution length.
        // Gate B (2026-09-02) showed M = 2N−2 is NOT wrong (the only aliased
        // filter offsets are ±(N−1), equal because the chirp is even, and no
        // output sum uses both); the first wrong length is 2N−3. Padding to
        // nextPow2(2N−4) fits 128 / 256 at 66 / 130 and is 4.5e-2 / 7.2e-3
        // off the DFT there, so this row goes red for that mutation while
        // 65 / 129 stays green.
        // Non-square on purpose: an axis swap is invisible on a square grid.
        for (nx, ny) in [(7, 6), (10, 12), (14, 7), (254, 6), (6, 254), (1, 7), (65, 129), (66, 130)] {
            let fft = try XCTUnwrap(FFT2D(nx: nx, ny: ny), "\(nx)×\(ny)")
            let (gre, gim) = grid(nx: nx, ny: ny, seed: UInt64(nx * 1000 + ny))
            for forward in [true, false] {
                var re = gre, im = gim
                let reference = directDFT(re: gre, im: gim, nx: nx, ny: ny, forward: forward)
                fft.transform(re: &re, im: &im, forward: forward, scaleInverse: false)
                let error = relativeMaxError(re, im, against: reference)
                XCTAssertLessThan(error, 2e-6, "\(nx)×\(ny) forward=\(forward) error \(error)")
            }
        }
    }

    func testMixedAxesUseTheNativePathOnOneAxisAndBluesteinOnTheOther() throws {
        // 250 × 128: the separable path serves x with Bluestein and y with the
        // native radix-2 FFT. Both must agree with the direct DFT together.
        let nx = 250, ny = 128
        let fft = try XCTUnwrap(FFT2D(nx: nx, ny: ny))
        var (re, im) = grid(nx: nx, ny: ny, seed: 11)
        let reference = directDFT(re: re, im: im, nx: nx, ny: ny, forward: true)
        fft.transform(re: &re, im: &im, forward: true)
        let error = relativeMaxError(re, im, against: reference)
        XCTAssertLessThan(error, 2e-6, "250×128 error \(error)")
    }

    func testOnePlanServesConcurrentWorkersWithoutSharingScratch() throws {
        // DiskDetection builds one detector per worker but the plan type is
        // documented shareable; the Bluestein scratch is per-call. Eight
        // threads transforming through ONE FFT2D must each get the serial
        // answer bit-for-bit.
        let fft = try XCTUnwrap(FFT2D(nx: 250, ny: 10))
        let (gre, gim) = grid(nx: 250, ny: 10, seed: 13)
        var serialRe = gre, serialIm = gim
        fft.transform(re: &serialRe, im: &serialIm, forward: true)
        let workers = 8
        var results = [[Float]](repeating: [], count: workers)
        results.withUnsafeMutableBufferPointer { buffer in
            let base = buffer.baseAddress!
            DispatchQueue.concurrentPerform(iterations: workers) { w in
                var re = gre, im = gim
                for _ in 0..<20 { // repeat so the threads genuinely overlap
                    re = gre; im = gim
                    fft.transform(re: &re, im: &im, forward: true)
                }
                base[w] = re + im
            }
        }
        for w in 0..<workers {
            XCTAssertEqual(results[w], serialRe + serialIm, "worker \(w) diverged")
        }
    }
}

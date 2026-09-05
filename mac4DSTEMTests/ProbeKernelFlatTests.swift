import XCTest
import DSTEMCore
@testable import mac4DSTEM

/// The FLAT measured-kernel mode (py4DSTEM `get_probe_kernel_flat`): the
/// probe normalised to unit sum and Fourier-shifted so its centre lands on
/// the array corner, nothing masked, nothing subtracted. Added 2026-09-05 for
/// the bullseye item, where the trench mode leaves the beam never the
/// brightest correlation peak (`docs/open-items.md`).
final class ProbeKernelFlatTests: XCTestCase {

    private func gaussianProbe(qy: Int, qx: Int, cx: Float, cy: Float, sigma: Float) -> DiffractionPattern {
        var pixels = [Float](repeating: 0, count: qy * qx)
        for y in 0..<qy {
            for x in 0..<qx {
                let dx = Float(x) - cx, dy = Float(y) - cy
                pixels[y * qx + x] = 1000 * exp(-(dx * dx + dy * dy) / (2 * sigma * sigma))
            }
        }
        return DiffractionPattern(qy: qy, qx: qx, pixels: pixels)
    }

    /// Concentric rings like the bullseye aperture: bright to 3 px, dark 4–5,
    /// bright 6–10, then nothing.
    private func bullseyeProbe(qy: Int, qx: Int, cx: Float, cy: Float) -> DiffractionPattern {
        var pixels = [Float](repeating: 0, count: qy * qx)
        for y in 0..<qy {
            for x in 0..<qx {
                let r = ((Float(x) - cx) * (Float(x) - cx) + (Float(y) - cy) * (Float(y) - cy)).squareRoot()
                pixels[y * qx + x] = r <= 3 ? 1000 : (r >= 6 && r <= 10 ? 700 : (r > 10 && r < 11 ? 200 : 0))
            }
        }
        return DiffractionPattern(qy: qy, qx: qx, pixels: pixels)
    }

    /// Centre of mass in WRAPPED coordinates: a kernel centred on the corner
    /// reads (0, 0).
    private func wrappedCentre(_ kernel: [Float], qy: Int, qx: Int) -> (x: Float, y: Float) {
        var sx: Float = 0, sy: Float = 0, total: Float = 0
        for y in 0..<qy {
            let wy = Float(y < (qy + 1) / 2 ? y : y - qy)
            for x in 0..<qx {
                let wx = Float(x < (qx + 1) / 2 ? x : x - qx)
                let v = kernel[y * qx + x]
                sx += v * wx; sy += v * wy; total += v
            }
        }
        return (sx / total, sy / total)
    }

    func testFlatKernelIntegratesToOneAndPutsTheProbeCentreOnTheCorner() throws {
        let qy = 48, qx = 64
        let probe = gaussianProbe(qy: qy, qx: qx, cx: 20.3, cy: 12.7, sigma: 2.5)
        let kernel = try XCTUnwrap(ProbeKernel.flat(pattern: probe, originX: 20.3, originY: 12.7, radius: 3))
        XCTAssertEqual(kernel.kernel.reduce(0, +), 1, accuracy: 1e-4, "get_probe_kernel_flat normalises to unit sum")
        let centre = wrappedCentre(kernel.kernel, qy: qy, qx: qx)
        XCTAssertEqual(centre.x, 0, accuracy: 0.01, "a fractional shift must land the centre on the corner, not a pixel away")
        XCTAssertEqual(centre.y, 0, accuracy: 0.01)
        XCTAssertEqual(kernel.mode, .flat)
        XCTAssertEqual(kernel.trenchRadii.inner, 0)
        XCTAssertEqual(kernel.trenchRadii.outer, 0)
    }

    func testFlatKernelAtAnIntegerCentreIsTheRolledNormalisedProbe() throws {
        let qy = 40, qx = 56
        let probe = bullseyeProbe(qy: qy, qx: qx, cx: 30, cy: 20)
        let kernel = try XCTUnwrap(ProbeKernel.flat(pattern: probe, originX: 30, originY: 20, radius: 10))
        let total = probe.pixels.reduce(0, +)
        var worst: Float = 0
        for y in 0..<qy {
            for x in 0..<qx {
                // the probe pixel that lands at (x, y) after rolling by (-30, -20)
                let sy = (y + 20) % qy, sx = (x + 30) % qx
                worst = max(worst, abs(kernel.kernel[y * qx + x] - probe.pixels[sy * qx + sx] / total))
            }
        }
        XCTAssertLessThan(worst, 2e-6, "an integer shift is an exact roll; the Fourier shift must agree to float precision")
    }

    func testFlatKernelCorrelationPeaksOnTheStructuredProbeItself() throws {
        // The probe pattern correlated with its own flat kernel: the brightest
        // peak is the probe centre. This is the property the trench cannot
        // promise for a ringed probe (bullseye Gate D, 2026-09-05).
        let qy = 64, qx = 64
        let probe = bullseyeProbe(qy: qy, qx: qx, cx: 33, cy: 29)
        let kernel = try XCTUnwrap(ProbeKernel.flat(pattern: probe, originX: 33, originY: 29, radius: 10))
        let detector = try XCTUnwrap(DiskDetector(kernel: kernel))
        var params = DiskDetectionParams()
        params.minPeakSpacing = 4
        params.edgeBoundary = 2
        params.subpixel = .poly
        let peaks = probe.pixels.withUnsafeBufferPointer { detector.detect(pattern: $0.baseAddress!, params: params) }
        let brightest = try XCTUnwrap(peaks.max { $0.intensity < $1.intensity })
        XCTAssertEqual(brightest.x, 33, accuracy: 0.5)
        XCTAssertEqual(brightest.y, 29, accuracy: 0.5)
    }

    /// Correlation, not convolution: with an ASYMMETRIC probe the brightest
    /// self-correlation peak is the probe centre; dropping the conjugation of
    /// the kernel's transform turns the correlation into a convolution and
    /// moves that peak to the mirror image (Gate B refuter, 2026-09-05 — the
    /// radially symmetric cases above cannot see it).
    func testFlatKernelCorrelatesRatherThanConvolvesAnAsymmetricProbe() throws {
        let qy = 64, qx = 64
        var pixels = [Float](repeating: 0, count: qy * qx)
        for y in 0..<qy {
            for x in 0..<qx {
                let d1 = ((Float(x) - 30) * (Float(x) - 30) + (Float(y) - 28) * (Float(y) - 28)).squareRoot()
                let d2 = ((Float(x) - 41) * (Float(x) - 41) + (Float(y) - 31) * (Float(y) - 31)).squareRoot()
                pixels[y * qx + x] = (d1 <= 3 ? 1000 : 0) + (d2 <= 2 ? 400 : 0)
            }
        }
        let probe = DiffractionPattern(qy: qy, qx: qx, pixels: pixels)
        // The probe's own centre of mass is what get_probe_kernel_flat shifts to the corner.
        var sx: Float = 0, sy: Float = 0, total: Float = 0
        for y in 0..<qy { for x in 0..<qx { let v = pixels[y * qx + x]; sx += v * Float(x); sy += v * Float(y); total += v } }
        let cx = sx / total, cy = sy / total
        let kernel = try XCTUnwrap(ProbeKernel.flat(pattern: probe, originX: cx, originY: cy, radius: 4))
        let detector = try XCTUnwrap(DiskDetector(kernel: kernel))
        var params = DiskDetectionParams()
        params.minPeakSpacing = 4
        params.edgeBoundary = 2
        params.subpixel = .poly
        let peaks = pixels.withUnsafeBufferPointer { detector.detect(pattern: $0.baseAddress!, params: params) }
        let brightest = try XCTUnwrap(peaks.max { $0.intensity < $1.intensity })
        XCTAssertEqual(brightest.x, cx, accuracy: 0.15, "the self-correlation peak is the probe's centre of mass")
        XCTAssertEqual(brightest.y, cy, accuracy: 0.15)
    }

    func testANonFinitePixelCountsAsZeroNotPoison() throws {
        var probe = gaussianProbe(qy: 32, qx: 32, cx: 15.5, cy: 16.5, sigma: 2)
        var pixels = probe.pixels
        pixels[5 * 32 + 7] = .nan
        pixels[9 * 32 + 3] = .infinity
        probe = DiffractionPattern(qy: 32, qx: 32, pixels: pixels)
        let kernel = try XCTUnwrap(ProbeKernel.flat(pattern: probe, originX: 15.5, originY: 16.5, radius: 3))
        XCTAssertTrue(kernel.kernel.allSatisfy(\.isFinite))
        XCTAssertEqual(kernel.kernel.reduce(0, +), 1, accuracy: 1e-4)
    }

    func testMeasuredWithFlatModeRecordsSourceModeAndPath() throws {
        let probe = gaussianProbe(qy: 32, qx: 32, cx: 16, cy: 16, sigma: 2)
        let kernel = try XCTUnwrap(ProbeKernel.measured(
            pattern: probe, originX: 16, originY: 16, radius: 3,
            mode: .flat, source: .fileProbe, probePath: "/4DSTEM_experiment/data/diffractionslices/probe_template/data"
        ))
        XCTAssertEqual(kernel.source, .fileProbe)
        XCTAssertEqual(kernel.source.provenanceID, "measured_file_probe")
        XCTAssertEqual(kernel.mode, .flat)
        XCTAssertEqual(kernel.probePath, "/4DSTEM_experiment/data/diffractionslices/probe_template/data")
        // The default mode is unchanged: the trench, with nothing recorded as a path.
        let trench = try XCTUnwrap(ProbeKernel.measured(pattern: probe, originX: 16, originY: 16, radius: 3))
        XCTAssertEqual(trench.mode, .sigmoidTrench)
        XCTAssertEqual(trench.source, .measured)
        XCTAssertNil(trench.probePath)
        XCTAssertEqual(trench.trenchRadii.inner, 3)
    }
}

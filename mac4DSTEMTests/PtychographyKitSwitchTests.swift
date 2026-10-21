import XCTest
import DSTEMCore
import struct CuboPtycho.PtychographyArray
import struct CuboPtycho.PtychographyPosition
import enum CuboPtycho.SingleslicePtychography
@testable import mac4DSTEM

/// Session 5 (2026-10-21): the initial probe is CuboKit 0.6.0's `PtychographyProbe.build` (C21 to C56 and any other (n, m) term), the
/// app's own probe builder and its Float FFT are gone. The fixture `Fixtures/Ptychography/probe-engine-baseline-881f8e0a.json`
/// holds what the code before the switch produced (the app's Float builder and Float engine, commit 881f8e0a) on inputs this class
/// regenerates, and what CuboPtycho's Double engine produced on the same Float inputs.
///
/// Tolerances (D12, Float32 results): the probe moves by float rounding only (measured 6e-8 absolute on a peak of 0.42 and 1.2e-7 on
/// 1.1, i.e. one Float ulp: the old builder's Float FFT against the kit's Double one); four reconstruction iterations amplify that to
/// 3.8e-6 absolute on values near 1 (measured), tolerance 1e-5. The app's engine is CuboPtycho 0.7.0's (the app's own Float engine is
/// gone): a detector size vDSP takes (`16 x 16` below) runs the kit's Float32 path, `12 x 10` its Double path; the four option sets below
/// (12 x 10, so the Double path) are held to the pre-switch result and to the kit's Double result at 1e-5, the Float32 path to the kit's
/// Double result at 1e-4 (the kit's written tolerance, measured 2e-7 here, and 3e-7 against the old Float engine on 16 x 16 to 32 x 24).
@MainActor
final class PtychographyKitSwitchTests: XCTestCase {
    private struct Run: Decodable { let name: String; let objRe: [Double]; let objIm: [Double]; let prRe: [Double]; let prIm: [Double]; let errors: [Double] }
    private struct Probe: Decodable { let real: [Double]; let imag: [Double] }
    private struct Golden: Decodable { let qy: Int; let qx: Int; let real: [Double]; let imag: [Double] }
    private struct Baseline: Decodable { let probes: [Probe]; let runs: [Run]; let goldens: [Golden]; let kitRuns: [Run] }

    private func baseline() throws -> Baseline {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/Ptychography/probe-engine-baseline-881f8e0a.json")
        return try JSONDecoder().decode(Baseline.self, from: Data(contentsOf: url))
    }

    private struct LCG { var s: UInt64
        mutating func next() -> Double { s = s &* 6364136223846793005 &+ 1442695040888963407; return Double(s >> 11) / Double(1 << 53) } }

    private let detectorHeight = 12, detectorWidth = 10
    private let wavelength = 0.0418, cutoff = 0.02, rolloff = 0.003

    private func probe(_ aberrations: PtychographyProbeAberrations) throws -> (real: [Float], imaginary: [Float]) {
        try PtychographyPreparer.initialProbe(
            detectorHeight: detectorHeight, detectorWidth: detectorWidth, rowSamplingAngstrom: 0.5, columnSamplingAngstrom: 0.6,
            wavelengthAngstrom: wavelength, cutoffRad: cutoff, rolloffRad: rolloff, aberrations: aberrations)
    }

    private let aberrationSets = [
        PtychographyProbeAberrations(),
        PtychographyProbeAberrations(defocusAngstrom: 50, c12aAngstrom: 10, c12bAngstrom: -7),
        PtychographyProbeAberrations(defocusAngstrom: -30, c12aAngstrom: 4, c12bAngstrom: 9, higherOrder: [
            .init(radialOrder: 2, angularOrder: 1, component: 0, coefficientAngstrom: 2000),
            .init(radialOrder: 2, angularOrder: 1, component: 1, coefficientAngstrom: -1500),
            .init(radialOrder: 3, angularOrder: 0, component: 0, coefficientAngstrom: 90000),
            .init(radialOrder: 4, angularOrder: 3, component: 1, coefficientAngstrom: 4e5),
            .init(radialOrder: 5, angularOrder: 6, component: 0, coefficientAngstrom: -3e6),
            .init(radialOrder: 6, angularOrder: 5, component: 1, coefficientAngstrom: 7e7)]),
    ]

    private func assertClose(_ actual: [Float], _ expected: [Double], tolerance: Double, _ label: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.count, expected.count, label, file: file, line: line)
        var worst = 0.0
        for (a, e) in zip(actual, expected) { worst = max(worst, abs(Double(a) - e)) }
        XCTAssertLessThanOrEqual(worst, tolerance, "\(label): max |delta| \(worst)", file: file, line: line)
    }

    /// Defocus, cartesian astigmatism and C21 to C56 terms reach the kit with the right sign and angle. Mutation: pass the
    /// astigmatism angle as atan2(a, b) / 2 or drop `kitHigherOrder`'s sine mapping -> red (probe 1 and 2 move by far more than 2e-7).
    func testProbeMatchesTheCodeBeforeTheSwitch() throws {
        let fixture = try baseline()
        for (index, aberrations) in aberrationSets.enumerated() {
            let built = try probe(aberrations)
            assertClose(built.real, fixture.probes[index].real, tolerance: 2e-7, "probe \(index) real")
            assertClose(built.imaginary, fixture.probes[index].imag, tolerance: 2e-7, "probe \(index) imaginary")
        }
    }

    /// The aberration-free probe through the preparer on two demo-cube crops (was a bitwise hash of the old builder's output).
    /// Mutation: a wrong rolloff, normalisation or intensity scale -> red.
    func testPreparedAberrationFreeProbeMatchesTheCodeBeforeTheSwitch() async throws {
        let fixture = try baseline()
        let crops: [(ry: Int, rx: Int, qy: Int, qx: Int, q: Double, radius: Float, originQX: Double, originQY: Double)] = [
            (3, 4, 16, 24, 0.05, 8, 0, 0), (2, 3, 24, 32, 0.0213, 7.5, 1.25, 0.5)]
        let source = DemoFourDDataSource()
        let full = try await source.discoverPrimaryDataset()
        for (index, crop) in crops.enumerated() {
            let specification = LoadSpecification(
                scanCrop: AxisCrop(yOffset: 0, xOffset: 0, height: crop.ry, width: crop.rx),
                detectorCrop: AxisCrop(yOffset: 0, xOffset: 0, height: crop.qy, width: crop.qx))
            let view = try LoadView(source: full, specification: specification)
            let calibration = ParallaxPhysicalCalibration(
                scanSamplingAngstrom: 1.0, reciprocalSamplingInvAngstrom: crop.q, energyEV: 80_000,
                wavelengthAngstrom: ParallaxPreprocessor.electronWavelengthAngstrom(energyEV: 80_000),
                originQX: crop.originQX, originQY: crop.originQY, rotationRad: 0, transpose: false)
            let input = try await PtychographyPreparer.prepare(source: source, view: view, calibration: calibration, probeRadiusPixels: crop.radius)
            XCTAssertEqual(fixture.goldens[index].qy, crop.qy)
            assertClose(input.initialProbe.real, fixture.goldens[index].real, tolerance: 3e-7, "crop \(index) real")
            assertClose(input.initialProbe.imaginary, fixture.goldens[index].imag, tolerance: 3e-7, "crop \(index) imaginary")
        }
    }

    private func engineInput() throws -> SingleslicePtychographyInput {
        var g = LCG(s: 12345)
        let scanHeight = 4, scanWidth = 3, count = detectorHeight * detectorWidth, objectHeight = 20, objectWidth = 18
        var positions = [PtychographyScanPosition]()
        for r in 0..<scanHeight { for c in 0..<scanWidth {
            positions.append(PtychographyScanPosition(row: Float(2.2 + Double(r) * 3.3 + g.next()), column: Float(1.7 + Double(c) * 2.9 + g.next())))
        } }
        var amplitudes = [Float]()
        for _ in 0..<(scanHeight * scanWidth * count) { amplitudes.append(Float(0.2 + 3 * g.next())) }
        let start = try probe(aberrationSets[2])
        var objectReal = [Float](repeating: 1, count: objectHeight * objectWidth), objectImaginary = [Float](repeating: 0, count: objectHeight * objectWidth)
        for i in 0..<objectReal.count { objectReal[i] = Float(0.8 + 0.5 * g.next()); objectImaginary[i] = Float(0.3 * (g.next() - 0.5)) }
        return SingleslicePtychographyInput(
            scanHeight: scanHeight, scanWidth: scanWidth, detectorHeight: detectorHeight, detectorWidth: detectorWidth,
            amplitudes: amplitudes, positions: positions, objectSamplingRowAngstrom: 0.5, objectSamplingColumnAngstrom: 0.6,
            initialObject: PtychographyComplexArray(width: objectWidth, height: objectHeight, real: objectReal, imaginary: objectImaginary),
            initialProbe: PtychographyComplexArray(width: detectorWidth, height: detectorHeight, real: start.real.map { $0 * 1.5 }, imaginary: start.imaginary.map { $0 * 1.5 }),
            probeAberrations: aberrationSets[2])
    }

    private func options(_ name: String) -> SingleslicePtychographyOptions {
        var o = SingleslicePtychographyOptions()
        o.iterations = 4
        switch name {
        case "noObjectCap": o.constrainObjectAmplitude = false
        case "purePhaseComAmp": o.purePhaseObject = true; o.fixProbeCenterOfMass = true; o.constrainProbeAmplitude = true
        case "fixProbeStep": o.fixProbe = true; o.stepSize = 0.3; o.normalizationMinimum = 0.5
        default: break
        }
        return o
    }

    /// Four option sets from the kit-built probe: against the pre-switch result (probe rounding only) and against CuboPtycho's
    /// Double engine on the same inputs. Mutation: swap the object cap off/on or break any probe constraint -> red.
    func testEngineRunsMatchTheCodeBeforeTheSwitchAndTheKitEngine() throws {
        let fixture = try baseline()
        let input = try engineInput()
        for (before, kit) in zip(fixture.runs, fixture.kitRuns) {
            XCTAssertEqual(before.name, kit.name)
            let result = try PtychographyReconstructor.reconstruct(input: input, options: options(before.name))
            for (label, expected) in [("before", before), ("kit", kit)] {
                assertClose(result.object.real, expected.objRe, tolerance: 1e-5, "\(before.name) object real vs \(label)")
                assertClose(result.object.imaginary, expected.objIm, tolerance: 1e-5, "\(before.name) object imaginary vs \(label)")
                assertClose(result.probe.real, expected.prRe, tolerance: 1e-5, "\(before.name) probe real vs \(label)")
                assertClose(result.probe.imaginary, expected.prIm, tolerance: 1e-5, "\(before.name) probe imaginary vs \(label)")
                assertClose(result.errorHistory, expected.errors, tolerance: 1e-5, "\(before.name) errors vs \(label)")
            }
        }
    }

    /// A probe whose aperture is empty (a zero cutoff) is the app's own refusal, in the app's words.
    func testAnEmptyApertureIsRefusedInTheAppsWords() {
        XCTAssertThrowsError(try PtychographyPreparer.initialProbe(
            detectorHeight: 12, detectorWidth: 10, rowSamplingAngstrom: 0.5, columnSamplingAngstrom: 0.6,
            wavelengthAngstrom: 0.0418, cutoffRad: 0, rolloffRad: 0, aberrations: PtychographyProbeAberrations())) { error in
            XCTAssertEqual(error as? PtychographyReconstructor.ReconstructionError,
                           .invalidInput("the calibrated probe aperture is empty"))
        }
    }

    /// The Float32 path (a 16 x 16 detector, a size vDSP takes) agrees with the kit's Double engine on the same inputs to 1e-4 absolute,
    /// the Float32 tolerance written in the kit's `SinglePrecisionTests`, and reports each iteration to `progress`. Mutation: a wrong
    /// option mapping (the object cap, the step size) -> red.
    func testTheFloatPathAgreesWithTheKitDoubleEngineAndReportsProgress() throws {
        var g = LCG(s: 777)
        let scanHeight = 3, scanWidth = 3, n = 16, count = n * n, objectSize = 28
        var positions = [PtychographyScanPosition]()
        for r in 0..<scanHeight { for c in 0..<scanWidth {
            positions.append(PtychographyScanPosition(row: Float(2.2 + Double(r) * 4.3 + g.next()), column: Float(1.7 + Double(c) * 3.9 + g.next())))
        } }
        let amplitudes = (0..<(scanHeight * scanWidth * count)).map { _ in Float(0.2 + 3 * g.next()) }
        let objectReal = (0..<(objectSize * objectSize)).map { _ in Float(0.8 + 0.5 * g.next()) }
        let objectImaginary = (0..<(objectSize * objectSize)).map { _ in Float(0.3 * (g.next() - 0.5)) }
        let probeReal = (0..<count).map { _ in Float(g.next() - 0.5) }, probeImaginary = (0..<count).map { _ in Float(g.next() - 0.5) }
        let input = SingleslicePtychographyInput(
            scanHeight: scanHeight, scanWidth: scanWidth, detectorHeight: n, detectorWidth: n, amplitudes: amplitudes, positions: positions,
            objectSamplingRowAngstrom: 0.5, objectSamplingColumnAngstrom: 0.6,
            initialObject: PtychographyComplexArray(width: objectSize, height: objectSize, real: objectReal, imaginary: objectImaginary),
            initialProbe: PtychographyComplexArray(width: n, height: n, real: probeReal, imaginary: probeImaginary))
        var options = SingleslicePtychographyOptions()
        options.iterations = 5; options.stepSize = 0.4; options.fixProbeCenterOfMass = true

        final class Fractions: @unchecked Sendable { var values = [Double]() }
        let fractions = Fractions()
        let result = try PtychographyReconstructor.reconstruct(input: input, options: options, progress: { fractions.values.append($0) })
        XCTAssertEqual(fractions.values, (1...5).map { Double($0) / 5 })

        let kit = try SingleslicePtychography.reconstruct(
            amplitudes: amplitudes.map { Double($0) },
            positions: positions.map { PtychographyPosition(row: Double($0.row), column: Double($0.column)) },
            object: PtychographyArray(rows: objectSize, columns: objectSize, real: objectReal.map { Double($0) }, imaginary: objectImaginary.map { Double($0) }),
            probe: PtychographyArray(rows: n, columns: n, real: probeReal.map { Double($0) }, imaginary: probeImaginary.map { Double($0) }),
            iterations: 5, stepSize: 0.4, fixProbeCenterOfMass: true)
        func worst(_ a: [Float], _ b: [Double]) -> Double { zip(a, b).map { abs(Double($0) - $1) }.max() ?? .infinity }
        XCTAssertLessThanOrEqual(worst(result.object.real, kit.object.real), 1e-4, "object real")
        XCTAssertLessThanOrEqual(worst(result.object.imaginary, kit.object.imaginary), 1e-4, "object imaginary")
        XCTAssertLessThanOrEqual(worst(result.probe.real, kit.probe.real), 1e-4, "probe real")
        XCTAssertLessThanOrEqual(worst(result.errorHistory, kit.errors), 1e-4, "error history")
    }

    /// A cancel raised from the progress callback stops the run at the next poll and is the app's `.cancelled`, on both paths
    /// (16 x 16 Float32, 12 x 10 Double). Mutation: dropping `isCancelled:` from either kit call -> the run completes, red.
    func testCancellationFromProgressStopsBothPaths() throws {
        for (dh, dw) in [(16, 16), (12, 10)] {
            var g = LCG(s: 5)
            let count = dh * dw, scan = 2
            let input = SingleslicePtychographyInput(
                scanHeight: scan, scanWidth: scan, detectorHeight: dh, detectorWidth: dw,
                amplitudes: (0..<(scan * scan * count)).map { _ in Float(0.5 + g.next()) },
                positions: (0..<(scan * scan)).map { PtychographyScanPosition(row: Float($0) * 2.5 + 1, column: Float($0) * 1.5 + 2) },
                objectSamplingRowAngstrom: 0.5, objectSamplingColumnAngstrom: 0.5,
                initialObject: PtychographyComplexArray(width: dw + 8, height: dh + 8, real: [Float](repeating: 1, count: (dh + 8) * (dw + 8)), imaginary: [Float](repeating: 0, count: (dh + 8) * (dw + 8))),
                initialProbe: PtychographyComplexArray(width: dw, height: dh, real: (0..<count).map { _ in Float(g.next()) }, imaginary: [Float](repeating: 0, count: count)))
            var options = SingleslicePtychographyOptions()
            options.iterations = 50
            let token = AnalysisCancellationToken()
            XCTAssertThrowsError(try PtychographyReconstructor.reconstruct(
                input: input, options: options, cancellation: token, progress: { _ in token.cancel() }), "\(dh)x\(dw)") {
                XCTAssertEqual($0 as? PtychographyReconstructor.ReconstructionError, .cancelled, "\(dh)x\(dw)")
            }
        }
    }
}

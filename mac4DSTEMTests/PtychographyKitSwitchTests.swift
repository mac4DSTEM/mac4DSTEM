import XCTest
import DSTEMCore
@testable import mac4DSTEM

/// Session 5 (2026-10-21): the initial probe is CuboKit 0.6.0's `PtychographyProbe.build` (C21 to C56 and any other (n, m) term), the
/// app's own probe builder and its Float FFT are gone. The fixture `Fixtures/Ptychography/probe-engine-baseline-881f8e0a.json`
/// holds what the code before the switch produced (the app's Float builder and Float engine, commit 881f8e0a) on inputs this class
/// regenerates, and what CuboPtycho's Double engine produced on the same Float inputs.
///
/// Tolerances (D12, Float32 results): the probe moves by float rounding only (measured 6e-8 absolute on a peak of 0.42 and 1.2e-7 on
/// 1.1, i.e. one Float ulp: the old builder's Float FFT against the kit's Double one); four reconstruction iterations amplify that to
/// 3.8e-6 absolute on values near 1 (measured), tolerance 1e-5. The app engine against the kit's Double engine on identical Float
/// inputs: 3.4e-6 measured, tolerance 1e-5 (DEVIATION: the app engine accumulates in Float and is 4x faster than the kit's; it stays
/// until the kit has a Float engine with cancellation and progress, see `SingleslicePtychography.swift`).
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
        var positions = [PtychographyPosition]()
        for r in 0..<scanHeight { for c in 0..<scanWidth {
            positions.append(PtychographyPosition(row: Float(2.2 + Double(r) * 3.3 + g.next()), column: Float(1.7 + Double(c) * 2.9 + g.next())))
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
            let result = try SingleslicePtychography.reconstruct(input: input, options: options(before.name))
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
            XCTAssertEqual(error as? SingleslicePtychography.ReconstructionError,
                           .invalidInput("the calibrated probe aperture is empty"))
        }
    }
}

import Foundation

/// D002 (Gate D, 2026-09-09): one scan-position case and the wrong
/// conventions it must NOT match.
struct PositionCase: Decodable {
    let ry: Int, rx: Int, qy: Int, qx: Int
    let rotationDeg: Double
    let transpose: Bool
    let scanSamplingAngstrom: Double
    let qSamplingInvAngstrom: Double
    let expected: [Double]
    let controls: [String: [Double]]
}

/// R1 (2026-09-30): one initial-probe case. `polar` is what py4DSTEM's ComplexProbe was given; `cartesian` is what py4DSTEM's own
/// `polar_aberrations_to_cartesian` derives from it (C10 = -defocus, C12a/C12b, C21a/C21b, ...); `real`/`imag` are the
/// corner-centred unit-norm `ComplexProbe(...).build()._array`.
struct ProbeCase: Decodable {
    let name: String
    let gptsRow: Int, gptsColumn: Int
    let samplingRow: Double, samplingColumn: Double
    let energyEV: Double, semiangleMrad: Double, rolloffMrad: Double
    let polar: [String: Double]
    let cartesian: [String: Double]
    let real: [Double]
    let imag: [Double]
}

/// FNV-1a over the bit patterns: the golden hashes below were captured from the probe code at git 02174c9c, BEFORE R1.
func bitHash(_ values: [Float]) -> UInt64 {
    var hash: UInt64 = 0xcbf29ce484222325
    for value in values {
        var bits = value.bitPattern
        for _ in 0..<4 {
            hash ^= UInt64(bits & 0xff)
            hash = hash &* 0x100000001b3
            bits >>= 8
        }
    }
    return hash
}

/// py4DSTEM's cartesian terms as the app's aberrations: defocus = -C10 (ComplexProbe C10 = -defocus), C12a/C12b, and every other
/// "C{m}{n}[a|b]" as a higher-order term with radial order m = first digit, angular order n = second digit.
func probeAberrations(from cartesian: [String: Double]) -> PtychographyProbeAberrations {
    var aberrations = PtychographyProbeAberrations()
    for (key, value) in cartesian.sorted(by: { $0.key < $1.key }) {
        let digits = Array(key.dropFirst())
        let radial = Int(String(digits[0]))!, angular = Int(String(digits[1]))!
        if radial == 1 && angular == 0 { aberrations.defocusAngstrom = -value; continue }
        if radial == 1 && angular == 2 {
            if digits.count == 3 && digits[2] == "a" { aberrations.c12aAngstrom = value }
            else { aberrations.c12bAngstrom = value }
            continue
        }
        aberrations.higherOrder.append(.init(
            radialOrder: radial, angularOrder: angular,
            component: digits.count == 3 && digits[2] == "b" ? 1 : 0, coefficientAngstrom: value
        ))
    }
    return aberrations
}

struct Fixture: Decodable {
    let probeCases: [ProbeCase]
    let scanShape: [Int]
    let probeShape: [Int]
    let objectShape: [Int]
    let positions: [Float]
    let amplitudes: [Float]
    let initialObjectReal: [Float]
    let initialObjectImag: [Float]
    let initialProbeReal: [Float]
    let initialProbeImag: [Float]
    let iterations: Int
    let stepSize: Float
    let normalizationMinimum: Float
    let errors: [Float]
    let objectReal: [Float]
    let objectImag: [Float]
    let probeReal: [Float]
    let probeImag: [Float]
    let cropShape: [Int]
    let cropPhase: [Float]
    let cropAmplitude: [Float]
    let constrainedErrors: [Float]
    let constrainedObjectReal: [Float]
    let constrainedObjectImag: [Float]
    let constrainedProbeReal: [Float]
    let constrainedProbeImag: [Float]
    let centeredProbePhase: [Float]
    let centeredProbeAmplitude: [Float]
    let dmErrors: [Float]
    let dmObjectReal: [Float]
    let dmObjectImag: [Float]
    let dmProbeReal: [Float]
    let dmProbeImag: [Float]
    let dmCropPhase: [Float]
    let dmCropAmplitude: [Float]
    let positionCases: [PositionCase]
}

func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() {
        throw NSError(domain: "singleslice-ptychography-test", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: message])
    }
}

func maximumError(_ actual: [Float], _ expected: [Float]) -> Float {
    guard actual.count == expected.count else { return .infinity }
    return zip(actual, expected).reduce(0) { max($0, abs($1.0 - $1.1)) }
}

func maximumPhaseError(
    _ actual: [Float], _ expected: [Float], amplitudes: [Float]
) -> Float {
    guard actual.count == expected.count, actual.count == amplitudes.count else {
        return .infinity
    }
    return zip(zip(actual, expected), amplitudes).reduce(0) {
        guard $1.1 > 1e-4 else { return $0 }
        return max($0, abs(atan2(sin($1.0.0 - $1.0.1), cos($1.0.0 - $1.0.1))))
    }
}

@main
struct Harness {
    static func main() async throws {
        let fixture = try JSONDecoder().decode(
            Fixture.self,
            from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
        )
        let positions = stride(from: 0, to: fixture.positions.count, by: 2).map {
            PtychographyPosition(row: fixture.positions[$0],
                                 column: fixture.positions[$0 + 1])
        }
        let input = SingleslicePtychographyInput(
            scanHeight: fixture.scanShape[0], scanWidth: fixture.scanShape[1],
            detectorHeight: fixture.probeShape[0], detectorWidth: fixture.probeShape[1],
            amplitudes: fixture.amplitudes, positions: positions,
            objectSamplingRowAngstrom: 0.5, objectSamplingColumnAngstrom: 0.75,
            initialObject: PtychographyComplexArray(
                width: fixture.objectShape[1], height: fixture.objectShape[0],
                real: fixture.initialObjectReal, imaginary: fixture.initialObjectImag
            ),
            initialProbe: PtychographyComplexArray(
                width: fixture.probeShape[1], height: fixture.probeShape[0],
                real: fixture.initialProbeReal, imaginary: fixture.initialProbeImag
            )
        )
        var options = SingleslicePtychographyOptions()
        options.iterations = fixture.iterations
        options.stepSize = fixture.stepSize
        options.normalizationMinimum = fixture.normalizationMinimum
        let result = try SingleslicePtychography.reconstruct(input: input, options: options)
        let errors = maximumError(result.errorHistory, fixture.errors)
        let objectReal = maximumError(result.object.real, fixture.objectReal)
        let objectImag = maximumError(result.object.imaginary, fixture.objectImag)
        let probeReal = maximumError(result.probe.real, fixture.probeReal)
        let probeImag = maximumError(result.probe.imaginary, fixture.probeImag)
        try require(errors < 2e-5, "iteration errors differ: \(errors)")
        try require(max(objectReal, objectImag) < 3e-5,
                    "final object differs: \(objectReal), \(objectImag)")
        try require(max(probeReal, probeImag) < 3e-5,
                    "final probe differs: \(probeReal), \(probeImag)")
        let phase = result.objectPhase()
        let amplitude = result.objectAmplitude()
        try require(phase.height == fixture.cropShape[0]
                    && phase.width == fixture.cropShape[1], "object crop shape differs")
        try require(maximumError(phase.pixels, fixture.cropPhase) < 3e-5,
                    "cropped phase differs")
        try require(maximumError(amplitude.pixels, fixture.cropAmplitude) < 3e-5,
                    "cropped amplitude differs")
        try require(input.initialObject.real == fixture.initialObjectReal
                    && input.initialProbe.real == fixture.initialProbeReal,
                    "input checkpoint was mutated")
        print("PASS: every GD error, final complex object/probe, and crop")

        var constrainedOptions = options
        constrainedOptions.constrainObjectAmplitude = true
        constrainedOptions.fixProbeCenterOfMass = true
        constrainedOptions.constrainProbeAmplitude = true
        constrainedOptions.probeAmplitudeRelativeRadius = 0.42
        constrainedOptions.probeAmplitudeRelativeWidth = 0.09
        let constrained = try SingleslicePtychography.reconstruct(
            input: input, options: constrainedOptions
        )
        try require(maximumError(constrained.errorHistory, fixture.constrainedErrors) < 2e-5,
                    "constrained iteration errors differ")
        try require(maximumError(constrained.object.real, fixture.constrainedObjectReal) < 3e-5
                    && maximumError(constrained.object.imaginary, fixture.constrainedObjectImag) < 3e-5,
                    "constrained object differs")
        try require(maximumError(constrained.probe.real, fixture.constrainedProbeReal) < 3e-5
                    && maximumError(constrained.probe.imaginary, fixture.constrainedProbeImag) < 3e-5,
                    "constrained probe differs")
        try require(maximumError(constrained.probePhase().pixels, fixture.centeredProbePhase) < 3e-5,
                    "centered probe phase differs")
        try require(maximumError(constrained.probeAmplitude().pixels,
                                 fixture.centeredProbeAmplitude) < 3e-5,
                    "centered probe amplitude differs")
        try require(constrained.options == constrainedOptions,
                    "completed result did not retain exact options")
        print("PASS: object/probe constraints and centered probe diagnostics")

        var dmOptions = options
        dmOptions.method = .differenceMapAlternatingProjections
        dmOptions.projectionParameter = 0.8
        let dm = try SingleslicePtychography.reconstruct(input: input, options: dmOptions)
        try require(maximumError(dm.errorHistory, fixture.dmErrors) < 2e-5,
                    "DM/AP iteration errors differ")
        try require(maximumError(dm.object.real, fixture.dmObjectReal) < 3e-5
                    && maximumError(dm.object.imaginary, fixture.dmObjectImag) < 3e-5,
                    "DM/AP object differs")
        try require(maximumError(dm.probe.real, fixture.dmProbeReal) < 3e-5
                    && maximumError(dm.probe.imaginary, fixture.dmProbeImag) < 3e-5,
                    "DM/AP probe differs")
        let dmPhaseError = maximumPhaseError(
            dm.objectPhase().pixels, fixture.dmCropPhase,
            amplitudes: fixture.dmCropAmplitude
        )
        try require(dmPhaseError < 3e-4,
                    "DM/AP object crop differs: \(dmPhaseError)")
        try require(maximumError(dm.objectAmplitude().pixels,
                                 fixture.dmCropAmplitude) < 3e-5,
                    "DM/AP object amplitude crop differs")
        try require(dm.options.method == .differenceMapAlternatingProjections
                    && dm.options.projectionParameter == 0.8,
                    "DM/AP result options differ")
        print("PASS: retained-exit-wave DM/AP projection method")

        var limited = options
        limited.maxWorkingBytes = 1
        do {
            _ = try SingleslicePtychography.reconstruct(input: input, options: limited)
            try require(false, "memory ceiling was ignored")
        } catch SingleslicePtychography.ReconstructionError.memoryLimit {}
        var invalid = options
        invalid.iterations = 0
        do {
            _ = try SingleslicePtychography.reconstruct(input: input, options: invalid)
            try require(false, "zero iterations were accepted")
        } catch SingleslicePtychography.ReconstructionError.invalidOptions {}
        invalid = options
        invalid.probeAmplitudeRelativeWidth = 0
        do {
            _ = try SingleslicePtychography.reconstruct(input: input, options: invalid)
            try require(false, "invalid probe support width was accepted")
        } catch SingleslicePtychography.ReconstructionError.invalidOptions {}
        invalid = dmOptions
        invalid.projectionParameter = 1.1
        do {
            _ = try SingleslicePtychography.reconstruct(input: input, options: invalid)
            try require(false, "invalid DM/AP alpha was accepted")
        } catch SingleslicePtychography.ReconstructionError.invalidOptions {}
        let cancellation = AnalysisCancellationToken()
        do {
            _ = try SingleslicePtychography.reconstruct(
                input: input, options: options, cancellation: cancellation
            ) { fraction in
                if fraction > 0 { cancellation.cancel() }
            }
            try require(false, "mid-reconstruction cancellation was ignored")
        } catch SingleslicePtychography.ReconstructionError.cancelled {}
        print("PASS: immutable input, invalid options, memory, and cancellation")

        // R1 (2026-09-30) — the initial probe against py4DSTEM's `ComplexProbe(...).build()._array`, on a NON-square grid with
        // different row/column samplings, through py4DSTEM's own polar -> cartesian helper. Pins three conventions at once: the
        // defocus sign (C10 = -defocus), the C12a/C12b <-> C12/phi12 mapping, and phi = arctan2(second axis, first axis).
        do {
            var worst = 0.0
            var separations = [String: Double]()
            var plantedControlsRejected = 0
            var inFocus: [Double]?
            for probeCase in fixture.probeCases {
                guard let fft = FFT2D(nx: probeCase.gptsColumn, ny: probeCase.gptsRow) else {
                    throw NSError(domain: "singleslice-ptychography-test", code: 2,
                                  userInfo: [NSLocalizedDescriptionKey: "no FFT for the probe grid"])
                }
                let wavelength = ParallaxPreprocessor.electronWavelengthAngstrom(energyEV: probeCase.energyEV)
                let aberrations = probeAberrations(from: probeCase.cartesian)
                func built(_ aberrations: PtychographyProbeAberrations) throws -> (real: [Double], imag: [Double]) {
                    let probe = try PtychographyProbe.build(
                        detectorHeight: probeCase.gptsRow, detectorWidth: probeCase.gptsColumn,
                        rowSamplingAngstrom: probeCase.samplingRow, columnSamplingAngstrom: probeCase.samplingColumn,
                        wavelengthAngstrom: wavelength, cutoffRad: probeCase.semiangleMrad / 1_000,
                        rolloffRad: probeCase.rolloffMrad / 1_000, aberrations: aberrations, fft: fft
                    )
                    return (probe.real.map(Double.init), probe.imaginary.map(Double.init))
                }
                func distance(_ other: (real: [Double], imag: [Double])) -> Double {
                    max(zip(other.real, probeCase.real).reduce(0.0) { max($0, abs($1.0 - $1.1)) },
                        zip(other.imag, probeCase.imag).reduce(0.0) { max($0, abs($1.0 - $1.1)) })
                }
                let amplitude = zip(probeCase.real, probeCase.imag).reduce(0.0) { max($0, hypot($1.0, $1.1)) }
                let actual = try built(aberrations)
                let error = distance(actual)
                worst = max(worst, error / amplitude)
                try require(error <= 1e-5 * amplitude,
                            "probe case `\(probeCase.name)`: max |delta| = \(error) against py4DSTEM's ComplexProbe (limit \(1e-5 * amplitude))")
                if probeCase.name == "in-focus" { inFocus = probeCase.real }
                // Anti-vacuity: the aberrated cases must be far from the in-focus probe, and every planted wrong convention
                // must be far from py4DSTEM's answer - otherwise the comparison above proves nothing about them.
                if !aberrations.isZero, let inFocus {
                    let gap = zip(inFocus, probeCase.real).reduce(0.0) { max($0, abs($1.0 - $1.1)) }
                    try require(gap > 100 * 1e-5 * amplitude,
                                "probe case `\(probeCase.name)` is indistinguishable from the in-focus probe (gap \(gap))")
                }
                var controls = [(String, PtychographyProbeAberrations)]()
                var flipped = aberrations; flipped.defocusAngstrom = -flipped.defocusAngstrom
                if aberrations.defocusAngstrom != 0 { controls.append(("defocus sign", flipped)) }
                var astigmatismFlipped = aberrations
                astigmatismFlipped.c12aAngstrom = -astigmatismFlipped.c12aAngstrom
                astigmatismFlipped.c12bAngstrom = -astigmatismFlipped.c12bAngstrom
                if aberrations.c12aAngstrom != 0 || aberrations.c12bAngstrom != 0 {
                    controls.append(("astigmatism sign", astigmatismFlipped))
                    var swapped = aberrations
                    swapped.c12aAngstrom = aberrations.c12bAngstrom
                    swapped.c12bAngstrom = aberrations.c12aAngstrom
                    controls.append(("C12a and C12b swapped", swapped))
                }
                if aberrations.higherOrder.contains(where: { $0.angularOrder > 0 }) {
                    var cosineSine = aberrations
                    cosineSine.higherOrder = aberrations.higherOrder.map {
                        var term = $0
                        if term.angularOrder > 0 { term.component = 1 - term.component }
                        return term
                    }
                    controls.append(("cosine and sine swapped", cosineSine))
                    var higherFlipped = aberrations
                    higherFlipped.higherOrder = aberrations.higherOrder.map {
                        var term = $0; term.coefficientAngstrom = -term.coefficientAngstrom; return term
                    }
                    controls.append(("higher-order sign", higherFlipped))
                }
                for (name, control) in controls {
                    let separation = distance(try built(control))
                    separations[name] = min(separations[name] ?? .infinity, separation / amplitude)
                    try require(separation > 100 * 1e-5 * amplitude,
                                "probe case `\(probeCase.name)`: the planted wrong convention `\(name)` is within \(separation) of py4DSTEM's probe - the fixture cannot tell it from the right one")
                    plantedControlsRejected += 1
                }
            }
            try require(plantedControlsRejected >= 14,
                        "only \(plantedControlsRejected) planted wrong conventions were checked - the probe controls have gone vacuous")
            let summary = separations.sorted { $0.key < $1.key }
                .map { "\($0.key) >= \(String(format: "%.2g", $0.value))" }.joined(separator: ", ")
            print("PASS: the initial probe equals py4DSTEM's ComplexProbe over \(fixture.probeCases.count) cases (worst |delta| / max|probe| = \(String(format: "%.2g", worst))); \(plantedControlsRejected) planted wrong conventions each rejected (relative separations: \(summary))")
        }

        // D002 — the preparer's scan positions against py4DSTEM's
        // `_calculate_scan_positions_in_pixels`. Before the fix the preparer
        // built an axis-aligned raster and never read `rotationRad` or
        // `transpose`, so a 0 deg and a 30 deg calibration were bit-identical.
        //
        // Every case is a crop of the demo cube. The 12x12x64x64 full extent is
        // SQUARE with equal row/column object sampling, which makes transpose a
        // no-op by geometry and hides a wrong convention — it is here only as a
        // control, and the cases that decide anything are non-square.
        let source = DemoFourDDataSource()
        let fullDescriptor = try await source.discoverPrimaryDataset()
        var controlsThatBit = 0
        for (index, testCase) in fixture.positionCases.enumerated() {
            let specification = LoadSpecification(
                scanCrop: AxisCrop(yOffset: 0, xOffset: 0,
                                   height: testCase.ry, width: testCase.rx),
                detectorCrop: AxisCrop(yOffset: 0, xOffset: 0,
                                       height: testCase.qy, width: testCase.qx)
            )
            let view = try LoadView(source: fullDescriptor, specification: specification)
            try require(view.descriptor.ry == testCase.ry && view.descriptor.rx == testCase.rx
                        && view.descriptor.qy == testCase.qy && view.descriptor.qx == testCase.qx,
                        "position case \(index): the crop is \(view.descriptor.ry)x\(view.descriptor.rx)x\(view.descriptor.qy)x\(view.descriptor.qx), not the case's shape")
            let wavelength = ParallaxPreprocessor.electronWavelengthAngstrom(energyEV: 80_000)
            let calibration = ParallaxPhysicalCalibration(
                scanSamplingAngstrom: testCase.scanSamplingAngstrom,
                reciprocalSamplingInvAngstrom: testCase.qSamplingInvAngstrom,
                energyEV: 80_000, wavelengthAngstrom: wavelength,
                originQX: 0, originQY: 0,
                rotationRad: testCase.rotationDeg * .pi / 180,
                transpose: testCase.transpose
            )
            let prepared = try await PtychographyPreparer.prepare(
                source: source, view: view, calibration: calibration, probeRadiusPixels: 8
            )
            var actual = [Double]()
            actual.reserveCapacity(prepared.positions.count * 2)
            for position in prepared.positions {
                actual.append(Double(position.row))
                actual.append(Double(position.column))
            }
            try require(actual.count == testCase.expected.count,
                        "position case \(index): \(actual.count) values, expected \(testCase.expected.count)")
            func maximumDifference(_ other: [Double]) -> Double {
                zip(actual, other).reduce(0.0) { max($0, abs($1.0 - $1.1)) }
            }
            // Float positions built from Double arithmetic: 1e-3 object pixels
            // is far below the smallest control here (1.73 px) and far above
            // Float rounding on values of order 100.
            let tolerance = 1e-3
            let delta = maximumDifference(testCase.expected)
            try require(delta < tolerance,
                        "position case \(index) (rot \(testCase.rotationDeg) deg, transpose \(testCase.transpose), q \(testCase.qy)x\(testCase.qx)): max |delta| = \(delta) object px against py4DSTEM's convention")
            // Anti-vacuity: every control that is itself distinguishable from
            // the reference must be distinguishable from the real code too.
            for (name, control) in testCase.controls.sorted(by: { $0.key < $1.key }) {
                let separation = zip(testCase.expected, control)
                    .reduce(0.0) { max($0, abs($1.0 - $1.1)) }
                guard separation > tolerance else { continue }
                controlsThatBit += 1
                try require(maximumDifference(control) > tolerance,
                            "position case \(index): the preparer matches the WRONG convention `\(name)`")
            }
        }
        // A reference.py that emitted controls identical to the reference would
        // make every check above vacuous.
        try require(controlsThatBit >= 12,
                    "only \(controlsThatBit) negative controls were distinguishable — the position controls have gone vacuous")
        print("PASS: scan positions match py4DSTEM's rotate/transpose/clip convention over \(fixture.positionCases.count) cases; \(controlsThatBit) planted wrong conventions each rejected")

        // Gate B, 2026-09-11. `calibration.originQX`/`originQY` shift the
        // detector resample (PtychographyPreparation.swift:70, :76) and NOTHING
        // asserted them: the only thing this harness read from `prepare` was
        // `positions`, which the origin does not touch, so deleting both fields
        // left the whole gate green. A position case cannot close that — the
        // origin moves AMPLITUDES — so this is an analytic invariant instead.
        // At an INTEGER shift the bilinear resample reduces exactly to a
        // circular shift (`rowFraction`/`columnFraction` are 0), so the shifted
        // amplitudes must equal the unshifted ones rolled by that many rows
        // (originQX) or columns (originQY). Ground truth is the arithmetic, not
        // the code's own output.
        //
        // It also pins, in an executable place, the naming trap in that file:
        // `originQX` is added to the ROW and `originQY` to the COLUMN, which is
        // correct — `ParallaxPreprocessing.swift:98-99` sets
        // `originQX: Double(apertureCenterY)` — but it is the opposite sense to
        // the `cx` = COLUMN convention documented a few lines below it. Anyone
        // who "corrects" the naming must fail here.
        do {
            let shiftRows = 2
            let shiftColumns = 3
            let specification = LoadSpecification(
                scanCrop: AxisCrop(yOffset: 0, xOffset: 0, height: 3, width: 4),
                detectorCrop: AxisCrop(yOffset: 0, xOffset: 0, height: 16, width: 24)
            )
            let view = try LoadView(source: fullDescriptor, specification: specification)
            let descriptor = view.descriptor
            let wavelength = ParallaxPreprocessor.electronWavelengthAngstrom(energyEV: 80_000)
            func amplitudes(originQX: Double, originQY: Double) async throws -> [Float] {
                let calibration = ParallaxPhysicalCalibration(
                    scanSamplingAngstrom: 1.0,
                    reciprocalSamplingInvAngstrom: 0.05,
                    energyEV: 80_000, wavelengthAngstrom: wavelength,
                    originQX: originQX, originQY: originQY,
                    rotationRad: 0, transpose: false
                )
                return try await PtychographyPreparer.prepare(
                    source: source, view: view, calibration: calibration,
                    probeRadiusPixels: 8
                ).amplitudes
            }
            let base = try await amplitudes(originQX: 0, originQY: 0)
            let shifted = try await amplitudes(originQX: Double(shiftRows),
                                               originQY: Double(shiftColumns))
            let detectorCount = descriptor.qy * descriptor.qx
            try require(base.count == detectorCount * descriptor.ry * descriptor.rx
                        && shifted.count == base.count,
                        "origin-shift invariant: unexpected amplitude count")
            var maximumDelta: Float = 0
            var maximumSeparation: Float = 0
            for pattern in 0..<(descriptor.ry * descriptor.rx) {
                for row in 0..<descriptor.qy {
                    for column in 0..<descriptor.qx {
                        let sourceRow = (row + shiftRows) % descriptor.qy
                        let sourceColumn = (column + shiftColumns) % descriptor.qx
                        let here = pattern * detectorCount + row * descriptor.qx + column
                        let there = pattern * detectorCount
                            + sourceRow * descriptor.qx + sourceColumn
                        maximumDelta = max(maximumDelta, abs(shifted[here] - base[there]))
                        maximumSeparation = max(maximumSeparation,
                                                abs(base[there] - base[here]))
                    }
                }
            }
            // Anti-vacuity: on patterns flat along these axes the roll would be
            // a no-op and the assertion below would pass on anything at all.
            try require(maximumSeparation > 1e-3,
                        "the origin-shift invariant is VACUOUS: rolling by (\(shiftRows), \(shiftColumns)) moves the amplitudes by only \(maximumSeparation)")
            try require(maximumDelta < 1e-5,
                        "an integer origin shift is not a circular shift of the resampled amplitudes: max |delta| = \(maximumDelta) against a separation of \(maximumSeparation) — originQX must roll ROWS and originQY COLUMNS")
            print("PASS: an integer origin shift equals a circular shift of the resampled amplitudes (rows by \(shiftRows), columns by \(shiftColumns); separation \(maximumSeparation))")
        }
        // R1 (2026-09-30) — through the preparer. (1) No aberrations reproduce, bit for bit, the probe this code built
        // before R1 (the hashes were captured from git 02174c9c's PtychographyPreparation.swift on these two crops). (2) With
        // aberrations the prepared probe is the builder's probe up to the mean-intensity scale, i.e. `prepare` really hands them
        // on. (3) Non-finite or malformed aberrations are refused.
        do {
            struct Golden {
                let ry: Int, rx: Int, qy: Int, qx: Int
                let q: Double, radius: Float, originQX: Double, originQY: Double
                let real: UInt64, imaginary: UInt64
            }
            let goldens = [
                Golden(ry: 3, rx: 4, qy: 16, qx: 24, q: 0.05, radius: 8, originQX: 0, originQY: 0,
                       real: 0xa2f70f0ec0ff6fbd, imaginary: 0x3fc1df107866e72b),
                Golden(ry: 2, rx: 3, qy: 24, qx: 32, q: 0.0213, radius: 7.5, originQX: 1.25, originQY: 0.5,
                       real: 0x1c82119693445fab, imaginary: 0x2051128dad3f47bb),
            ]
            let wavelength = ParallaxPreprocessor.electronWavelengthAngstrom(energyEV: 80_000)
            for (index, golden) in goldens.enumerated() {
                let specification = LoadSpecification(
                    scanCrop: AxisCrop(yOffset: 0, xOffset: 0, height: golden.ry, width: golden.rx),
                    detectorCrop: AxisCrop(yOffset: 0, xOffset: 0, height: golden.qy, width: golden.qx)
                )
                let view = try LoadView(source: fullDescriptor, specification: specification)
                let calibration = ParallaxPhysicalCalibration(
                    scanSamplingAngstrom: 1.0, reciprocalSamplingInvAngstrom: golden.q,
                    energyEV: 80_000, wavelengthAngstrom: wavelength,
                    originQX: golden.originQX, originQY: golden.originQY, rotationRad: 0, transpose: false
                )
                let plain = try await PtychographyPreparer.prepare(
                    source: source, view: view, calibration: calibration, probeRadiusPixels: golden.radius
                )
                try require(bitHash(plain.initialProbe.real) == golden.real
                            && bitHash(plain.initialProbe.imaginary) == golden.imaginary,
                            "golden crop \(index): the aberration-free probe is no longer bit-identical to the pre-R1 probe (real \(String(bitHash(plain.initialProbe.real), radix: 16)), imaginary \(String(bitHash(plain.initialProbe.imaginary), radix: 16)))")
                let explicitZero = try await PtychographyPreparer.prepare(
                    source: source, view: view, calibration: calibration, probeRadiusPixels: golden.radius,
                    aberrations: PtychographyProbeAberrations()
                )
                try require(explicitZero.initialProbe.real == plain.initialProbe.real
                            && explicitZero.initialProbe.imaginary == plain.initialProbe.imaginary,
                            "golden crop \(index): explicit zero aberrations differ from the default")

                let aberrated = PtychographyProbeAberrations(
                    defocusAngstrom: -400, c12aAngstrom: 35, c12bAngstrom: -20,
                    higherOrder: [.init(radialOrder: 2, angularOrder: 1, component: 0, coefficientAngstrom: 1500)]
                )
                let prepared = try await PtychographyPreparer.prepare(
                    source: source, view: view, calibration: calibration, probeRadiusPixels: golden.radius,
                    aberrations: aberrated
                )
                guard let fft = FFT2D(nx: golden.qx, ny: golden.qy) else { fatalError("no FFT") }
                let expected = try PtychographyProbe.build(
                    detectorHeight: golden.qy, detectorWidth: golden.qx,
                    rowSamplingAngstrom: 1 / (golden.q * Double(golden.qy)),
                    columnSamplingAngstrom: 1 / (golden.q * Double(golden.qx)),
                    wavelengthAngstrom: wavelength, cutoffRad: Double(golden.radius) * golden.q * wavelength,
                    rolloffRad: 0.002, aberrations: aberrated, fft: fft
                )
                let preparedNorm = sqrt(zip(prepared.initialProbe.real, prepared.initialProbe.imaginary)
                    .reduce(0.0) { $0 + Double($1.0 * $1.0 + $1.1 * $1.1) })
                var deviation = 0.0
                var peak = 0.0
                for pixel in 0..<expected.real.count {
                    deviation = max(deviation,
                                    abs(Double(prepared.initialProbe.real[pixel]) / preparedNorm - Double(expected.real[pixel])),
                                    abs(Double(prepared.initialProbe.imaginary[pixel]) / preparedNorm - Double(expected.imaginary[pixel])))
                    peak = max(peak, hypot(Double(expected.real[pixel]), Double(expected.imaginary[pixel])))
                }
                try require(deviation < 1e-5 * peak,
                            "crop \(index): the prepared probe is not the aberrated probe (max |delta| \(deviation), peak \(peak))")
                let gap = zip(prepared.initialProbe.imaginary, plain.initialProbe.imaginary)
                    .reduce(0.0) { max($0, Double(abs($1.0 - $1.1))) }
                try require(gap > 0, "crop \(index): the aberrations changed nothing in the prepared probe")
                // The input records what it was built with, and the reconstruction carries the record through (the app publishes
                // the defocus from the RESULT, so it cannot name a probe the run did not start from).
                try require(prepared.probeAberrations == aberrated && plain.probeAberrations == PtychographyProbeAberrations(),
                            "crop \(index): `prepare` did not record the aberrations it built the probe with")
                var oneIteration = SingleslicePtychographyOptions()
                oneIteration.iterations = 1
                let carried = try SingleslicePtychography.reconstruct(input: prepared, options: oneIteration)
                try require(carried.probeAberrations == aberrated,
                            "crop \(index): the reconstruction did not carry the input's probe aberrations")
            }
            let specification = LoadSpecification(
                scanCrop: AxisCrop(yOffset: 0, xOffset: 0, height: 2, width: 2),
                detectorCrop: AxisCrop(yOffset: 0, xOffset: 0, height: 16, width: 16)
            )
            let view = try LoadView(source: fullDescriptor, specification: specification)
            let calibration = ParallaxPhysicalCalibration(
                scanSamplingAngstrom: 1.0, reciprocalSamplingInvAngstrom: 0.05,
                energyEV: 80_000, wavelengthAngstrom: wavelength,
                originQX: 0, originQY: 0, rotationRad: 0, transpose: false
            )
            let malformed: [PtychographyProbeAberrations] = [
                PtychographyProbeAberrations(defocusAngstrom: .nan),
                PtychographyProbeAberrations(c12aAngstrom: .infinity),
                PtychographyProbeAberrations(higherOrder: [.init(radialOrder: 0, angularOrder: 0, component: 0, coefficientAngstrom: 1)]),
                PtychographyProbeAberrations(higherOrder: [.init(radialOrder: 2, angularOrder: 0, component: 1, coefficientAngstrom: 1)]),
                PtychographyProbeAberrations(higherOrder: [.init(radialOrder: 2, angularOrder: 1, component: 0, coefficientAngstrom: .nan)]),
            ]
            for aberrations in malformed {
                do {
                    _ = try await PtychographyPreparer.prepare(
                        source: source, view: view, calibration: calibration, probeRadiusPixels: 4,
                        aberrations: aberrations
                    )
                    try require(false, "malformed aberrations were accepted: \(aberrations)")
                } catch SingleslicePtychography.ReconstructionError.invalidInput {}
            }
            print("PASS: zero aberrations are bit-identical to the pre-R1 probe on \(goldens.count) crops; aberrations reach the prepared probe; \(malformed.count) malformed sets refused")
        }
        print("singleslice-ptychography-test: all passed")
    }
}

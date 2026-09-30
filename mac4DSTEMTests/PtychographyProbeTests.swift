import AppKit
import SwiftUI
import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

/// Lane R1 (2026-09-30): the ptychography probe takes a defocus and the fitted aberrations.
///
/// The fixture that pins the probe to py4DSTEM's `ComplexProbe` (planted wrong conventions included) is
/// `tools/singleslice-ptychography-test` - it needs py4DSTEM, so it lives in the scientific gate. What this class pins without
/// Python: the conventions as plain arithmetic on the Fourier side of the probe, the bit-for-bit promise for "no aberrations",
/// the seeding rule (defocus is MINUS the parallax fit's C1), and that the published product names the defocus it started from.
/// Every test names the mutation it catches.
@MainActor
final class PtychographyProbeTests: XCTestCase {

    // MARK: - The probe's conventions, as arithmetic

    private let energyEV = 80_000.0
    private let rows = 32, columns = 24
    private let rowSampling = 0.4, columnSampling = 0.55
    private let semiangleRad = 0.028, rolloffRad = 0.002

    private var wavelength: Double { ParallaxPreprocessor.electronWavelengthAngstrom(energyEV: energyEV) }

    /// The probe's Fourier transform (aperture * exp(-i chi), up to one overall complex scale), by `PtychographyProbe.build`
    /// followed by a forward FFT.
    private func spectrum(_ aberrations: PtychographyProbeAberrations) throws -> (real: [Float], imaginary: [Float]) {
        let fft = try XCTUnwrap(FFT2D(nx: columns, ny: rows))
        var probe = try PtychographyProbe.build(
            detectorHeight: rows, detectorWidth: columns,
            rowSamplingAngstrom: rowSampling, columnSamplingAngstrom: columnSampling,
            wavelengthAngstrom: wavelength, cutoffRad: semiangleRad, rolloffRad: rolloffRad,
            aberrations: aberrations, fft: fft
        )
        fft.transform(re: &probe.real, im: &probe.imaginary, forward: true)
        return probe
    }

    /// Phase of the spectrum at (row, column) relative to its DC pixel (the overall scale), and the scattering angle there.
    private func relativePhase(of s: (real: [Float], imaginary: [Float]), row: Int, column: Int) -> (phase: Double, alpha: Double) {
        let here = row * columns + column
        let phase = atan2(Double(s.imaginary[here]), Double(s.real[here]))
            - atan2(Double(s.imaginary[0]), Double(s.real[0]))
        let rowFrequency = Double(row <= (rows - 1) / 2 ? row : row - rows) / (Double(rows) * rowSampling)
        let columnFrequency = Double(column <= (columns - 1) / 2 ? column : column - columns)
            / (Double(columns) * columnSampling)
        return (atan2(sin(phase), cos(phase)), hypot(rowFrequency, columnFrequency) * wavelength)
    }

    /// py4DSTEM: `defocus` -> C10 = -defocus, chi = (2 pi / lambda) * alpha^2 / 2 * C10, the probe's spectrum
    /// aperture * exp(-i chi). So the spectrum's phase is +pi alpha^2 defocus / lambda: POSITIVE for positive defocus.
    /// Mutation it catches: `-defocusAngstrom` -> `defocusAngstrom` in `PtychographyProbeAberrations.chi`; `-aperture * sin` ->
    /// `aperture * sin` (exp(+i chi)); `2 * .pi` dropped.
    func testPositiveDefocusGivesAPositiveSpectrumPhase() throws {
        let defocus = 60.0
        let s = try spectrum(PtychographyProbeAberrations(defocusAngstrom: defocus))
        var checked = 0
        for (row, column) in [(3, 0), (0, 4), (2, 3), (30, 1), (1, 21)] {
            let (phase, alpha) = relativePhase(of: s, row: row, column: column)
            guard alpha > 0.002, alpha < semiangleRad - 2 * rolloffRad else { continue }
            XCTAssertEqual(phase, .pi * alpha * alpha * defocus / wavelength, accuracy: 2e-3, "pixel (\(row), \(column))")
            checked += 1
        }
        XCTAssertGreaterThanOrEqual(checked, 4, "the test has to look at pixels inside the aperture")
    }

    /// chi's astigmatism term is (pi / lambda) alpha^2 (C12a cos 2 theta + C12b sin 2 theta) with theta = atan2(column, row)
    /// frequency (py4DSTEM's phi = arctan2(second axis, first axis)); the spectrum phase is minus that. On the ROW axis
    /// theta = 0 (cos 2 theta = +1), on the COLUMN axis theta = 90 deg (cos 2 theta = -1), on the diagonal sin 2 theta = +1.
    /// Mutation it catches: cos/sin swapped; `atan2(frequencyRow, frequencyColumn)`; the sign of the astigmatism term.
    func testAstigmatismFollowsThePy4DSTEMAxes() throws {
        let c12a = 40.0, c12b = 25.0
        let s = try spectrum(PtychographyProbeAberrations(c12aAngstrom: c12a))
        let row = relativePhase(of: s, row: 3, column: 0)        // theta = 0
        let column = relativePhase(of: s, row: 0, column: 4)     // theta = 90 deg
        XCTAssertEqual(row.phase, -.pi * row.alpha * row.alpha * c12a / wavelength, accuracy: 2e-3)
        XCTAssertEqual(column.phase, .pi * column.alpha * column.alpha * c12a / wavelength, accuracy: 2e-3)

        // A pixel at 45 degrees in ANGLE: equal row and column frequencies.
        let rowFrequency = 2.0 / (Double(rows) * rowSampling), columnFrequency = 2.0 / (Double(columns) * columnSampling)
        let diagonalRow = 2, diagonalColumn = 2
        // theta there is atan2(columnFrequency, rowFrequency), NOT 45 degrees on this non-square grid: use the real angle.
        let theta = atan2(columnFrequency, rowFrequency)
        let t = try spectrum(PtychographyProbeAberrations(c12bAngstrom: c12b))
        let diagonal = relativePhase(of: t, row: diagonalRow, column: diagonalColumn)
        XCTAssertEqual(diagonal.phase, -.pi * diagonal.alpha * diagonal.alpha * c12b * sin(2 * theta) / wavelength, accuracy: 2e-3)
        XCTAssertGreaterThan(abs(sin(2 * theta)), 0.5, "the pixel must sit where sin 2 theta is far from zero")
    }

    /// A higher-order term is coefficient * alpha^(m+1) / (m+1) * cos(n theta) (cosine) or sin(n theta) (sine), the basis
    /// `ParallaxAberrationCorrector` uses for the same fit. Coma C21 (m = 2, n = 1) on the ROW axis: cos = 1, sin = 0.
    /// Mutation it catches: the 1/(m+1); cos <-> sin; the exponent.
    func testComaUsesTheParallaxBasis() throws {
        let coefficient = 4_000.0
        let cosine = try spectrum(PtychographyProbeAberrations(
            higherOrder: [.init(radialOrder: 2, angularOrder: 1, component: 0, coefficientAngstrom: coefficient)]))
        let sine = try spectrum(PtychographyProbeAberrations(
            higherOrder: [.init(radialOrder: 2, angularOrder: 1, component: 1, coefficientAngstrom: coefficient)]))
        let onRow = relativePhase(of: cosine, row: 3, column: 0)
        XCTAssertEqual(onRow.phase, -2 * .pi / wavelength * coefficient * pow(onRow.alpha, 3) / 3, accuracy: 3e-3)
        let sineOnRow = relativePhase(of: sine, row: 3, column: 0)
        XCTAssertEqual(sineOnRow.phase, 0, accuracy: 3e-3, "sin(theta) vanishes on the row axis")
        let onColumn = relativePhase(of: sine, row: 0, column: 4)
        XCTAssertEqual(onColumn.phase, -2 * .pi / wavelength * coefficient * pow(onColumn.alpha, 3) / 3, accuracy: 3e-3)
    }

    // MARK: - No aberrations: the probe this code built before R1, bit for bit

    private func bitHash(_ values: [Float]) -> UInt64 {
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

    /// The hashes were captured from git 02174c9c's `PtychographyPreparation.swift` (the code BEFORE this lane) on these two
    /// demo-cube crops (`$SP/R1/golden/head-golden.log`, 2026-09-30). The same two hashes are pinned in the harness.
    /// Mutation it catches: any change to the aberration-free aperture, rolloff or normalisation.
    func testNoAberrationsReproduceThePreR1ProbeBitForBit() async throws {
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
        let source = DemoFourDDataSource()
        let full = try await source.discoverPrimaryDataset()
        for golden in goldens {
            let specification = LoadSpecification(
                scanCrop: AxisCrop(yOffset: 0, xOffset: 0, height: golden.ry, width: golden.rx),
                detectorCrop: AxisCrop(yOffset: 0, xOffset: 0, height: golden.qy, width: golden.qx)
            )
            let view = try LoadView(source: full, specification: specification)
            let calibration = ParallaxPhysicalCalibration(
                scanSamplingAngstrom: 1.0, reciprocalSamplingInvAngstrom: golden.q,
                energyEV: 80_000, wavelengthAngstrom: wavelength,
                originQX: golden.originQX, originQY: golden.originQY, rotationRad: 0, transpose: false
            )
            let input = try await PtychographyPreparer.prepare(
                source: source, view: view, calibration: calibration, probeRadiusPixels: golden.radius
            )
            XCTAssertEqual(bitHash(input.initialProbe.real), golden.real, "crop \(golden.qy)x\(golden.qx): real part")
            XCTAssertEqual(bitHash(input.initialProbe.imaginary), golden.imaginary, "crop \(golden.qy)x\(golden.qx): imaginary part")
        }
    }

    // MARK: - Seeding from the parallax fit

    private func lowOrderFit(c1: Double, c12a: Double, c12b: Double, rotationRad: Double = -0.0017) -> ParallaxAberrationFitResult {
        ParallaxAberrationFitResult(
            measuredShifts: [], fittedShifts: [], rotationRad: rotationRad,
            c1Angstrom: c1, c12aAngstrom: c12a, c12bAngstrom: c12b,
            rmsResidualAngstrom: 0, forceTranspose: false, forcedRotationAngleDegrees: nil
        )
    }

    private func higherOrderFit(low: ParallaxAberrationFitResult) -> ParallaxHigherOrderAberrationFitResult {
        let terms = [
            ParallaxAberrationTerm(radialOrder: 1, angularOrder: 0, component: 0),
            ParallaxAberrationTerm(radialOrder: 1, angularOrder: 2, component: 0),
            ParallaxAberrationTerm(radialOrder: 1, angularOrder: 2, component: 1),
            ParallaxAberrationTerm(radialOrder: 2, angularOrder: 1, component: 0),
            ParallaxAberrationTerm(radialOrder: 2, angularOrder: 1, component: 1),
            ParallaxAberrationTerm(radialOrder: 2, angularOrder: 3, component: 0),
            ParallaxAberrationTerm(radialOrder: 2, angularOrder: 3, component: 1),
        ]
        return ParallaxHigherOrderAberrationFitResult(
            lowOrder: low, terms: terms,
            coefficientsAngstrom: [670, 11, 13, 300, -200, 50, 60],
            fittedShifts: [], rmsResidualAngstrom: 0, fitMethod: .recursive
        )
    }

    /// The defocus a parallax fit implies is MINUS its C1: py4DSTEM's forward model stores C10 = -defocus (utils.py:159-160) and
    /// E1 (2026-09-30) has its Parallax return C1 = -508.67 for a probe built at `defocus = +500` (the gold-on-carbon tutorial
    /// agrees; the MoS2 notebooks pass +C1 at about 50 A). The astigmatism keeps the fit's signs (E1: C12a/C12b came back with
    /// ComplexProbe's own signs, transpose = false).
    /// Mutation it catches: `-lowOrder.c1Angstrom` -> `lowOrder.c1Angstrom`; negating the astigmatism.
    func testUseParallaxFitTakesMinusC1AndTheFitsAstigmatism() {
        let settings = PtychographySettings()
        let taken = settings.useParallaxFit(
            lowOrder: lowOrderFit(c1: 663.6, c12a: 10.1, c12b: 12.8), higherOrder: nil
        )
        XCTAssertEqual(taken, 0)
        XCTAssertEqual(settings.defocusAngstrom, -663.6)
        XCTAssertEqual(settings.c12aAngstrom, 10.1)
        XCTAssertEqual(settings.c12bAngstrom, 12.8)
        XCTAssertEqual(settings.probeAberrations, PtychographyProbeAberrations(
            defocusAngstrom: -663.6, c12aAngstrom: 10.1, c12bAngstrom: 12.8))
    }

    /// The toggle off ignores the higher-order fit; on, it takes ALL of one fit (the recursive fit's refined defocus and
    /// astigmatism, not the low-order ones) and keeps the terms for the run; pressing again with it off drops them.
    /// Mutation it catches: taking the terms with the toggle off; mixing the low-order C1 with the joint fit's terms; keeping
    /// stale terms.
    func testHigherOrderTermsFollowTheToggle() {
        let low = lowOrderFit(c1: 663.6, c12a: 10.1, c12b: 12.8)
        let high = higherOrderFit(low: low)
        let settings = PtychographySettings()

        XCTAssertEqual(settings.useParallaxFit(lowOrder: low, higherOrder: high), 0, "toggle off")
        XCTAssertEqual(settings.defocusAngstrom, -663.6)
        XCTAssertTrue(settings.probeAberrations.higherOrder.isEmpty)

        settings.includeHigherOrderFit = true
        XCTAssertEqual(settings.useParallaxFit(lowOrder: low, higherOrder: high), 4, "toggle on: C21 and C23, both components")
        XCTAssertEqual(settings.defocusAngstrom, -670, "the joint fit's own (1,0,0)")
        XCTAssertEqual(settings.c12aAngstrom, 11)
        XCTAssertEqual(settings.c12bAngstrom, 13)
        XCTAssertEqual(settings.probeAberrations.higherOrder.map(\.coefficientAngstrom), [300, -200, 50, 60])
        XCTAssertEqual(settings.probeAberrations.higherOrder.map(\.radialOrder), [2, 2, 2, 2])
        XCTAssertEqual(settings.probeAberrations.higherOrder.map(\.angularOrder), [1, 1, 3, 3])
        XCTAssertEqual(settings.probeAberrations.higherOrder.map(\.component), [0, 1, 0, 1])

        settings.includeHigherOrderFit = false
        XCTAssertEqual(settings.useParallaxFit(lowOrder: low, higherOrder: high), 0)
        XCTAssertTrue(settings.probeAberrations.higherOrder.isEmpty, "a copy with the toggle off leaves no terms behind")

        settings.includeHigherOrderFit = true
        XCTAssertEqual(settings.useParallaxFit(lowOrder: low, higherOrder: nil), 0, "no higher-order fit: nothing to take")
    }

    /// The action fills the fields from the stored fit, names what it took (and both rotations, for the reader to judge), and
    /// does nothing without a fit.
    /// Mutation it catches: writing the status without the defocus; acting without a fit.
    func testTheActionFillsTheFieldsFromTheStoredFit() {
        let state = AppState()
        state.usePtychographyProbeFromParallaxFit()
        XCTAssertEqual(state.ptychography.defocusAngstrom, 0, "no fit: untouched")

        state.phaseContrast.parallaxAberrationFit = lowOrderFit(c1: 663.6, c12a: 10.1, c12b: 12.8, rotationRad: -0.0017)
        state.calibrationSession.calibration.rotationRad = 0
        state.usePtychographyProbeFromParallaxFit()
        XCTAssertEqual(state.ptychography.defocusAngstrom, -663.6)
        XCTAssertEqual(state.ptychography.c12aAngstrom, 10.1)
        XCTAssertTrue(state.statusText.contains("defocus -663.6 Å"), state.statusText)
        XCTAssertTrue(state.statusText.contains("fit rotation -0.10°"), state.statusText)
        XCTAssertTrue(state.statusText.contains("calibrated rotation 0.00°"), state.statusText)
    }

    // MARK: - The section fits the inspector

    private func hostedSize<V: View>(_ view: V, width: CGFloat, state: AppState) -> CGSize {
        let host = NSHostingController(rootView: view.environment(state).environment(state.preferences))
        return host.sizeThatFits(in: CGSize(width: width, height: 10_000))
    }

    /// The new rows (Defocus, Use Parallax Fit, and under Advanced the two astigmatism rows and the higher-order toggle) must
    /// fit the narrowest inspector column - a fixed-size label and a 72-pt field set the pane's minimum
    /// (`InspectorWidthBudgetTests`). Hosted with Advanced open, because the room-wide sweep hosts it closed. The measured
    /// heights are attached so the row cost (rows x pt) is on record.
    /// Mutation it catches: "Astigmatism C12a" -> "Astigmatism C12a (two-fold, cosine)".
    func testPtychographySectionFitsTheNarrowestColumnWithAdvancedOpen() {
        let state = AppState()
        let budget = LayoutPolicy.inspectorWidth.min - 2 * 16
        let closed = hostedSize(SingleslicePtychographySection(), width: 1, state: state)
        let open = hostedSize(SingleslicePtychographySection(advancedExpanded: true), width: 1, state: state)
        XCTAssertGreaterThan(open.width, 10, "the probe measured nothing")
        XCTAssertLessThanOrEqual(closed.width, budget, "Advanced closed needs \(closed.width) pt")
        XCTAssertLessThanOrEqual(open.width, budget, "Advanced open needs \(open.width) pt against \(budget)")

        let ideal = LayoutPolicy.inspectorWidth.ideal - 2 * 16
        let closedHeight = hostedSize(SingleslicePtychographySection(), width: ideal, state: state).height
        let openHeight = hostedSize(SingleslicePtychographySection(advancedExpanded: true), width: ideal, state: state).height
        let single = hostedSize(
            InspectorRow("Astigmatism C12a") { NumericField("x", value: .constant(0.0), format: .number, unit: "Å") },
            width: ideal, state: state)
        let action = hostedSize(
            InspectorActionRow { InspectorAdaptiveButton("Use Parallax Fit", systemImage: "arrow.down.circle") {} },
            width: ideal, state: state)
        let toggle = hostedSize(
            InspectorRow("Take higher-order terms") { Toggle("x", isOn: .constant(false)).labelsHidden() },
            width: ideal, state: state)
        let attachment = XCTAttachment(string: "section height at \(ideal) pt: Advanced closed \(closedHeight), open \(openHeight); numeric row \(single.height) pt, action row \(action.height) pt, toggle row \(toggle.height) pt; row spacing \(LayoutPolicy.inspectorRowSpacing) pt; minimum width closed \(closed.width), open \(open.width)")
        attachment.lifetime = .keepAlways
        add(attachment)
        print("ROW-COST section height at \(ideal) pt: closed \(closedHeight), open \(openHeight); numeric row \(single.height), action row \(action.height), toggle row \(toggle.height); row spacing \(LayoutPolicy.inspectorRowSpacing); min width closed \(closed.width), open \(open.width)")
    }

    // MARK: - The product says what it was made with

    private func result(probe aberrations: PtychographyProbeAberrations = PtychographyProbeAberrations()) -> SingleslicePtychographyResult {
        let array = PtychographyComplexArray(width: 2, height: 2, real: [1, 1, 1, 1], imaginary: [0, 0, 0, 0])
        return SingleslicePtychographyResult(
            object: array, probe: array, positions: [], errorHistory: [0.5, 0.25],
            objectSamplingRowAngstrom: 0.25, objectSamplingColumnAngstrom: 0.30,
            options: SingleslicePtychographyOptions(), probeAberrations: aberrations)
    }

    /// The published product's name carries the defocus the probe started from, read from the RESULT, and the record goes with
    /// it (there is no second copy).
    /// Mutation it catches: the suffix dropped; the name read from the settings instead of the result; a separately stored probe
    /// record surviving its result.
    func testThePublishedProductNamesTheDefocusAndItGoesWithTheResult() throws {
        let state = AppState()
        state.changeMode(.singleslicePtychography)
        state.ptychography.defocusAngstrom = 123   // the settings must NOT leak into the name of a result made without them
        state.phaseContrast.singleslicePtychography = result()
        state.showParallaxProduct(.iterativePhase)
        XCTAssertEqual(state.resultPresentation.product?.displayName, "Ptychography object phase · defocus 0 Å",
                       "the name is the result's record, not the settings'")

        state.phaseContrast.singleslicePtychography = result(probe: PtychographyProbeAberrations(defocusAngstrom: -663.6))
        state.showParallaxProduct(.iterativePhase)
        XCTAssertEqual(state.resultPresentation.product?.displayName, "Ptychography object phase · defocus -663.6 Å")
        state.showParallaxProduct(.iterativeProbeAmplitude)
        XCTAssertEqual(state.resultPresentation.product?.displayName, "Ptychography probe amplitude · defocus -663.6 Å")

        state.phaseContrast.singleslicePtychography = nil
        XCTAssertNil(state.phaseContrast.singleslicePtychographyProbe, "the probe record goes with its result")
    }

    /// THE CALL SITE (Gate B, 2026-09-30): the app's run must hand its fields to `PtychographyPreparer.prepare`, and what it
    /// publishes must be what `prepare` received. Driven through the real `runSingleslicePtychography` on the demo cube (one
    /// iteration): the result's record is the input's, which `prepare` set from its `aberrations` argument, so a call that drops
    /// the argument publishes an in-focus record and this goes red. Before this, dropping `aberrations: aberrations` left the
    /// harness and every unit test green while the status line still said "defocus -600 Å" (it read the settings).
    /// Mutation it catches: `aberrations: aberrations` removed from the `prepare` call in `runSingleslicePtychography`.
    func testTheRunHandsItsFieldsToPrepareAndPublishesWhatPrepareReceived() async throws {
        let state = AppState()
        await state.openDemoFixture(calibrated: true)
        if state.calibrationSession.acceleratingVoltage == nil { state.calibrationSession.acceleratingVoltage = 80 }
        if state.calibrationSession.calibration.rotationRad == nil { state.calibrationSession.calibration.rotationRad = 0 }
        state.changeMode(.singleslicePtychography)
        state.ptychography.iterations = 1
        state.ptychography.defocusAngstrom = -600
        state.ptychography.c12aAngstrom = 35
        state.ptychography.c12bAngstrom = -20
        let typed = PtychographyProbeAberrations(defocusAngstrom: -600, c12aAngstrom: 35, c12bAngstrom: -20)
        XCTAssertEqual(state.ptychography.probeAberrations, typed, "precondition: the fields are what the run should start from")

        await state.runSingleslicePtychography()
        let reconstruction = try XCTUnwrap(state.phaseContrast.singleslicePtychography, state.statusText)
        XCTAssertEqual(reconstruction.probeAberrations, typed, "the reconstruction's record is what prepare received")
        XCTAssertEqual(state.phaseContrast.singleslicePtychographyProbe, typed)
        XCTAssertTrue(state.statusText.contains("defocus -600 Å"), state.statusText)
        XCTAssertEqual(state.resultPresentation.product?.displayName, "Ptychography object phase · defocus -600 Å")
    }
}

//
//  AppState.swift
//  Role: The single source of truth the whole UI observes. It owns the two
//        actors (H5Reader for disk I/O, FourDArray for caching + GPU upload),
//        exposes @Published view state, and provides the high-level actions
//        the UI calls: open a file, pick a scan position, run an analysis.
//
//  CONCURRENCY MODEL (matches the code-quality rules):
//    • AppState is @MainActor → all @Published mutations happen on the main
//      thread, so SwiftUI is always updated safely.
//    • Disk reads live on the H5Reader actor; the GPU-bound, blocking Metal
//      call is pushed onto a detached background task so the UI never stalls.
//    • Errors are funneled into `errorMessage`, which drives a SwiftUI .alert.
//

import Foundation
import SwiftUI

// MARK: - Small UI value types

/// A real-space scan position (column x = Rx index, row y = Ry index).
struct ScanPos: Equatable {
    var x: Int
    var y: Int
}

/// The annular virtual-detector aperture, in *detector pixels*.
struct Aperture: Equatable {
    var centerX: Float
    var centerY: Float
    var inner: Float
    var outer: Float

    init(centerX: Float = 0, centerY: Float = 0,
         inner: Float = 0, outer: Float = 20) {
        self.centerX = centerX
        self.centerY = centerY
        self.inner = inner
        self.outer = outer
    }
}

/// Which pattern the diffraction view shows: the live one under the cursor,
/// or a whole-cube statistic (py4DSTEM's dp_mean / dp_max views).
enum PatternDisplayMode: String, CaseIterable, Identifiable {
    case current = "Current"
    case mean    = "Mean"
    case max     = "Max"
    var id: String { rawValue }
}

/// Geometry family used by the virtual detector (py4DSTEM detector modes).
/// The draggable aperture drives all of them: annulus uses inner+outer radii,
/// rectangle uses the outer radius as half-width, point uses the center pixel.
enum VirtualShapeMode: String, CaseIterable, Identifiable {
    case annulus   = "Annulus"
    case rectangle = "Rectangle"
    case point     = "Point"
    var id: String { rawValue }
}

/// How the DPC result is rendered. All four derive from the same cached CoM
/// field, so switching is instant — no GPU re-run.
enum DPCDisplayMode: String, CaseIterable, Identifiable {
    case magnitude  = "Magnitude"
    case angle      = "Angle"
    case colorWheel = "Color Wheel"
    case idpc       = "iDPC"
    var id: String { rawValue }
}

/// Which analysis the UI is currently showing. Only a subset is wired up in
/// Stage 1; the rest are visible-but-disabled so the roadmap is obvious.
enum AnalysisMode: String, CaseIterable, Identifiable {
    case virtualDetector = "Virtual Det"
    case dpc             = "DPC"
    case disks           = "Disks"
    case strain          = "Strain"
    case ptychography    = "Ptycho"
    case acom            = "ACOM"

    var id: String { rawValue }

    var isAvailable: Bool {
        self == .virtualDetector || self == .dpc || self == .disks
    }
}

// MARK: - AppState

@MainActor
final class AppState: ObservableObject {

    // Backends (not published — they're plumbing, not view state).
    private var reader: H5Reader?
    private(set) var fourD: FourDArray?
    private var openURL: URL?            // kept alive for sandbox access

    // Dataset / navigation
    @Published var datasets: [DatasetDescriptor] = []
    @Published var descriptor: DatasetDescriptor?
    @Published var selectedScan = ScanPos(x: 0, y: 0)
    @Published var acceleratingVoltage: Double?

    // Live images
    @Published var currentPattern: DiffractionPattern?
    @Published var resultImage: FloatImage?
    /// Set instead of a scalar result when the view is inherently colored
    /// (DPC color wheel). Exactly one of resultImage/resultRGBA is active.
    @Published var resultRGBA: RGBAImage?

    // DPC state: the CoM field is cached so display-mode switches are free.
    @Published var dpcDisplay: DPCDisplayMode = .magnitude {
        didSet { applyDPCDisplay() }
    }
    private var comField: [Float]?

    // Disk detection state.
    @Published var probeKernel: ProbeKernel?
    @Published var diskParams = DiskDetectionParams() {
        didSet { Task { await detectCurrentPattern() } }   // live overlay tracks params
    }
    @Published var currentPeaks: [BraggPeak] = []
    @Published var braggPeakCount: Int?                    // total, after a full scan
    private(set) var braggVectors: BraggVectors?

    // Whole-cube diffraction statistics (computed during origin calibration).
    @Published var meanPattern: DiffractionPattern?
    @Published var maxPattern: DiffractionPattern?
    @Published var patternDisplayMode: PatternDisplayMode = .current {
        didSet { patternVersion &+= 1 }
    }

    // Calibration attached to the active dataset.
    @Published var calibration = Calibration()
    @Published var originFitFunction: OriginFitFunction = .plane
    // Version counters: bump when the *content* changes so MetalImageView knows
    // to re-upload its texture (cheaper than diffing big [Float] arrays).
    @Published var patternVersion = 0
    @Published var resultVersion = 0

    // Display options
    @Published var aperture = Aperture()
    @Published var virtualShape: VirtualShapeMode = .annulus
    @Published var colormap: ColormapKind = .viridis {
        didSet {
            // Colormap can change the (symmetric) normalization, so refresh both.
            patternVersion &+= 1
            resultVersion &+= 1
        }
    }
    @Published var logScale = true {
        didSet { patternVersion &+= 1 }   // re-normalize the displayed pattern
    }
    @Published var analysisMode: AnalysisMode = .virtualDetector

    // Status / errors
    @Published var isBusy = false
    @Published var statusText = "No file loaded"
    @Published var errorMessage: String?      // non-nil ⇒ show .alert

    /// The pattern the diffraction view should render, per display mode.
    /// Mean/max fall back to the live pattern until they've been computed.
    var displayedPattern: DiffractionPattern? {
        switch patternDisplayMode {
        case .current: return currentPattern
        case .mean:    return meanPattern ?? currentPattern
        case .max:     return maxPattern ?? currentPattern
        }
    }

    /// Min/max of the displayed pattern, for the status bar.
    var patternMinMax: (Float, Float)? { displayedPattern?.minMax }

    var hasDataset: Bool { descriptor?.is4D == true }

    // MARK: - Open a file

    func openFile(url: URL) {
        Task { await openFileAsync(url: url) }
    }

    private func openFileAsync(url: URL) async {
        isBusy = true
        statusText = "Opening \(url.lastPathComponent)…"
        defer { isBusy = false }

        // Release any previously held sandbox access before grabbing the new one.
        if let prev = openURL { prev.stopAccessingSecurityScopedResource() }
        let accessed = url.startAccessingSecurityScopedResource()
        openURL = accessed ? url : nil

        do {
            let r = try H5Reader(path: url.path)
            let primary = try await r.discoverPrimaryDataset()
            self.reader = r
            self.datasets = [primary]
            await activate(descriptor: primary, reader: r)
        } catch {
            present(error)
        }
    }

    /// Open a specific HDF5 path the user typed in (manual override).
    func openManualPath(_ datasetPath: String) {
        guard let r = reader else {
            present(SimpleError("Open a file first, then enter a dataset path."))
            return
        }
        Task {
            isBusy = true
            defer { isBusy = false }
            do {
                let d = try await r.describe(path: datasetPath)
                if !datasets.contains(where: { $0.datasetPath == d.datasetPath }) {
                    datasets.append(d)
                }
                await activate(descriptor: d, reader: r)
            } catch {
                present(error)
            }
        }
    }

    func selectDataset(_ d: DatasetDescriptor) {
        guard let r = reader else { return }
        Task { await activate(descriptor: d, reader: r) }
    }

    // MARK: - Activate a dataset

    private func activate(descriptor d: DatasetDescriptor, reader r: H5Reader) async {
        guard d.is4D else {
            present(H5Error.unsupportedRank(d.shape.count))
            return
        }
        descriptor = d
        let cube = FourDArray(reader: r, descriptor: d)
        fourD = cube

        // Calibration, cube statistics, and cached results belong to the
        // previous dataset.
        calibration = Calibration()
        meanPattern = nil
        maxPattern = nil
        patternDisplayMode = .current
        comField = nil
        resultRGBA = nil
        probeKernel = nil
        braggVectors = nil
        braggPeakCount = nil
        currentPeaks = []

        // Pixel-scaled detection defaults, adapted to this detector
        // (py4DSTEM's absolute defaults assume ~512 px patterns).
        let qMin = Float(min(d.qx, d.qy))
        var dp = DiskDetectionParams()
        dp.minPeakSpacing = max(4, (qMin / 8).rounded())
        dp.edgeBoundary = max(2, Int(qMin / 24))
        diskParams = dp

        // Sensible defaults: aperture centered on the detector, scan at center.
        let qMax = Float(min(d.qx, d.qy))
        aperture = Aperture(centerX: Float(d.qx) / 2,
                            centerY: Float(d.qy) / 2,
                            inner: 0,
                            outer: qMax / 4)
        selectedScan = ScanPos(x: d.rx / 2, y: d.ry / 2)

        // Accelerating voltage from common attribute names (best-effort).
        var kV: Double?
        for name in ["accelerating_voltage_kV", "accelerating_voltage", "beam_energy"] {
            kV = await r.readDoubleAttribute(name)
            if kV != nil { break }
        }
        acceleratingVoltage = kV

        statusText = "Loaded \(d.fileName) — \(d.shapeString)"

        await loadPattern()
        await runCurrentAnalysis()
    }

    // MARK: - Navigation

    func moveScan(to pos: ScanPos) {
        guard let d = descriptor else { return }
        let clamped = ScanPos(x: min(max(0, pos.x), d.rx - 1),
                              y: min(max(0, pos.y), d.ry - 1))
        guard clamped != selectedScan else { return }
        selectedScan = clamped
        Task { await loadPattern() }
    }

    func loadPattern() async {
        guard let fourD else { return }
        do {
            let p = try await fourD.pattern(ry: selectedScan.y, rx: selectedScan.x)
            currentPattern = p
            patternVersion &+= 1
            await detectCurrentPattern()
        } catch {
            present(error)
        }
    }

    // MARK: - Analyses

    func runCurrentAnalysis() async {
        switch analysisMode {
        case .virtualDetector: await runVirtualDetector()
        case .dpc:             await runDPC()
        case .disks:
            // Live overlay on the current pattern; the full-scan pass is
            // explicit (Detect All Disks) because it's expensive.
            await detectCurrentPattern()
            if let bv = braggVectors, let d = descriptor {
                showBraggMap(bv, descriptor: d)
            }
        default:               break   // Strain / Ptycho / ACOM → Stage 2+
        }
    }

    /// Called continuously while the user drags the aperture (stores values),
    /// and on drag-end we recompute. Keeping recompute on commit avoids
    /// hammering the GPU on every pixel of a drag.
    func updateAperture(_ a: Aperture) {
        aperture = a
    }

    func commitApertureChange() {
        guard analysisMode == .virtualDetector else { return }
        Task { await runVirtualDetector() }
    }

    func runVirtualDetector() async {
        guard let fourD, let d = descriptor else { return }
        isBusy = true
        statusText = "Computing virtual detector…"
        defer { isBusy = false }

        let ap = aperture
        let shapeMode = virtualShape
        do {
            let cube = try await fourD.cubeBuffer()
            // Push the blocking GPU call off the main actor.
            let img = try await Task.detached(priority: .userInitiated) { () throws -> FloatImage in
                switch shapeMode {
                case .annulus:
                    // Analytic fast path — no mask rebuild while dragging.
                    return try VirtualDetector.run(cube: cube, descriptor: d, aperture: ap)
                case .rectangle:
                    let half = Int(ap.outer.rounded())
                    let shape = DetectorShape.rectangle(
                        xMin: Int(ap.centerX.rounded()) - half,
                        xMax: Int(ap.centerX.rounded()) + half,
                        yMin: Int(ap.centerY.rounded()) - half,
                        yMax: Int(ap.centerY.rounded()) + half)
                    return try VirtualDetector.image(cube: cube, descriptor: d, shape: shape)
                case .point:
                    let shape = DetectorShape.point(x: Int(ap.centerX.rounded()),
                                                    y: Int(ap.centerY.rounded()))
                    return try VirtualDetector.image(cube: cube, descriptor: d, shape: shape)
                }
            }.value
            resultImage = img
            resultRGBA = nil
            resultVersion &+= 1
            statusText = "Virtual detector ✓  (\(shapeMode.rawValue), \(d.rx) × \(d.ry))"
        } catch {
            present(error)
        }
    }

    /// Measure the CoM shift field on the GPU, against calibrated origins
    /// when available. Shared by DPC and rotation calibration.
    private func computeCoMField() async throws -> [Float]? {
        guard let fourD, let d = descriptor else { return nil }
        // Reference: calibrated per-position origins when available; else the
        // mean fitted origin; else the aperture center as a last resort.
        let origins = calibration.origin?.interleavedFitted
        let center = calibration.meanOrigin ?? (x: aperture.centerX, y: aperture.centerY)
        let cube = try await fourD.cubeBuffer()
        let params = CoMParams(ry: UInt32(d.ry), rx: UInt32(d.rx),
                               qy: UInt32(d.qy), qx: UInt32(d.qx),
                               cx: center.x, cy: center.y,
                               useOrigins: 0)   // set by the engine if origins != nil
        return try await Task.detached(priority: .userInitiated) {
            try MetalEngine.shared.centerOfMass(cube: cube, params: params,
                                                origins: origins)
        }.value
    }

    func runDPC() async {
        guard descriptor != nil else { return }
        isBusy = true
        statusText = "Computing DPC (center of mass)…"
        defer { isBusy = false }

        do {
            comField = try await computeCoMField()
            applyDPCDisplay()
            let ref = calibration.hasFittedOrigin ? "calibrated origins" : "global center"
            statusText = "DPC ✓  (\(dpcDisplay.rawValue) vs \(ref))"
        } catch {
            present(error)
        }
    }

    /// Derive the displayed image from the cached CoM field per `dpcDisplay`.
    /// Cheap enough to run on the main actor (scan-sized arrays), which keeps
    /// display-mode switching synchronous and simple.
    private func applyDPCDisplay() {
        guard var com = comField, let d = descriptor,
              analysisMode == .dpc else { return }
        // Express the field in the scan frame once rotation is calibrated.
        if let rot = calibration.rotationRad {
            com = DPC.applyRotation(com: com, rotationRad: rot,
                                    transpose: calibration.transposeQR ?? false)
        }
        switch dpcDisplay {
        case .magnitude:
            resultImage = DPC.magnitudeImage(com: com, width: d.rx, height: d.ry)
            resultRGBA = nil
        case .angle:
            resultImage = DPC.angleImage(com: com, width: d.rx, height: d.ry)
            resultRGBA = nil
        case .colorWheel:
            resultRGBA = DPC.colorWheelRGBA(com: com, width: d.rx, height: d.ry)
            resultImage = nil
        case .idpc:
            resultImage = DPC.integrateIDPC(com: com, width: d.rx, height: d.ry)
            resultRGBA = nil
        }
        resultVersion &+= 1
    }

    // MARK: - Calibration

    /// Origin calibration (py4DSTEM get_origin + fit_origin): max pattern →
    /// probe size → per-pattern beam position → smooth fit. Also fills the
    /// mean/max pattern display modes as a side effect.
    func calibrateOrigin() async {
        guard let fourD, let d = descriptor else { return }
        isBusy = true
        statusText = "Calibrating origin…"
        defer { isBusy = false }

        let fitFn = originFitFunction
        do {
            let cube = try await fourD.cubeBuffer()
            let result = try await Task.detached(priority: .userInitiated) {
                try OriginCalibration.run(cube: cube, descriptor: d, fitFunction: fitFn)
            }.value

            calibration.probeRadius = result.probeRadius
            calibration.origin = result.origin
            meanPattern = DiffractionPattern(qy: d.qy, qx: d.qx, pixels: result.meanDP)
            maxPattern = DiffractionPattern(qy: d.qy, qx: d.qx, pixels: result.maxDP)
            patternVersion &+= 1

            // Recenter the aperture on the measured beam.
            if let o = calibration.meanOrigin {
                aperture.centerX = o.x
                aperture.centerY = o.y
            }
            let rms = result.origin.rmsResidual
            statusText = String(format: "Origin ✓  r ≈ %.1f px, fit RMS %.3f px (%@)",
                                result.probeRadius, rms, fitFn.rawValue)

            // Refresh whichever analysis is showing with the new reference.
            await runCurrentAnalysis()
        } catch {
            present(error)
        }
    }

    /// R–Q rotation calibration: find the rotation (and detector transpose)
    /// that makes the CoM field curl-free (RotationCalibration). Runs origin
    /// calibration first if needed — the solver wants the descan-corrected
    /// field, and a residual descan plane would bias the curl.
    func calibrateRotation(maximizeDivergence: Bool = false) async {
        guard let d = descriptor else { return }

        if !calibration.hasFittedOrigin {
            await calibrateOrigin()
            guard calibration.hasFittedOrigin else { return }   // it errored
        }

        isBusy = true
        statusText = "Calibrating R–Q rotation…"
        defer { isBusy = false }

        do {
            if comField == nil { comField = try await computeCoMField() }
            guard let com = comField else { return }

            let result = await Task.detached(priority: .userInitiated) {
                RotationCalibration.solve(com: com, width: d.rx, height: d.ry,
                                          maximizeDivergence: maximizeDivergence)
            }.value
            guard let result else {
                present(SimpleError("Scan is too small for rotation calibration (need at least 3 × 3 positions)."))
                return
            }
            calibration.rotationRad = result.rotationRad
            calibration.transposeQR = result.transpose
            applyDPCDisplay()
            statusText = String(format: "Rotation ✓  θ = %.1f°%@",
                                result.rotationRad * 180 / .pi,
                                result.transpose ? ", detector transposed" : "")
        } catch {
            present(error)
        }
    }

    // MARK: - Disk detection

    /// Build the synthetic probe kernel from the calibrated probe radius,
    /// running origin calibration first if needed.
    func generateProbeKernel() async {
        guard let d = descriptor else { return }
        if calibration.probeRadius == nil {
            await calibrateOrigin()
            guard calibration.probeRadius != nil else { return }   // it errored
        }
        guard let r = calibration.probeRadius else { return }

        guard let k = ProbeKernel.synthetic(radius: r, qy: d.qy, qx: d.qx) else {
            present(SimpleError("Could not build a probe kernel (radius \(r) px)."))
            return
        }
        probeKernel = k
        statusText = String(format: "Probe kernel ✓  r = %.1f px, trench %.0f–%.0f px",
                            r, k.trenchRadii.inner, k.trenchRadii.outer)
        await detectCurrentPattern()
    }

    /// Live overlay: detect disks in the currently displayed pattern only.
    func detectCurrentPattern() async {
        guard analysisMode == .disks, let k = probeKernel,
              let pattern = currentPattern else {
            if !currentPeaks.isEmpty { currentPeaks = [] }
            return
        }
        let params = diskParams
        let peaks = await Task.detached(priority: .userInitiated) { () -> [BraggPeak] in
            guard let det = DiskDetector(kernel: k) else { return [] }
            return det.detect(pattern: pattern.pixels, params: params)
        }.value
        currentPeaks = peaks
    }

    /// Full-scan detection → BraggVectors + Bragg vector map.
    func runDiskDetection() async {
        guard let fourD, let d = descriptor else { return }
        if probeKernel == nil {
            await generateProbeKernel()
        }
        guard let k = probeKernel else { return }

        isBusy = true
        statusText = "Detecting Bragg disks…"
        defer { isBusy = false }

        let params = diskParams
        do {
            let cube = try await fourD.cubeBuffer()
            let vectors = await Task.detached(priority: .userInitiated) { [weak self] () -> BraggVectors? in
                DiskDetection.detectAll(cube: cube, descriptor: d,
                                        kernel: k, params: params) { f in
                    Task { @MainActor in
                        self?.statusText = "Detecting Bragg disks… \(Int(f * 100)) %"
                    }
                }
            }.value
            guard let vectors else {
                present(SimpleError("Disk detection failed to initialize its FFT plan."))
                return
            }
            braggVectors = vectors
            braggPeakCount = vectors.totalPeakCount
            showBraggMap(vectors, descriptor: d)
            statusText = "Disks ✓  \(vectors.totalPeakCount) peaks "
                       + "(\(params.subpixel.rawValue) subpixel)"
        } catch {
            present(error)
        }
    }

    /// Show the Bragg vector map (log-scaled for display — the central beam
    /// dominates the raw histogram) in the result pane.
    private func showBraggMap(_ bv: BraggVectors, descriptor d: DatasetDescriptor) {
        let bvm = bv.map(qy: d.qy, qx: d.qx)
        resultImage = FloatImage(width: bvm.width, height: bvm.height,
                                 pixels: bvm.pixels.map { log10(1 + max($0, 0)) })
        resultRGBA = nil
        resultVersion &+= 1
    }

    /// Apply a standard detector geometry (BF/ADF/HAADF) and recompute.
    func applyDetectorPreset(_ preset: DetectorPreset) {
        guard let d = descriptor else { return }
        let qMax = Float(min(d.qx, d.qy)) / 2
        if let (inner, outer) = preset.radii(maxRadius: qMax) {
            aperture.inner = inner
            aperture.outer = outer
            aperture.centerX = Float(d.qx) / 2
            aperture.centerY = Float(d.qy) / 2
        }
        if analysisMode != .virtualDetector { analysisMode = .virtualDetector }
        Task { await runVirtualDetector() }
    }

    func changeMode(_ mode: AnalysisMode) {
        analysisMode = mode
        guard mode.isAvailable else {
            statusText = "\(mode.rawValue) is coming in a later stage."
            return
        }
        Task { await runCurrentAnalysis() }
    }

    // MARK: - Errors

    func present(_ error: Error) {
        errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        statusText = "Error"
    }
}

// MARK: - Tiny ad-hoc error

struct SimpleError: LocalizedError {
    let message: String
    init(_ m: String) { message = m }
    var errorDescription: String? { message }
}

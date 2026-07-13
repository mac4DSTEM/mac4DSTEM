import Foundation

struct SimpleError: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? { message }
}

/// A real-space scan position. x is the scan column and y is the scan row.
struct ScanPos: Equatable {
    var x: Int
    var y: Int
}

/// The virtual-detector aperture in detector pixels.
struct Aperture: Equatable {
    var centerX: Float
    var centerY: Float
    var inner: Float
    var outer: Float

    init(centerX: Float = 0, centerY: Float = 0, inner: Float = 0, outer: Float = 20) {
        self.centerX = centerX
        self.centerY = centerY
        self.inner = inner
        self.outer = outer
    }
}

enum PatternDisplayMode: String, CaseIterable, Identifiable {
    case current = "Current"
    case mean = "Mean"
    case max = "Max"

    var id: String { rawValue }
}

enum VirtualShapeMode: String, CaseIterable, Identifiable {
    case circle = "Circle"
    case annulus = "Annulus"
    case rectangle = "Rectangle"
    case point = "Point"

    var id: String { rawValue }
}

enum DPCDisplayMode: String, CaseIterable, Identifiable {
    case magnitude = "Magnitude (detector px)"
    case magnitudeMrad = "Magnitude (mrad)"
    case angle = "Angle"
    case colorWheel = "Color Wheel"
    case idpc = "iDPC"

    var id: String { rawValue }
}

enum AnalysisMode: String, CaseIterable, Identifiable {
    case virtualDetector = "Virtual Det"
    case dpc = "DPC"
    case disks = "Disks"
    case strain = "Strain"
    case ptychography = "Ptycho"
    case acom = "ACOM"

    var id: String { rawValue }

    var isAvailable: Bool {
        self == .virtualDetector || self == .dpc || self == .disks
            || self == .strain || self == .ptychography || self == .acom
    }
}

enum ParallaxResultProduct: String, CaseIterable, Identifiable, Sendable {
    case preprocess = "Preprocessed BF"
    case alignment = "Aligned BF"
    case subpixel = "Subpixel BF"
    case correctedPhase = "Corrected phase"
    case depth = "Depth plane"
    case iterativePhase = "Ptychography phase"
    case iterativeAmplitude = "Ptychography amplitude"
    case iterativeProbePhase = "Probe phase"
    case iterativeProbeAmplitude = "Probe amplitude"

    var id: String { rawValue }
}

/// Crystal presets offered for ACOM template generation. `.custom` is a
/// user-defined cubic crystal (element + structure + lattice constant) —
/// resolved by AppState.resolvedACOMCrystal, not here.
enum CrystalChoice: String, CaseIterable, Identifiable {
    case gold      = "Gold (FCC)"
    case aluminum  = "Aluminium (FCC)"
    case nickel    = "Nickel (FCC)"
    case copper    = "Copper (FCC)"
    case iron      = "Iron (BCC)"
    case silicon   = "Silicon (diamond)"
    case custom    = "Custom…"
    var id: String { rawValue }

    var crystal: Crystal {
        switch self {
        case .gold:     return .gold
        case .aluminum: return .aluminum
        case .nickel:   return .nickel
        case .copper:   return .copper
        case .iron:     return .iron
        case .silicon:  return .silicon
        case .custom:   return .gold   // placeholder; see resolvedACOMCrystal
        }
    }
}

/// Which ACOM result map to display.
enum ACOMDisplayMode: String, CaseIterable, Identifiable {
    case ipfZ        = "IPF · Z"
    case reliability = "Reliability"
    case disorientation = "Cubic FZ angle"
    case inPlane     = "In-plane angle"
    case phi1        = "Euler φ₁"
    case Phi         = "Euler Φ"
    case phi2        = "Euler φ₂"
    case score       = "Score"
    var id: String { rawValue }
}

/// Which image pane the user is currently operating on. Determines which ROI
/// tools the left panel shows and where interactions are routed.
enum ActivePane {
    case diffraction   // detector ROI → real-space image (virtual imaging)
    case realSpace     // region ROI → diffraction pattern (virtual diffraction)
}

/// Real-space region shape for virtual diffraction. A point is plain scrubbing
/// (one position); a region sums its positions' patterns.
enum RegionShape: String, CaseIterable, Identifiable {
    case point     = "Point"
    case rectangle = "Rectangle"
    case circle    = "Circle"
    var id: String { rawValue }
}

enum StrainReferenceMode: String, CaseIterable, Identifiable {
    case wholeScan = "Whole-scan mean"
    case selectedRegion = "Current real-space ROI"
    var id: String { rawValue }
}

enum StrainBasisMode: String, CaseIterable, Identifiable {
    case automatic = "Automatic"
    case manual = "Manual g₁ / g₂"
    var id: String { rawValue }
}

@Observable
final class AppState {
    private var reader: (any FourDDataSource)?
    private var fourD: FourDArray?
    private var openURL: URL?
    @ObservationIgnored var scopedSessionSidecarURL: URL?

    var datasets: [DatasetDescriptor] = []
    var descriptor: DatasetDescriptor?
    var selectedScan = ScanPos(x: 0, y: 0)
    var acceleratingVoltage: Double?

    var currentPattern: DiffractionPattern?
    var resultImage: FloatImage?
    var resultRGBA: RGBAImage?
    /// Set only while `resultImage` is the scalar map restored from the stable
    /// session sidecar. New scientific results clear it at publication.
    @ObservationIgnored var restoredResultInfo: (kind: String, displayName: String, valueUnits: String)?
    @ObservationIgnored var restoredResultPixelInfo:
        (row: Double?, column: Double?, units: String?, provenance: [String: String])?
    /// Read-only inventory of supported objects in the stable companion file.
    var sessionInventory: SessionSidecarInventory = .empty

    var meanPattern: DiffractionPattern?
    var maxPattern: DiffractionPattern?
    var patternDisplayMode: PatternDisplayMode = .current {
        didSet {
            patternVersion &+= 1
            Task { await detectCurrentPattern() }
        }
    }

    var calibration = Calibration()
    private(set) var calibrationProvenance = CalibrationProvenance()
    var originFitFunction: OriginFitFunction = .plane
    var ellipseFitInnerRadius: Double = 10
    var ellipseFitOuterRadius: Double = 30
    private(set) var lastEllipseFit: EllipseCalibrationFit?
    private(set) var parallaxPreprocess: ParallaxPreprocessResult?
    private(set) var parallaxAberrationFit: ParallaxAberrationFitResult?
    private(set) var parallaxCorrection: ParallaxAberrationCorrectionResult?
    private(set) var parallaxSubpixel: ParallaxSubpixelResult?
    private(set) var parallaxDepth: ParallaxDepthResult?
    private(set) var singleslicePtychography: SingleslicePtychographyResult?
    var ptychographyIterations = 8
    var ptychographyStepSize: Float = 0.5
    var ptychographyNormalizationMinimum: Float = 1
    var ptychographyFixProbe = false
    var ptychographyConstrainObjectAmplitude = false
    var ptychographyPurePhaseObject = false
    var ptychographyFixProbeCenterOfMass = false
    var ptychographyConstrainProbeAmplitude = false
    var ptychographyProbeAmplitudeRadius: Float = 0.5
    var ptychographyProbeAmplitudeWidth: Float = 0.05
    var parallaxKDEUpsampleFactor: Double = 0
    var parallaxKDESigmaPixels: Double = 0.125
    var parallaxKDELowpass = false
    var parallaxKDELanczosOrder = 0
    var parallaxPositionCorrectionIterations = 0
    var parallaxPositionCorrectionCheckerboard = false
    var parallaxDepthStartAngstrom: Double = -256
    var parallaxDepthEndAngstrom: Double = 256
    var parallaxDepthPlaneCount = 33
    var parallaxDepthUseFullFit = true
    var parallaxDepthInformationLimit: Double = 0
    var parallaxDepthInformationPower: Double = 1
    private(set) var parallaxDepthSelectedIndex = 0
    private(set) var parallaxResultProduct: ParallaxResultProduct = .preprocess
    private(set) var parallaxHigherOrderFit: ParallaxHigherOrderAberrationFitResult? {
        didSet {
            parallaxCorrection = nil
            parallaxDepth = nil
        }
    }
    var parallaxQLowpassInvAngstrom: Double = 0
    var parallaxQHighpassInvAngstrom: Double = 0
    private(set) var parallaxAlignment: ParallaxAlignmentResult? {
        didSet {
            parallaxAberrationFit = nil
            parallaxHigherOrderFit = nil
            parallaxSubpixel = nil
            parallaxDepth = nil
        }
    }
    /// Full rotation-calibration result (objective curves) for the
    /// diagnostics plot in the inspector.
    var lastRotationResult: RotationCalibration.Result?
    var patternVersion = 0
    var resultVersion = 0

    // DPC: cached CoM shift field so display-mode switches don't re-run the GPU.
    @ObservationIgnored private var comField: [Float]?

    // Disk detection state.
    var probeKernel: ProbeKernel?
    var currentPeaks: [BraggPeak] = []
    var braggPeakCount: Int?
    private(set) var braggVectors: BraggVectors?
    @ObservationIgnored private var liveDetectionRequest: UInt64 = 0
    var diskParams = DiskDetectionParams() {
        didSet { Task { await detectCurrentPattern() } }   // live overlay tracks params
    }

    // Strain mapping state.
    private(set) var strainMap: StrainMap?
    var strainComponent: StrainComponent = .exx {
        didSet { applyStrainDisplay() }
    }

    // ACOM state.
    @ObservationIgnored private(set) var orientationPlan: OrientationPlan?
    @ObservationIgnored private(set) var orientationMap: OrientationMap?
    var hasOrientationPlan = false
    var hasOrientationMap = false
    var acomCrystal: CrystalChoice = .gold
    var acomScale: Double = 0.01           // Å⁻¹ per detector pixel (Q calibration)

    // Custom (user-defined) cubic crystal for ACOM.
    var customZ: Int = 79                                  // element (Au default)
    var customStructure: Crystal.CubicStructure = .fcc
    var customLatticeA: Double = 4.08                      // Å

    var selectedEulerText: String? {
        guard let map = orientationMap,
              selectedScan.x >= 0, selectedScan.x < map.width,
              selectedScan.y >= 0, selectedScan.y < map.height else { return nil }
        let degrees = map[selectedScan.x, selectedScan.y].euler.degrees
        return String(format: "%.1f°, %.1f°, %.1f°", degrees.0, degrees.1, degrees.2)
    }

    /// The crystal ACOM should use — a preset, or the user-defined cubic cell.
    var resolvedACOMCrystal: Crystal {
        acomCrystal == .custom
            ? Crystal.cubic(customStructure, a: customLatticeA, z: customZ)
            : acomCrystal.crystal
    }
    var acomDisplay: ACOMDisplayMode = .reliability {
        didSet { applyACOMDisplay() }
    }

    var aperture = Aperture()
    var virtualShape: VirtualShapeMode = .annulus

    // Active pane + real-space region (virtual diffraction).
    var activePane: ActivePane = .diffraction
    var realSpaceShape: RegionShape = .point
    var realSpaceRadius: Float = 6            // scan px half-extent / radius
    var virtualDiffractionPattern: DiffractionPattern?
    var strainReferenceMode: StrainReferenceMode = .wholeScan
    var strainBasisMode: StrainBasisMode = .automatic
    var strainG1X: Float = 10
    var strainG1Y: Float = 0
    var strainG2X: Float = 0
    var strainG2Y: Float = 10
    var dpcDisplay: DPCDisplayMode = .magnitude {
        didSet { applyDPCDisplay() }
    }
    var colormap: ColormapKind = .viridis {
        didSet {
            patternVersion &+= 1
            resultVersion &+= 1
        }
    }
    var logScale = true {
        didSet { patternVersion &+= 1 }
    }
    /// Display contrast window for the diffraction pane. Kept independent of
    /// the real-space result window so adjusting a CBED never changes a map.
    var patternDisplayRangeLo: Float = 0
    var patternDisplayRangeHi: Float = 1
    var patternGamma: Float = 1
    var analysisMode: AnalysisMode = .virtualDetector

    var isBusy = false
    var statusText = "No file loaded" {
        didSet { appendLog(statusText) }
    }
    var errorMessage: String?

    /// Rolling log of meaningful status events, shown in the output strip
    /// below the image panes. Progress spam ("… 42 %") is filtered out.
    private(set) var logMessages: [String] = []
    var showLogPane = true
    var showToolsPane = true
    var showInspectorPane = false
    private(set) var openDatasetRequest = 0
    private(set) var preprocessingExportRequest = 0

    func requestOpenDataset() { openDatasetRequest &+= 1 }
    func requestPreprocessingExport() { preprocessingExportRequest &+= 1 }

    var calibrationReadiness: CalibrationReadinessReport {
        CalibrationReadinessReport.make(
            calibration: calibration, provenance: calibrationProvenance
        )
    }

    private func appendLog(_ message: String) {
        guard !message.isEmpty, !message.hasSuffix("%") else { return }
        if logMessages.last?.hasSuffix(message) == true { return }
        let stamp = Self.logClock.string(from: Date())
        logMessages.append("\(stamp)  \(message)")
        if logMessages.count > 300 { logMessages.removeFirst(logMessages.count - 300) }
    }

    private static let logClock: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    /// Increments whenever a (new) dataset is activated. Long-running detached
    /// analyses capture the epoch at launch and drop their results if it has
    /// moved on — otherwise work from a previous file could land in the state
    /// of the current one.
    private(set) var datasetEpoch = 0

    /// Display contrast window for the real-space result, as fractions of the
    /// normalized [0,1] intensity range (driven by the histogram range slider,
    /// applied in the fragment shader).
    var displayRangeLo: Float = 0
    var displayRangeHi: Float = 1
    var resultGamma: Float = 1

    /// Raw-value endpoints currently assigned to the scalar result colorbar.
    var resultDisplayedValueRange: (low: Double, high: Double)? {
        guard let image = resultImage else { return nil }
        let (rawLow, rawHigh) = image.minMax
        guard rawLow.isFinite, rawHigh.isFinite else { return nil }
        let baseLow: Double
        let baseHigh: Double
        if colormap.isDiverging {
            let magnitude = Double(max(abs(rawLow), abs(rawHigh)))
            baseLow = -magnitude
            baseHigh = magnitude
        } else {
            baseLow = Double(rawLow)
            baseHigh = Double(rawHigh)
        }
        let span = baseHigh - baseLow
        return (baseLow + span * Double(displayRangeLo),
                baseLow + span * Double(displayRangeHi))
    }

    /// Raw intensity endpoints currently assigned to the CBED colorbar. When
    /// log display is active, transform-space clipping is inverted back to
    /// intensity so the labels remain physically interpretable.
    var patternDisplayedValueRange: (low: Double, high: Double)? {
        guard let pattern = displayedPattern else { return nil }
        var low = Double.greatestFiniteMagnitude
        var high = -Double.greatestFiniteMagnitude
        for pixel in pattern.pixels where pixel.isFinite {
            let value = logScale ? log10(1 + Double(max(pixel, 0))) : Double(pixel)
            low = min(low, value)
            high = max(high, value)
        }
        guard low <= high else { return nil }
        let span = high - low
        let clippedLow = low + span * Double(patternDisplayRangeLo)
        let clippedHigh = low + span * Double(patternDisplayRangeHi)
        if logScale {
            return (pow(10, clippedLow) - 1, pow(10, clippedHigh) - 1)
        }
        return (clippedLow, clippedHigh)
    }

    /// Fractional progress [0,1] of the running long operation, or nil when
    /// idle / indeterminate. Drives the performance panel's progress bar.
    var progress: Double?
    @ObservationIgnored private let operationController = AnalysisOperationController()
    /// Short label and unit budget for the performance panel.
    var activeOperation: String? { operationController.name }
    var activeOperationTotalUnits: Int? { operationController.totalUnits }

    var canCancelActiveOperation: Bool {
        isBusy && operationController.hasActiveOperation
    }

    func beginCancellableOperation(
        _ name: String, status: String, totalUnits: Int? = nil
    )
        -> AnalysisCancellationToken {
        let token = operationController.begin(name: name, totalUnits: totalUnits)
        isBusy = true
        progress = 0
        statusText = status
        return token
    }

    func finishCancellableOperation(_ token: AnalysisCancellationToken) {
        guard operationController.finish(token) else { return }
        isBusy = false
        progress = nil
    }

    func activeOperationMetrics(at now: Date = Date())
        -> AnalysisOperationMetrics? {
        operationController.metrics(progress: progress, at: now)
    }

    /// Cross-file operation helpers keep extensions from reaching into the
    /// token identity itself while still rejecting late progress/status work.
    func isCurrentOperation(_ token: AnalysisCancellationToken) -> Bool {
        operationController.isCurrent(token)
    }

    func updateCancellableOperation(
        _ token: AnalysisCancellationToken, progress fraction: Double, status: String
    ) {
        guard operationController.isCurrent(token), !token.isCancelled else { return }
        progress = min(1, max(0, fraction))
        statusText = status
    }

    func cancelActiveOperation() {
        guard let name = operationController.cancelCurrent() else { return }
        statusText = "Cancelling \(name)…"
    }

    // Normalized-pixel caches: SwiftUI re-evaluates view bodies far more often
    // than content changes, and normalization is O(pixels) + an allocation.
    // Keyed on the version counters, so texture and cache invalidate together.
    @ObservationIgnored private var patternNormCache: (version: Int, log: Bool, pixels: [Float])?
    @ObservationIgnored private var resultNormCache: (version: Int, symmetric: Bool, pixels: [Float])?

    /// Display-normalized pixels of `displayedPattern`, cached per patternVersion.
    func normalizedPatternPixels() -> [Float] {
        guard let pattern = displayedPattern else { return [] }
        if let c = patternNormCache, c.version == patternVersion, c.log == logScale {
            return c.pixels
        }
        let pixels = pattern.normalized(useLog: logScale)
        patternNormCache = (patternVersion, logScale, pixels)
        return pixels
    }

    /// Display-normalized pixels of `resultImage`, cached per resultVersion.
    func normalizedResultPixels() -> [Float] {
        guard let image = resultImage else { return [] }
        let symmetric = colormap.isDiverging
        if let c = resultNormCache, c.version == resultVersion, c.symmetric == symmetric {
            return c.pixels
        }
        let pixels = image.normalized(symmetric: symmetric)
        resultNormCache = (resultVersion, symmetric, pixels)
        return pixels
    }

    var displayedPattern: DiffractionPattern? {
        // A real-space region ROI drives the CBED with the summed pattern.
        if realSpaceShape != .point, let vd = virtualDiffractionPattern { return vd }
        switch patternDisplayMode {
        case .current: return currentPattern
        case .mean: return meanPattern ?? currentPattern
        case .max: return maxPattern ?? currentPattern
        }
    }

    var patternMinMax: (Float, Float)? { displayedPattern?.minMax }

    var hasDataset: Bool { descriptor?.is4D == true }

    /// Narrow handoff used by the export workflow without exposing the mutable
    /// reader slot to views. The returned value is an actor and remains safe to
    /// use from the detached preprocessing task.
    func currentDataSourceForExport() -> (any FourDDataSource)? { reader }

    func changeMode(_ mode: AnalysisMode) {
        guard mode.isAvailable else { return }
        analysisMode = mode
    }

    func openFile(url: URL) {
        Task { await openFileAsync(url: url) }
    }

    func selectDataset(_ descriptor: DatasetDescriptor) {
        guard let reader else { return }
        Task { await activate(descriptor: descriptor, reader: reader) }
    }

    func openManualPath(_ datasetPath: String) {
        guard let reader else {
            present(SimpleError("Open a file before entering a dataset path."))
            return
        }

        Task {
            isBusy = true
            defer { isBusy = false }

            do {
                guard let h5 = reader as? H5Reader else {
                    present(SimpleError("Manual dataset paths are only supported for HDF5 files."))
                    return
                }
                let descriptor = try await h5.describe(path: datasetPath)
                if !datasets.contains(where: { $0.datasetPath == descriptor.datasetPath }) {
                    datasets.append(descriptor)
                }
                await activate(descriptor: descriptor, reader: h5)
            } catch {
                present(error)
            }
        }
    }

    func selectScan(x: Int, y: Int) {
        selectedScan = ScanPos(x: x, y: y)
        Task { await loadCurrentPattern() }
    }

    func present(_ error: Error) {
        errorMessage = error.localizedDescription
        statusText = "Error: \(error.localizedDescription)"
    }

    private func openFileAsync(url: URL) async {
        isBusy = true
        statusText = "Opening \(url.lastPathComponent)..."
        errorMessage = nil
        defer { isBusy = false }

        if let openURL {
            openURL.stopAccessingSecurityScopedResource()
        }
        if let scopedSessionSidecarURL {
            scopedSessionSidecarURL.stopAccessingSecurityScopedResource()
            self.scopedSessionSidecarURL = nil
        }

        let accessed = url.startAccessingSecurityScopedResource()
        openURL = accessed ? url : nil

        do {
            let ext = url.pathExtension.lowercased()
            let reader: any FourDDataSource
            if ext == "dm4" || ext == "dm3" {
                reader = try await DM4Reader(path: url.path)
            } else {
                reader = try H5Reader(path: url.path)
            }
            let descriptor = try await reader.discoverPrimaryDataset()
            self.reader = reader
            datasets = [descriptor]
            await activate(descriptor: descriptor, reader: reader)
        } catch {
            present(error)
        }
    }

    private func activate(descriptor: DatasetDescriptor, reader: any FourDDataSource) async {
        guard descriptor.is4D else {
            present(H5Error.unsupportedRank(descriptor.shape.count))
            return
        }

        // Dataset replacement is also a cancellation boundary. The epoch still
        // independently prevents any non-cooperative GPU result from landing.
        operationController.reset()
        progress = nil
        isBusy = false
        datasetEpoch &+= 1
        self.descriptor = descriptor
        fourD = FourDArray(reader: reader, descriptor: descriptor)
        selectedScan = ScanPos(x: 0, y: 0)
        displayRangeLo = 0
        displayRangeHi = 1
        resultGamma = 1
        patternDisplayRangeLo = 0
        patternDisplayRangeHi = 1
        patternGamma = 1
        lastRotationResult = nil
        lastEllipseFit = nil
        parallaxPreprocess = nil
        parallaxAlignment = nil
        singleslicePtychography = nil
        parallaxResultProduct = .preprocess
        let detectorHalfSize = Double(min(descriptor.qx, descriptor.qy)) / 2
        ellipseFitInnerRadius = max(1, detectorHalfSize * 0.35)
        ellipseFitOuterRadius = max(ellipseFitInnerRadius + 2, detectorHalfSize * 0.9)
        aperture = Aperture(
            centerX: Float(descriptor.qx) / 2,
            centerY: Float(descriptor.qy) / 2,
            inner: 0,
            outer: Float(min(descriptor.qx, descriptor.qy)) / 4
        )
        if let rawVoltage = await reader.readDoubleAttribute(
            "accelerating_voltage", onObjectPath: "/"
        ) {
            // py4DSTEM metadata commonly stores eV while microscope UI and
            // DM tags may expose kV. Keep one app convention: kV.
            acceleratingVoltage = rawVoltage > 1_000 ? rawVoltage / 1_000 : rawVoltage
        } else {
            acceleratingVoltage = nil
        }
        calibration = Calibration()
        calibrationProvenance = CalibrationProvenance()
        // Pixel sizes from file metadata (DM4 tags or py4DSTEM EMD bundle).
        if let pc = await reader.pixelCalibration() {
            var rSize = pc.rSize
            var rUnits = pc.rUnits
            // Normalize µm → nm (STEM-scale bars read better in nm).
            if let r = rSize, ["µm", "um", "micron"].contains(rUnits?.lowercased() ?? "") {
                rSize = r * 1000
                rUnits = "nm"
            }
            calibration.rPixelSize = rSize
            calibration.rPixelUnits = rUnits
            calibration.qPixelSize = pc.qSize
            calibration.qPixelUnits = pc.qUnits
            if rSize.map({ $0.isFinite && $0 > 0 }) == true {
                calibrationProvenance.rScale = .importedFile
            }
            if pc.qSize.map({ $0.isFinite && $0 > 0 }) == true {
                calibrationProvenance.qScale = .importedFile
            }
            if let flip = pc.qrFlip { calibration.transposeQR = flip }
            calibration.rotationRad = pc.qrRotationRad.map(Float.init)
            calibration.probeRadius = pc.probeSemiangle.map(Float.init)
            calibration.ellipseA = pc.ellipseA
            calibration.ellipseB = pc.ellipseB
            calibration.ellipseTheta = pc.ellipseTheta
            if calibration.hasRotation { calibrationProvenance.rotation = .importedFile }
            if calibration.probeRadius.map({ $0.isFinite && $0 > 0 }) == true {
                calibrationProvenance.probe = .importedFile
            }
            if calibration.hasEllipse { calibrationProvenance.ellipse = .importedFile }
            // AXIS SWAP (single documented conversion point — see
            // PixelCalibration.qx0Mean/qy0Mean doc comment): py4DSTEM indexes
            // patterns (qx, qy) with qx as the first/row axis, which is this
            // app's detector y; qy is the second/column axis, this app's x.
            // So app aperture x = qy0Mean, app aperture y = qx0Mean.
            if let qx0 = pc.qx0Mean, let qy0 = pc.qy0Mean {
                aperture.centerX = Float(qy0)
                aperture.centerY = Float(qx0)
                calibration.originProvenance = .fileMean
            }
            // Full py4DSTEM origin maps use real-space order [R_Nx, R_Ny],
            // matching app [Ry, Rx]. Detector coordinates still need the one
            // documented swap: py4DSTEM qx -> app y, qy -> app x.
            if let maps = pc.originMaps,
               let appMaps = maps.appOriginMaps(width: descriptor.rx, height: descriptor.ry) {
                calibration.origin = appMaps
                if let origin = calibration.meanOrigin {
                    aperture.centerX = origin.x
                    aperture.centerY = origin.y
                }
                calibration.originProvenance = .fileMaps
            }
            // Auto-fill the ACOM Q scale (Å⁻¹/px) when the units are convertible.
            if let q = pc.qSize, q > 0 {
                switch pc.qUnits?.lowercased() {
                case "1/nm", "nm^-1", "1/nanometer": acomScale = q * 0.1
                case "1/a", "1/å", "a^-1", "å^-1", "1/angstrom", "angstrom^-1": acomScale = q
                default: break
                }
            }
        }
        patternDisplayMode = .current
        meanPattern = nil
        maxPattern = nil
        resultImage = nil
        resultRGBA = nil
        restoredResultInfo = nil
        sessionInventory = .empty
        comField = nil
        probeKernel = nil
        braggVectors = nil
        braggPeakCount = nil
        currentPeaks = []
        strainMap = nil
        orientationPlan = nil
        orientationMap = nil
        hasOrientationPlan = false
        hasOrientationMap = false
        activePane = .diffraction
        realSpaceShape = .point
        virtualDiffractionPattern = nil
        realSpaceRadius = Float(max(3, min(descriptor.rx, descriptor.ry) / 12))

        // Pixel-scaled detection defaults, adapted to this detector
        // (py4DSTEM's absolute defaults assume ~512 px patterns).
        let qMin = Float(min(descriptor.qx, descriptor.qy))
        var dp = DiskDetectionParams()
        dp.minPeakSpacing = max(4, (qMin / 8).rounded())
        dp.edgeBoundary = max(2, Int(qMin / 24))
        diskParams = dp

        let sessionSnapshot = await loadSessionSnapshot(for: descriptor)
        await loadCurrentPattern()
        statusText = "Loaded \(descriptor.fileName) at \(descriptor.datasetPath)"
        await runCurrentAnalysis()
        if let sessionSnapshot {
            restoreSessionResult(from: sessionSnapshot, for: descriptor)
        }
    }

    private func loadSessionSnapshot(
        for descriptor: DatasetDescriptor
    ) async -> SessionSidecarSnapshot? {
        let url = resolvedSessionSidecarURL(for: descriptor)
            ?? BraggVectorEMDWriter.sessionSidecarURL(forSourcePath: descriptor.filePath)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let epoch = datasetEpoch
        do {
            let snapshot = try await Task.detached(priority: .utility) {
                try BraggVectorEMDWriter.loadSession(from: url)
            }.value
            guard epoch == datasetEpoch else { return nil }
            sessionInventory = snapshot.inventory
            if let sessionCalibration = snapshot.calibration {
                applySessionCalibration(sessionCalibration, for: descriptor)
            }
            return snapshot
        } catch {
            guard epoch == datasetEpoch else { return nil }
            statusText = "Could not restore \(url.lastPathComponent): \(error.localizedDescription)"
            return nil
        }
    }

    private func applySessionCalibration(
        _ saved: PixelCalibration, for descriptor: DatasetDescriptor
    ) {
        if let value = saved.rSize {
            calibration.rPixelSize = value
            calibrationProvenance.rScale = value.isFinite && value > 0 ? .sessionSidecar : nil
        }
        if let value = saved.rUnits { calibration.rPixelUnits = value }
        if let value = saved.qSize {
            calibration.qPixelSize = value
            calibrationProvenance.qScale = value.isFinite && value > 0 ? .sessionSidecar : nil
        }
        if let value = saved.qUnits { calibration.qPixelUnits = value }
        if let value = saved.qrFlip { calibration.transposeQR = value }
        if let value = saved.qrRotationRad {
            calibration.rotationRad = Float(value)
            calibrationProvenance.rotation = value.isFinite ? .sessionSidecar : nil
        }
        if let value = saved.probeSemiangle {
            calibration.probeRadius = Float(value)
            calibrationProvenance.probe = value.isFinite && value > 0 ? .sessionSidecar : nil
        }
        let savedEllipseCount = [saved.ellipseA, saved.ellipseB, saved.ellipseTheta]
            .compactMap { $0 }.count
        if let value = saved.ellipseA { calibration.ellipseA = value }
        if let value = saved.ellipseB { calibration.ellipseB = value }
        if let value = saved.ellipseTheta { calibration.ellipseTheta = value }
        if savedEllipseCount > 0 {
            calibrationProvenance.ellipse = calibration.hasEllipse
                ? (savedEllipseCount == 3 ? .sessionSidecar : .mixed)
                : nil
        }

        var restoredMaps = false
        if let maps = saved.originMaps,
           let appMaps = maps.appOriginMaps(width: descriptor.rx, height: descriptor.ry) {
            calibration.origin = appMaps
            if let origin = calibration.meanOrigin {
                aperture.centerX = origin.x
                aperture.centerY = origin.y
            }
            calibration.originProvenance = .sessionMaps
            restoredMaps = true
        }
        if !restoredMaps, let qx0 = saved.qx0Mean, let qy0 = saved.qy0Mean {
            calibration.origin = nil
            aperture.centerX = Float(qy0)
            aperture.centerY = Float(qx0)
            calibration.originProvenance = .sessionMean
        }
        if let q = saved.qSize, q > 0 {
            switch saved.qUnits?.lowercased() {
            case "1/nm", "nm^-1", "1/nanometer": acomScale = q * 0.1
            case "1/a", "1/å", "a^-1", "å^-1", "1/angstrom", "angstrom^-1":
                acomScale = q
            default: break
            }
        }
    }

    private func restoreSessionResult(
        from snapshot: SessionSidecarSnapshot, for descriptor: DatasetDescriptor
    ) {
        let url = resolvedSessionSidecarURL(for: descriptor)
            ?? BraggVectorEMDWriter.sessionSidecarURL(forSourcePath: descriptor.filePath)
        if let map = snapshot.currentResult {
            resultImage = FloatImage(width: map.width, height: map.height, pixels: map.pixels)
            resultRGBA = nil
            restoredResultInfo = (map.kind, map.displayName, map.valueUnits)
            restoredResultPixelInfo = (
                map.pixelSizeRow, map.pixelSizeColumn, map.pixelUnits, map.provenance
            )
        } else if let map = snapshot.currentRGBAResult {
            guard map.width == descriptor.rx, map.height == descriptor.ry else {
                statusText = "Ignored \(url.lastPathComponent): saved RGBA map is \(map.width) × \(map.height), expected \(descriptor.rx) × \(descriptor.ry)"
                return
            }
            resultImage = nil
            resultRGBA = RGBAImage(width: map.width, height: map.height, rgba: map.rgba)
            restoredResultInfo = (map.kind, map.displayName, map.valueUnits)
            restoredResultPixelInfo = nil
        } else {
            return
        }
        resultVersion &+= 1
        statusText = "Restored \(restoredResultInfo?.displayName ?? "result") ← \(url.lastPathComponent)"
    }

    private func loadCurrentPattern() async {
        guard let descriptor, let fourD else { return }

        do {
            let epoch = datasetEpoch
            let pattern = try await fourD.pattern(ry: selectedScan.y, rx: selectedScan.x)
            guard epoch == datasetEpoch else { return }
            currentPattern = pattern
            patternVersion &+= 1
            statusText = "Pattern x \(selectedScan.x), y \(selectedScan.y) from \(descriptor.fileName)"
            await detectCurrentPattern()
        } catch {
            present(error)
        }
    }

    // MARK: - Analyses

    /// Run the lightweight/default action for the current mode. Expensive
    /// whole-scan workflows remain explicit buttons in their tool sections.
    func runCurrentAnalysis() async {
        switch analysisMode {
        case .virtualDetector: await runVirtualDetector()
        case .dpc:             await runDPC()
        case .disks:
            // Live overlay on the current pattern; the full-scan pass is
            // explicit (Detect All Disks) because it's expensive.
            await detectCurrentPattern()
            if let bv = braggVectors, let d = descriptor { showBraggMap(bv, descriptor: d) }
        case .strain:
            // Strain is computed explicitly (needs a disk-detection pass);
            // just re-show it if already computed.
            if strainMap != nil { applyStrainDisplay() }
        case .ptychography:
            if let preview = parallaxAlignment?.previewImage
                ?? parallaxPreprocess?.previewImage {
                restoredResultInfo = nil
                resultImage = preview
                resultRGBA = nil
                resultVersion &+= 1
            }
        case .acom:
            if orientationMap != nil { applyACOMDisplay() }
        }
    }

    // Coalescing flags for live drag: at most one GPU pass / pattern load in
    // flight; the latest state is recomputed when it finishes (drop frames in
    // between so drags stay smooth without piling up work).
    @ObservationIgnored private var vdInFlight = false
    @ObservationIgnored private var vdPending = false
    @ObservationIgnored private var patternInFlight = false
    @ObservationIgnored private var patternPending = false
    @ObservationIgnored private var vdiffInFlight = false
    @ObservationIgnored private var vdiffPending = false

    /// Live aperture edit during a drag: store, then recompute the real-space
    /// image continuously (coalesced, quiet — no status/busy churn).
    func updateAperture(_ newAperture: Aperture) {
        activePane = .diffraction
        if newAperture.centerX != aperture.centerX || newAperture.centerY != aperture.centerY {
            // A manual center supersedes fitted per-position maps. Retaining
            // those maps would make export silently ignore the manual value.
            calibration.origin = nil
            calibration.originProvenance = .manual
            parallaxPreprocess = nil
            parallaxAlignment = nil
        }
        aperture = newAperture
        scheduleLiveVirtualDetector()
    }

    func setManualQPixelSize(_ value: Double) {
        parallaxPreprocess = nil
        parallaxAlignment = nil
        if value.isFinite && value > 0 {
            calibration.qPixelSize = value
            calibration.qPixelUnits = calibration.qPixelUnits ?? "1/nm"
            calibrationProvenance.qScale = .manual
            switch calibration.qPixelUnits?.lowercased() {
            case "1/nm", "nm^-1", "1/nanometer": acomScale = value * 0.1
            case "1/a", "1/å", "a^-1", "å^-1", "1/angstrom", "angstrom^-1":
                acomScale = value
            default: break
            }
        } else {
            calibration.qPixelSize = nil
            calibrationProvenance.qScale = nil
        }
    }

    func setManualRPixelSize(_ value: Double) {
        parallaxPreprocess = nil
        parallaxAlignment = nil
        if value.isFinite && value > 0 {
            calibration.rPixelSize = value
            calibration.rPixelUnits = calibration.rPixelUnits ?? "nm"
            calibrationProvenance.rScale = .manual
        } else {
            calibration.rPixelSize = nil
            calibrationProvenance.rScale = nil
        }
    }

    func setManualAcceleratingVoltage(_ value: Double) {
        parallaxPreprocess = nil
        parallaxAlignment = nil
        acceleratingVoltage = value.isFinite && value > 0 ? value : nil
    }

    private func scheduleLiveVirtualDetector() {
        guard analysisMode == .virtualDetector else { return }
        if vdInFlight { vdPending = true; return }
        vdInFlight = true
        Task {
            await runVirtualDetector(quiet: true)
            vdInFlight = false
            if vdPending { vdPending = false; scheduleLiveVirtualDetector() }
        }
    }

    func commitApertureChange() {
        guard analysisMode == .virtualDetector else { return }
        Task { await runVirtualDetector() }   // final pass, with status
    }

    /// Live scan-position scrub (drag in the real-space image). A point ROI
    /// streams the single pattern; a region ROI streams the summed pattern.
    func scrubTo(x: Int, y: Int) {
        guard let d = descriptor else { return }
        activePane = .realSpace
        let clamped = ScanPos(x: min(max(0, x), d.rx - 1), y: min(max(0, y), d.ry - 1))
        if clamped != selectedScan { selectedScan = clamped }
        if realSpaceShape == .point {
            scheduleLoadPattern()
        } else {
            scheduleVirtualDiffraction()
        }
    }

    /// Re-run whichever real-space product matches the current region shape
    /// (called when the shape or radius changes).
    func updateRealSpaceRegion() {
        activePane = .realSpace
        if realSpaceShape == .point {
            virtualDiffractionPattern = nil
            patternVersion &+= 1
            scheduleLoadPattern()
        } else {
            scheduleVirtualDiffraction()
        }
    }

    private func scheduleLoadPattern() {
        if patternInFlight { patternPending = true; return }
        patternInFlight = true
        Task {
            await loadCurrentPattern()
            patternInFlight = false
            if patternPending { patternPending = false; scheduleLoadPattern() }
        }
    }

    private func scheduleVirtualDiffraction() {
        if vdiffInFlight { vdiffPending = true; return }
        vdiffInFlight = true
        Task {
            await computeVirtualDiffraction()
            vdiffInFlight = false
            if vdiffPending { vdiffPending = false; scheduleVirtualDiffraction() }
        }
    }

    /// Sum the patterns over the current real-space region into the CBED pane.
    private func computeVirtualDiffraction() async {
        guard let fourD, let d = descriptor, realSpaceShape != .point else { return }
        let region = realSpaceRegionShape(d)
        do {
            let epoch = datasetEpoch
            let pattern = try await VirtualDetector.tiledDiffraction(
                data: fourD, descriptor: d, region: region
            )
            guard epoch == datasetEpoch else { return }
            virtualDiffractionPattern = pattern
            patternVersion &+= 1
            await detectCurrentPattern()
        } catch {
            // Quiet during live drag.
        }
    }

    /// The current real-space region as a scan-space DetectorShape (centered on
    /// the selected scan position).
    private func realSpaceRegionShape(_ d: DatasetDescriptor) -> DetectorShape {
        let r = Int(realSpaceRadius.rounded())
        switch realSpaceShape {
        case .point:
            return .point(x: selectedScan.x, y: selectedScan.y)
        case .rectangle:
            return .rectangle(xMin: selectedScan.x - r, xMax: selectedScan.x + r + 1,
                              yMin: selectedScan.y - r, yMax: selectedScan.y + r + 1)
        case .circle:
            return .circle(centerX: Float(selectedScan.x) + 0.5,
                           centerY: Float(selectedScan.y) + 0.5,
                           radius: realSpaceRadius + 0.5)
        }
    }

    /// Boolean scan mask sharing the point/rectangle/circle semantics of the
    /// visible real-space ROI. Used as the unstrained strain reference.
    private func realSpaceRegionMask(_ d: DatasetDescriptor) -> [Bool] {
        let r = Int(realSpaceRadius.rounded())
        let circleRadius = realSpaceRadius + 0.5
        let circleRadius2 = circleRadius * circleRadius
        var mask = [Bool](repeating: false, count: d.ry * d.rx)
        for y in 0..<d.ry {
            for x in 0..<d.rx {
                let included: Bool
                switch realSpaceShape {
                case .point:
                    included = x == selectedScan.x && y == selectedScan.y
                case .rectangle:
                    included = abs(x - selectedScan.x) <= r && abs(y - selectedScan.y) <= r
                case .circle:
                    let dx = Float(x - selectedScan.x)
                    let dy = Float(y - selectedScan.y)
                    included = dx * dx + dy * dy < circleRadius2
                }
                mask[y * d.rx + x] = included
            }
        }
        return mask
    }

    /// Apply a standard detector geometry (BF/ADF/HAADF) and recompute.
    func applyDetectorPreset(_ preset: DetectorPreset) {
        guard let descriptor else { return }
        let qMax = Float(min(descriptor.qx, descriptor.qy)) / 2
        if let radii = preset.radii(maxRadius: qMax) {
            aperture.inner = radii.inner
            aperture.outer = radii.outer
            virtualShape = preset == .brightField ? .circle : .annulus
        }
        if analysisMode != .virtualDetector { analysisMode = .virtualDetector }
        Task { await runVirtualDetector() }
    }

    /// Virtual-detector imaging over the whole cube. The annulus uses the
    /// analytic fast path; rectangle/point use the general mask kernel. The
    /// blocking GPU call is pushed off the main actor.
    func runVirtualDetector(quiet: Bool = false) async {
        guard let fourD, let descriptor else { return }
        let cancellation = quiet ? nil : beginCancellableOperation(
            "Virtual detector", status: "Computing virtual detector…",
            totalUnits: descriptor.rx * descriptor.ry
        )
        defer {
            if let cancellation { finishCancellableOperation(cancellation) }
        }

        let ap = aperture
        let shapeMode = virtualShape
        let d = descriptor
        do {
            let epoch = datasetEpoch
            if cancellation?.isCancelled == true {
                statusText = "Virtual detector cancelled"
                return
            }
            let progressUpdate: (@Sendable (Double) -> Void)?
            if let token = cancellation {
                progressUpdate = { @Sendable [weak self] fraction in
                    Task { @MainActor [weak self] in
                        guard let self, self.isCurrentOperation(token) else { return }
                        self.progress = fraction
                        self.statusText = "Computing virtual detector… \(Int(fraction * 100)) %"
                    }
                }
            } else {
                progressUpdate = nil
            }
            let image: FloatImage
            switch shapeMode {
            case .circle:
                image = try await VirtualDetector.tiledImage(
                    data: fourD, descriptor: d,
                    shape: .circle(centerX: ap.centerX, centerY: ap.centerY,
                                   radius: ap.outer),
                    cancellation: cancellation, progress: progressUpdate)
            case .annulus:
                image = try await VirtualDetector.tiledRun(
                    data: fourD, descriptor: d, aperture: ap,
                    cancellation: cancellation, progress: progressUpdate)
            case .rectangle:
                let half = Int(ap.outer.rounded())
                image = try await VirtualDetector.tiledImage(
                    data: fourD, descriptor: d,
                    shape: .rectangle(
                        xMin: Int(ap.centerX.rounded()) - half,
                        xMax: Int(ap.centerX.rounded()) + half,
                        yMin: Int(ap.centerY.rounded()) - half,
                        yMax: Int(ap.centerY.rounded()) + half),
                    cancellation: cancellation, progress: progressUpdate)
            case .point:
                image = try await VirtualDetector.tiledImage(
                    data: fourD, descriptor: d,
                    shape: .point(x: Int(ap.centerX.rounded()),
                                  y: Int(ap.centerY.rounded())),
                    cancellation: cancellation, progress: progressUpdate)
            }
            guard epoch == datasetEpoch else { return }
            if cancellation?.isCancelled == true {
                statusText = "Virtual detector cancelled"
                return
            }
            restoredResultInfo = nil
            resultImage = image
            resultRGBA = nil
            resultVersion &+= 1
            if !quiet {
                statusText = "Virtual detector ✓  (\(shapeMode.rawValue), \(d.rx) × \(d.ry))"
            }
        } catch {
            if cancellation?.isCancelled == true { statusText = "Virtual detector cancelled" }
            else if !quiet { present(error) }
        }
    }

    // MARK: - Calibration

    /// First parallax slice: build and preview py4DSTEM's normalized virtual-BF
    /// stack and incoherent BF initialization. No iterative reconstruction is
    /// performed or implied by this operation.
    func prepareParallaxPreview() async {
        guard let source = reader, let descriptor else { return }
        let physical: ParallaxPhysicalCalibration
        do {
            physical = try ParallaxPhysicalCalibration.resolve(
                calibration: calibration,
                apertureCenterX: aperture.centerX,
                apertureCenterY: aperture.centerY,
                acceleratingVoltageKV: acceleratingVoltage
            )
        } catch {
            present(error)
            return
        }

        let epoch = datasetEpoch
        let token = beginCancellableOperation(
            "Parallax preprocessing", status: "Preparing virtual-BF stack…",
            totalUnits: descriptor.ry * 2
        )
        defer { finishCancellableOperation(token) }
        do {
            let progressUpdate: @Sendable (Double) -> Void = { [weak self] fraction in
                Task { @MainActor [weak self] in
                    self?.updateCancellableOperation(
                        token, progress: fraction,
                        status: "Preparing virtual-BF stack… \(Int(fraction * 100)) %"
                    )
                }
            }
            let result = try await ParallaxPreprocessor.run(
                source: source, descriptor: descriptor, calibration: physical,
                cancellation: token, progress: progressUpdate
            )
            guard isCurrentOperation(token), datasetEpoch == epoch,
                  !token.isCancelled else { return }
            parallaxPreprocess = result
            parallaxAlignment = nil
            parallaxResultProduct = .preprocess
            restoredResultInfo = nil
            resultImage = result.previewImage
            resultRGBA = nil
            resultGamma = 1
            displayRangeLo = 0
            displayRangeHi = 1
            resultVersion &+= 1
            statusText = String(
                format: "Parallax preprocessing ✓  %d BF pixels · λ %.5f Å · %.2f mrad max · error %.4f",
                result.brightFieldPixelCount,
                result.calibration.wavelengthAngstrom,
                result.maximumProbeAngleMrad,
                result.initialError
            )
        } catch ParallaxPreprocessor.PreprocessError.cancelled {
            guard isCurrentOperation(token) else { return }
            statusText = "Parallax preprocessing cancelled"
        } catch {
            guard isCurrentOperation(token), datasetEpoch == epoch else { return }
            present(error)
        }
    }

    /// Run the next source-locked coarse-to-fine bin with factor-8 matrix-DFT
    /// correlation. The last completed level remains published until the next
    /// one succeeds and passes the operation/dataset publication guards.
    func alignParallaxNextLevel() async {
        guard let preprocessing = parallaxPreprocess else {
            present(SimpleError("Prepare the parallax preview before alignment."))
            return
        }
        let schedule = ParallaxAligner.defaultBinSchedule(
            detectorIndices: preprocessing.detectorIndices
        )
        guard !schedule.isEmpty else {
            present(SimpleError("The bright-field mask cannot form an alignment level."))
            return
        }
        let completed = parallaxAlignment?.completedBins ?? []
        guard completed.count < schedule.count else {
            present(ParallaxAligner.AlignmentError.alignmentComplete)
            return
        }
        let bin = schedule[completed.count]
        guard parallaxAlignment == nil
                || Array(schedule.prefix(completed.count)) == completed else {
            present(SimpleError("Reset the stale parallax alignment before continuing."))
            return
        }
        let groups = ParallaxAligner.groups(
            detectorIndices: preprocessing.detectorIndices, alignmentBin: bin
        )
        let epoch = datasetEpoch
        let token = beginCancellableOperation(
            "Parallax alignment bin \(bin)",
            status: "Aligning bin \(bin) virtual-BF groups…",
            totalUnits: groups.count + preprocessing.brightFieldPixelCount
        )
        defer { finishCancellableOperation(token) }
        do {
            let progressUpdate: @Sendable (Double) -> Void = { [weak self] fraction in
                Task { @MainActor [weak self] in
                    self?.updateCancellableOperation(
                        token, progress: fraction,
                        status: "Aligning bin \(bin) virtual-BF groups… \(Int(fraction * 100)) %"
                    )
                }
            }
            var options = ParallaxAlignmentOptions()
            options.upsampleFactor = 8
            let prior = parallaxAlignment
            let result = try await Task.detached(priority: .userInitiated) {
                try ParallaxAligner.alignNextLevel(
                    preprocessing: preprocessing, previous: prior, options: options,
                    cancellation: token, progress: progressUpdate
                )
            }.value
            guard isCurrentOperation(token), datasetEpoch == epoch,
                  !token.isCancelled else { return }
            parallaxAlignment = result
            parallaxResultProduct = .alignment
            restoredResultInfo = nil
            resultImage = result.previewImage
            resultRGBA = nil
            resultGamma = 1
            displayRangeLo = 0
            displayRangeHi = 1
            resultVersion &+= 1
            statusText = String(
                format: "Parallax alignment ✓  level %d/%d · bin %d · %d groups · %.2f px max shift · error %.4f → %.4f%@",
                result.completedBins.count, result.alignmentSchedule.count,
                result.alignmentBin, result.groups.count,
                result.maximumShiftPixels,
                result.errorHistory.dropLast().last ?? .nan,
                result.currentError,
                result.isComplete ? " · schedule complete" : ""
            )
        } catch ParallaxAligner.AlignmentError.cancelled {
            guard isCurrentOperation(token) else { return }
            statusText = "Parallax alignment bin \(bin) cancelled; last completed level retained"
        } catch {
            guard isCurrentOperation(token), datasetEpoch == epoch else { return }
            present(error)
        }
    }

    func resetParallaxAlignment() {
        guard !isBusy, let preprocessing = parallaxPreprocess else { return }
        parallaxAlignment = nil
        parallaxResultProduct = .preprocess
        restoredResultInfo = nil
        resultImage = preprocessing.previewImage
        resultRGBA = nil
        resultGamma = 1
        displayRangeLo = 0
        displayRangeHi = 1
        resultVersion &+= 1
        statusText = "Parallax alignment reset to the preprocessed preview"
    }

    func fitParallaxAberrations() {
        guard let preprocessing = parallaxPreprocess,
              let alignment = parallaxAlignment else {
            present(SimpleError("Complete parallax preprocessing and alignment first."))
            return
        }
        do {
            let result = try ParallaxAberrationFitter.fitHigherOrder(
                preprocessing: preprocessing, alignment: alignment
            )
            parallaxAberrationFit = result.lowOrder
            parallaxHigherOrderFit = result
            statusText = String(
                format: "Recursive aberration fit ✓  %d terms · rotation %.2f° · RMS %.4f Å → %.4f Å",
                result.terms.count,
                result.lowOrder.rotationRad * 180 / .pi,
                result.lowOrder.rmsResidualAngstrom,
                result.rmsResidualAngstrom
            )
        } catch {
            present(error)
        }
    }

    func upsampleParallaxBF() async {
        guard let preprocessing = parallaxPreprocess,
              let alignment = parallaxAlignment, alignment.isComplete else {
            present(SimpleError("Complete parallax alignment before KDE upsampling."))
            return
        }
        let epoch = datasetEpoch
        let token = beginCancellableOperation(
            "Parallax KDE", status: "Upsampling aligned virtual-BF images…",
            totalUnits: preprocessing.brightFieldPixelCount
        )
        defer { finishCancellableOperation(token) }
        do {
            var options = ParallaxSubpixelOptions()
            options.upsampleFactor = parallaxKDEUpsampleFactor > 0
                ? parallaxKDEUpsampleFactor : nil
            options.kdeSigmaPixels = parallaxKDESigmaPixels
            options.lowpassFilter = parallaxKDELowpass
            options.lanczosOrder = parallaxKDELanczosOrder > 0
                ? parallaxKDELanczosOrder : nil
            options.positionCorrectionIterations = parallaxPositionCorrectionIterations > 0
                ? parallaxPositionCorrectionIterations : nil
            options.positionCorrectionCheckerboard = parallaxPositionCorrectionCheckerboard
            let progressUpdate: @Sendable (Double) -> Void = { [weak self] fraction in
                Task { @MainActor [weak self] in
                    self?.updateCancellableOperation(
                        token, progress: fraction,
                        status: "Upsampling aligned virtual-BF images… \(Int(fraction * 100)) %"
                    )
                }
            }
            let result = try await Task.detached(priority: .userInitiated) {
                try ParallaxSubpixelReconstructor.reconstruct(
                    preprocessing: preprocessing, alignment: alignment,
                    options: options, cancellation: token, progress: progressUpdate
                )
            }.value
            guard isCurrentOperation(token), datasetEpoch == epoch,
                  !token.isCancelled else { return }
            parallaxSubpixel = result
            parallaxResultProduct = .subpixel
            restoredResultInfo = nil
            resultImage = result.croppedBF
            resultRGBA = nil
            resultGamma = 1
            displayRangeLo = 0
            displayRangeHi = 1
            resultVersion &+= 1
            statusText = String(
                format: "Parallax KDE ✓  ×%.2f · %.4f Å/px · %d × %d%@",
                result.upsampleFactor, result.outputSamplingAngstrom,
                result.croppedBF.height, result.croppedBF.width,
                result.positionCorrectionScores.isEmpty
                    ? "" : " · position corrected"
            )
        } catch ParallaxSubpixelReconstructor.ReconstructionError.cancelled {
            guard isCurrentOperation(token) else { return }
            statusText = "Parallax KDE cancelled; aligned result retained"
        } catch {
            guard isCurrentOperation(token), datasetEpoch == epoch else { return }
            present(error)
        }
    }

    func computeParallaxDepthSections() async {
        guard let preprocessing = parallaxPreprocess,
              let alignment = parallaxAlignment,
              let fit = parallaxHigherOrderFit else {
            present(SimpleError("Fit parallax aberrations before depth sectioning."))
            return
        }
        guard parallaxDepthPlaneCount > 0, parallaxDepthPlaneCount <= 257,
              parallaxDepthStartAngstrom.isFinite,
              parallaxDepthEndAngstrom.isFinite else {
            present(SimpleError("Use 1–257 finite parallax depth planes."))
            return
        }
        let depths: [Double]
        if parallaxDepthPlaneCount == 1 {
            depths = [parallaxDepthStartAngstrom]
        } else {
            depths = (0..<parallaxDepthPlaneCount).map { index in
                parallaxDepthStartAngstrom
                    + (parallaxDepthEndAngstrom - parallaxDepthStartAngstrom)
                    * Double(index) / Double(parallaxDepthPlaneCount - 1)
            }
        }
        var options = ParallaxDepthOptions()
        options.depthsAngstrom = depths
        options.useFullFit = parallaxDepthUseFullFit
        options.informationLimitInvAngstrom = parallaxDepthInformationLimit > 0
            ? parallaxDepthInformationLimit : nil
        options.informationPower = parallaxDepthInformationPower
        let epoch = datasetEpoch
        let token = beginCancellableOperation(
            "Parallax depth sectioning", status: "Computing depth planes…",
            totalUnits: depths.count
        )
        defer { finishCancellableOperation(token) }
        do {
            let progressUpdate: @Sendable (Double) -> Void = { [weak self] fraction in
                Task { @MainActor [weak self] in
                    self?.updateCancellableOperation(
                        token, progress: fraction,
                        status: "Computing depth planes… \(Int(fraction * 100)) %"
                    )
                }
            }
            let result = try await Task.detached(priority: .userInitiated) {
                try ParallaxDepthSectioner.section(
                    preprocessing: preprocessing, alignment: alignment, fit: fit,
                    options: options, cancellation: token, progress: progressUpdate
                )
            }.value
            guard isCurrentOperation(token), datasetEpoch == epoch,
                  !token.isCancelled else { return }
            parallaxDepth = result
            parallaxDepthSelectedIndex = depths.indices.min {
                abs(depths[$0]) < abs(depths[$1])
            } ?? 0
            showParallaxProduct(.depth)
            statusText = "Parallax depth sectioning ✓  \(depths.count) planes"
        } catch ParallaxDepthSectioner.DepthError.cancelled {
            guard isCurrentOperation(token) else { return }
            statusText = "Parallax depth sectioning cancelled; prior products retained"
        } catch {
            guard isCurrentOperation(token), datasetEpoch == epoch else { return }
            present(error)
        }
    }

    func runSingleslicePtychography() async {
        guard let source = reader, let descriptor else {
            present(SimpleError("Open a 4D dataset before ptychographic reconstruction."))
            return
        }
        let physical: ParallaxPhysicalCalibration
        do {
            physical = try ParallaxPhysicalCalibration.resolve(
                calibration: calibration, apertureCenterX: aperture.centerX,
                apertureCenterY: aperture.centerY,
                acceleratingVoltageKV: acceleratingVoltage
            )
        } catch {
            present(error)
            return
        }
        let epoch = datasetEpoch
        let token = beginCancellableOperation(
            "Single-slice ptychography", status: "Preparing diffraction amplitudes…",
            totalUnits: descriptor.ry + max(1, ptychographyIterations)
        )
        defer { finishCancellableOperation(token) }
        do {
            let prepareProgress: @Sendable (Double) -> Void = { [weak self] fraction in
                Task { @MainActor [weak self] in
                    self?.updateCancellableOperation(
                        token, progress: fraction * 0.3,
                        status: "Preparing diffraction amplitudes… \(Int(fraction * 100)) %"
                    )
                }
            }
            let input = try await PtychographyPreparer.prepare(
                source: source, descriptor: descriptor, calibration: physical,
                probeRadiusPixels: aperture.outer, cancellation: token,
                progress: prepareProgress
            )
            var options = SingleslicePtychographyOptions()
            options.iterations = ptychographyIterations
            options.stepSize = ptychographyStepSize
            options.normalizationMinimum = ptychographyNormalizationMinimum
            options.fixProbe = ptychographyFixProbe
            options.constrainObjectAmplitude = ptychographyConstrainObjectAmplitude
            options.purePhaseObject = ptychographyPurePhaseObject
            options.fixProbeCenterOfMass = ptychographyFixProbeCenterOfMass
            options.constrainProbeAmplitude = ptychographyConstrainProbeAmplitude
            options.probeAmplitudeRelativeRadius = ptychographyProbeAmplitudeRadius
            options.probeAmplitudeRelativeWidth = ptychographyProbeAmplitudeWidth
            let reconstructProgress: @Sendable (Double) -> Void = { [weak self] fraction in
                Task { @MainActor [weak self] in
                    self?.updateCancellableOperation(
                        token, progress: 0.3 + fraction * 0.7,
                        status: "Reconstructing object/probe… \(Int(fraction * 100)) %"
                    )
                }
            }
            let result = try await Task.detached(priority: .userInitiated) {
                try SingleslicePtychography.reconstruct(
                    input: input, options: options, cancellation: token,
                    progress: reconstructProgress
                )
            }.value
            guard isCurrentOperation(token), datasetEpoch == epoch,
                  !token.isCancelled else { return }
            singleslicePtychography = result
            showParallaxProduct(.iterativePhase)
            statusText = String(
                format: "Single-slice ptychography ✓  %d iterations · error %.6f",
                result.errorHistory.count, result.errorHistory.last ?? .nan
            )
        } catch SingleslicePtychography.ReconstructionError.cancelled {
            guard isCurrentOperation(token) else { return }
            statusText = "Single-slice ptychography cancelled; prior result retained"
        } catch {
            guard isCurrentOperation(token), datasetEpoch == epoch else { return }
            present(error)
        }
    }

    var availableParallaxProducts: [ParallaxResultProduct] {
        ParallaxResultProduct.allCases.filter {
            switch $0 {
            case .preprocess: parallaxPreprocess != nil
            case .alignment: parallaxAlignment != nil
            case .subpixel: parallaxSubpixel != nil
            case .correctedPhase: parallaxCorrection != nil
            case .depth: parallaxDepth != nil
            case .iterativePhase, .iterativeAmplitude,
                 .iterativeProbePhase, .iterativeProbeAmplitude:
                singleslicePtychography != nil
            }
        }
    }

    func showParallaxProduct(_ product: ParallaxResultProduct) {
        let image: FloatImage?
        switch product {
        case .preprocess: image = parallaxPreprocess?.previewImage
        case .alignment: image = parallaxAlignment?.previewImage
        case .subpixel: image = parallaxSubpixel?.croppedBF
        case .correctedPhase: image = parallaxCorrection?.correctedPhase
        case .depth: image = parallaxDepth?.croppedPlane(at: parallaxDepthSelectedIndex)
        case .iterativePhase: image = singleslicePtychography?.objectPhase()
        case .iterativeAmplitude: image = singleslicePtychography?.objectAmplitude()
        case .iterativeProbePhase: image = singleslicePtychography?.probePhase()
        case .iterativeProbeAmplitude: image = singleslicePtychography?.probeAmplitude()
        }
        guard let image else { return }
        parallaxResultProduct = product
        restoredResultInfo = nil
        resultImage = image
        resultRGBA = nil
        resultGamma = 1
        displayRangeLo = 0
        displayRangeHi = 1
        resultVersion &+= 1
    }

    func selectParallaxDepthPlane(_ index: Int) {
        guard let depth = parallaxDepth, depth.depthsAngstrom.indices.contains(index) else {
            return
        }
        parallaxDepthSelectedIndex = index
        showParallaxProduct(.depth)
    }

    func correctParallaxPhase() async {
        guard let preprocessing = parallaxPreprocess,
              let alignment = parallaxAlignment,
              let fit = parallaxHigherOrderFit else {
            present(SimpleError("Fit parallax aberrations before phase correction."))
            return
        }
        let epoch = datasetEpoch
        let token = beginCancellableOperation(
            "Parallax phase correction", status: "Applying aberration CTF…",
            totalUnits: alignment.stackHeight
        )
        defer { finishCancellableOperation(token) }
        do {
            var options = ParallaxAberrationCorrectionOptions()
            options.qLowpassInvAngstrom = parallaxQLowpassInvAngstrom != 0
                ? parallaxQLowpassInvAngstrom : nil
            options.qHighpassInvAngstrom = parallaxQHighpassInvAngstrom != 0
                ? parallaxQHighpassInvAngstrom : nil
            let result = try await Task.detached(priority: .userInitiated) {
                try ParallaxAberrationCorrector.correct(
                    preprocessing: preprocessing, alignment: alignment,
                    fit: fit, options: options, cancellation: token
                )
            }.value
            guard isCurrentOperation(token), datasetEpoch == epoch,
                  !token.isCancelled else { return }
            parallaxCorrection = result
            parallaxResultProduct = .correctedPhase
            restoredResultInfo = nil
            resultImage = result.correctedPhase
            resultRGBA = nil
            resultGamma = 1
            displayRangeLo = 0
            displayRangeHi = 1
            resultVersion &+= 1
            statusText = "Parallax phase correction ✓  full fitted CTF · DC removed"
        } catch ParallaxAberrationCorrector.CorrectionError.cancelled {
            guard isCurrentOperation(token) else { return }
            statusText = "Parallax phase correction cancelled; fit retained"
        } catch {
            guard isCurrentOperation(token), datasetEpoch == epoch else { return }
            present(error)
        }
    }

    /// Compute just the mean/max diffraction patterns (py4DSTEM get_dp_mean /
    /// get_dp_max) so the Mean/Max display modes work without running the
    /// full origin calibration.
    func computeDPStatistics() async {
        guard let fourD, let descriptor else { return }
        let cancellation = beginCancellableOperation(
            "DP statistics", status: "Computing DP mean/max…",
            totalUnits: descriptor.rx * descriptor.ry
        )
        defer { finishCancellableOperation(cancellation) }

        let d = descriptor
        do {
            let epoch = datasetEpoch
            let statistics = try await VirtualDetector.tiledDPStatistics(
                data: fourD, descriptor: d, cancellation: cancellation
            ) { [weak self] fraction in
                Task { @MainActor [weak self] in
                    guard let self, self.isCurrentOperation(cancellation) else { return }
                    self.progress = fraction
                    self.statusText = "Computing DP mean/max… \(Int(fraction * 100)) %"
                }
            }
            let (maxDP, meanDP) = statistics
            guard epoch == datasetEpoch else { return }
            if cancellation.isCancelled {
                statusText = "DP statistics cancelled"
                return
            }
            meanPattern = DiffractionPattern(qy: d.qy, qx: d.qx, pixels: meanDP)
            maxPattern = DiffractionPattern(qy: d.qy, qx: d.qx, pixels: maxDP)
            patternVersion &+= 1
            statusText = "DP statistics ✓  (mean + max over \(d.rx) × \(d.ry) positions)"
        } catch {
            if cancellation.isCancelled { statusText = "DP statistics cancelled" }
            else { present(error) }
        }
    }

    /// Origin calibration (py4DSTEM get_origin + fit_origin): max pattern →
    /// probe size → per-pattern beam position → smooth fit. Also fills the
    /// mean/max pattern display modes as a side effect.
    func calibrateOrigin() async {
        guard let fourD, let descriptor else { return }
        let cancellation = beginCancellableOperation(
            "Origin calibration", status: "Calibrating origin…",
            totalUnits: descriptor.rx * descriptor.ry
        )
        defer { finishCancellableOperation(cancellation) }

        let fitFn = originFitFunction
        let d = descriptor
        do {
            let epoch = datasetEpoch
            let result = try await OriginCalibration.tiledRun(
                data: fourD, descriptor: d, fitFunction: fitFn,
                cancellation: cancellation
            ) { [weak self] fraction in
                Task { @MainActor [weak self] in
                    guard let self, self.isCurrentOperation(cancellation) else { return }
                    self.progress = fraction
                    self.statusText = "Calibrating origin… \(Int(fraction * 100)) %"
                }
            }
            guard epoch == datasetEpoch else { return }
            if cancellation.isCancelled {
                statusText = "Origin calibration cancelled"
                return
            }
            guard let result else { return }

            calibration.probeRadius = result.probeRadius
            calibrationProvenance.probe = .measuredInApp
            calibration.origin = result.origin
            parallaxPreprocess = nil
            parallaxAlignment = nil
            meanPattern = DiffractionPattern(qy: d.qy, qx: d.qx, pixels: result.meanDP)
            maxPattern = DiffractionPattern(qy: d.qy, qx: d.qx, pixels: result.maxDP)
            patternVersion &+= 1

            // Recenter the aperture on the measured beam.
            if let origin = calibration.meanOrigin {
                aperture.centerX = origin.x
                aperture.centerY = origin.y
                calibration.originProvenance = .fitted
            }
            let rms = result.origin.rmsResidual ?? 0
            statusText = String(format: "Origin ✓  r ≈ %.1f px, fit RMS %.3f px (%@)",
                                result.probeRadius, rms, fitFn.rawValue)

            await runCurrentAnalysis()
        } catch {
            if cancellation.isCancelled { statusText = "Origin calibration cancelled" }
            else { present(error) }
        }
    }

    /// Fit py4DSTEM-native `(a,b,theta)` from the detector-shaped Bragg map
    /// when one is visible, otherwise from the scan-mean diffraction pattern.
    /// The fitter owns the qx=row/qy=column convention; this method performs
    /// the single app x/y swap at its boundary.
    func calibrateEllipse() async {
        guard let descriptor else { return }
        let detectorPattern: DiffractionPattern
        let sourceName: String
        if analysisMode == .disks, let image = resultImage,
           image.width == descriptor.qx, image.height == descriptor.qy {
            detectorPattern = DiffractionPattern(
                qy: descriptor.qy, qx: descriptor.qx, pixels: image.pixels
            )
            sourceName = "Bragg-vector map"
        } else {
            if meanPattern == nil { await computeDPStatistics() }
            guard let meanPattern else {
                present(SimpleError("Compute a mean diffraction pattern before fitting ellipse distortion."))
                return
            }
            detectorPattern = meanPattern
            sourceName = "mean diffraction pattern"
        }
        guard ellipseFitInnerRadius >= 0,
              ellipseFitOuterRadius > ellipseFitInnerRadius else {
            present(SimpleError("Ellipse fit outer radius must be larger than its inner radius."))
            return
        }

        let centerQX = Double(aperture.centerY)
        let centerQY = Double(aperture.centerX)
        let inner = ellipseFitInnerRadius
        let outer = ellipseFitOuterRadius
        let epoch = datasetEpoch
        let cancellation = beginCancellableOperation(
            "Ellipse calibration", status: "Fitting detector ellipse…", totalUnits: 1
        )
        defer { finishCancellableOperation(cancellation) }
        do {
            let fit = try await Task.detached(priority: .userInitiated) {
                try EllipseCalibration.fit1D(
                    pattern: detectorPattern,
                    centerQX: centerQX, centerQY: centerQY,
                    innerRadius: inner, outerRadius: outer
                )
            }.value
            guard epoch == datasetEpoch, !cancellation.isCancelled else {
                statusText = "Ellipse calibration cancelled"
                return
            }
            calibration.ellipseA = fit.a
            calibration.ellipseB = fit.b
            calibration.ellipseTheta = fit.theta
            calibrationProvenance.ellipse = .measuredInApp
            lastEllipseFit = fit
            progress = 1

            // A displayed Bragg map can be reprojected immediately because
            // raw peak storage remains unchanged. Strain/ACOM are deliberately
            // not relabeled; users rerun those quantitative analyses.
            if analysisMode == .disks, let vectors = braggVectors {
                showBraggMap(vectors, descriptor: descriptor)
            }
            statusText = String(
                format: "Ellipse ✓  a %.2f · b %.2f · θ %.1f° · residual %.3f (%@)",
                fit.a, fit.b, fit.theta * 180 / .pi,
                fit.normalizedResidual, sourceName
            )
        } catch {
            if cancellation.isCancelled { statusText = "Ellipse calibration cancelled" }
            else { present(error) }
        }
    }

    /// R–Q rotation calibration: find the rotation (and detector transpose)
    /// that makes the CoM field curl-free. Runs origin calibration first if
    /// needed — the solver wants the descan-corrected field.
    func calibrateRotation(maximizeDivergence: Bool = false) async {
        guard let descriptor else { return }

        if !calibration.hasFittedOrigin {
            await calibrateOrigin()
            guard calibration.hasFittedOrigin else { return }
        }

        let cancellation = beginCancellableOperation(
            "R–Q rotation", status: "Calibrating R–Q rotation…",
            totalUnits: descriptor.rx * descriptor.ry
        )
        defer { finishCancellableOperation(cancellation) }

        let d = descriptor
        do {
            let epoch = datasetEpoch
            guard let com = try await computeCoMField(cancellation: cancellation) else {
                if cancellation.isCancelled { statusText = "R–Q rotation cancelled" }
                return
            }
            let result = await Task.detached(priority: .userInitiated) {
                RotationCalibration.solve(com: com, width: d.rx, height: d.ry,
                                          maximizeDivergence: maximizeDivergence,
                                          cancellation: cancellation)
            }.value
            guard epoch == datasetEpoch else { return }
            if cancellation.isCancelled {
                statusText = "R–Q rotation cancelled"
                return
            }
            guard let result else {
                present(SimpleError("Scan is too small for rotation calibration (need at least 3 × 3 positions)."))
                return
            }
            calibration.rotationRad = result.rotationRad
            calibration.transposeQR = result.transpose
            calibrationProvenance.rotation = .measuredInApp
            parallaxPreprocess = nil
            parallaxAlignment = nil
            lastRotationResult = result
            applyDPCDisplay()   // a cached CoM field must not show a stale rotation
            statusText = String(format: "Rotation ✓  θ = %.1f°%@",
                                result.rotationRad * 180 / .pi,
                                result.transpose ? ", detector transposed" : "")
        } catch {
            if cancellation.isCancelled { statusText = "R–Q rotation cancelled" }
            else { present(error) }
        }
    }

    /// Measure the CoM shift field on the GPU, against calibrated origins when
    /// available. Shared by rotation calibration and (later) DPC.
    private func computeCoMField(
        cancellation: AnalysisCancellationToken? = nil
    ) async throws -> [Float]? {
        guard cancellation?.isCancelled != true else { return nil }
        guard let fourD, let descriptor else { return nil }
        let origins = calibration.origin?.interleavedFitted
        let center = calibration.meanOrigin ?? (x: aperture.centerX, y: aperture.centerY)
        let d = descriptor
        let result = try await VirtualDetector.tiledCenterOfMass(
            data: fourD, descriptor: d, center: center, origins: origins,
            cancellation: cancellation
        ) { [weak self] fraction in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let cancellation, !self.isCurrentOperation(cancellation) { return }
                self.progress = fraction
            }
        }
        return cancellation?.isCancelled == true ? nil : result
    }

    // MARK: - DPC

    /// Measure the CoM field (against calibrated origins) and cache it, then
    /// render the selected DPC view. The field is cached so switching between
    /// magnitude / angle / color-wheel / iDPC is instant (no GPU re-run).
    func runDPC() async {
        guard let descriptor else { return }
        let cancellation = beginCancellableOperation(
            "DPC", status: "Computing DPC (center of mass)…",
            totalUnits: descriptor.rx * descriptor.ry
        )
        defer { finishCancellableOperation(cancellation) }

        do {
            let epoch = datasetEpoch
            let field = try await computeCoMField(cancellation: cancellation)
            guard epoch == datasetEpoch else { return }
            if cancellation.isCancelled {
                statusText = "DPC cancelled"
                return
            }
            comField = field
            applyDPCDisplay()
            let ref = calibration.hasFittedOrigin ? "calibrated origins" : "global center"
            statusText = "DPC ✓  (\(dpcDisplay.rawValue) vs \(ref))"
        } catch {
            if cancellation.isCancelled { statusText = "DPC cancelled" }
            else { present(error) }
        }
    }

    /// Flip the calibrated R–Q rotation by 180° — the curl/divergence solver
    /// is blind to this (flipping both CoM components leaves both invariant),
    /// so inverted iDPC contrast is fixed here, by hand.
    func flipRotation180() {
        guard var rotation = calibration.rotationRad else { return }
        rotation += .pi
        if rotation > .pi { rotation -= 2 * .pi }
        calibration.rotationRad = rotation
        calibrationProvenance.rotation = .manual
        parallaxPreprocess = nil
        parallaxAlignment = nil
        applyDPCDisplay()
        statusText = String(format: "Rotation flipped → θ = %.1f°", rotation * 180 / .pi)
    }

    /// Derive the displayed image from the cached CoM field per `dpcDisplay`.
    /// The calibrated R–Q rotation/transpose is applied first so the field is
    /// in the scan frame. Cheap enough (scan-sized) to run on the main actor.
    private func applyDPCDisplay() {
        guard var com = comField, let d = descriptor, analysisMode == .dpc else { return }
        restoredResultInfo = nil
        if let rotation = calibration.rotationRad {
            com = DPC.applyRotation(com: com, rotationRad: rotation,
                                    transpose: calibration.transposeQR ?? false)
        }
        switch dpcDisplay {
        case .magnitude:
            resultImage = DPC.magnitudeImage(com: com, width: d.rx, height: d.ry)
            resultRGBA = nil
        case .magnitudeMrad:
            if let scale = dpcMilliradiansPerDetectorPixel {
                resultImage = DPC.physicalMagnitudeImage(
                    com: com, width: d.rx, height: d.ry,
                    milliradiansPerPixel: scale
                )
            } else {
                resultImage = DPC.magnitudeImage(com: com, width: d.rx, height: d.ry)
            }
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

    var dpcMilliradiansPerDetectorPixel: Float? {
        guard let voltageKV = acceleratingVoltage,
              let qSize = calibration.qPixelSize else { return nil }
        let invAngstrom: Double
        switch calibration.qPixelUnits?.lowercased() {
        case "1/nm", "nm^-1", "1/nanometer": invAngstrom = qSize * 0.1
        case "1/a", "1/å", "a^-1", "å^-1", "1/angstrom", "angstrom^-1":
            invAngstrom = qSize
        default: return nil
        }
        return DPC.milliradiansPerDetectorPixel(
            voltageKV: voltageKV, invAngstromPerPixel: invAngstrom
        )
    }

    // MARK: - Disk detection

    /// Build the synthetic probe kernel from the calibrated probe radius,
    /// running origin calibration first if needed.
    func generateProbeKernel() async {
        guard let descriptor else { return }
        if calibration.probeRadius == nil {
            await calibrateOrigin()
            guard calibration.probeRadius != nil else { return }
        }
        guard let radius = calibration.probeRadius else { return }

        guard let kernel = ProbeKernel.synthetic(radius: radius, qy: descriptor.qy, qx: descriptor.qx) else {
            present(SimpleError("Could not build a probe kernel (radius \(radius) px)."))
            return
        }
        probeKernel = kernel
        statusText = String(format: "Probe kernel ✓  r = %.1f px, trench %.0f–%.0f px",
                            radius, kernel.trenchRadii.inner, kernel.trenchRadii.outer)
        await detectCurrentPattern()
    }

    /// Build a measured kernel from the CBED currently displayed. With a
    /// rectangle/circle real-space ROI this is its summed vacuum pattern;
    /// normalization makes sum versus mean immaterial.
    func generateMeasuredProbeKernel() async {
        guard descriptor != nil, let pattern = displayedPattern else { return }
        if calibration.probeRadius == nil {
            await calibrateOrigin()
            guard calibration.probeRadius != nil else { return }
        }
        guard let radius = calibration.probeRadius else { return }
        let origin = calibration.meanOrigin
            ?? (x: aperture.centerX, y: aperture.centerY)
        guard let kernel = ProbeKernel.measured(
            pattern: pattern, originX: origin.x, originY: origin.y, radius: radius
        ) else {
            present(SimpleError("The current CBED/ROI did not contain a usable measured probe."))
            return
        }
        probeKernel = kernel
        statusText = String(
            format: "Measured probe kernel ✓  r = %.1f px from current CBED/ROI", radius
        )
        await detectCurrentPattern()
    }

    /// Live overlay: detect disks in the currently displayed pattern only.
    func detectCurrentPattern() async {
        liveDetectionRequest &+= 1
        let request = liveDetectionRequest
        guard analysisMode == .disks, let kernel = probeKernel,
              let pattern = displayedPattern else {
            if !currentPeaks.isEmpty { currentPeaks = [] }
            return
        }
        let params = diskParams
        let epoch = datasetEpoch
        let peaks = await Task.detached(priority: .userInitiated) { () -> [BraggPeak] in
            guard let detector = DiskDetector(kernel: kernel) else { return [] }
            return detector.detect(pattern: pattern.pixels, params: params)
        }.value
        guard epoch == datasetEpoch,
              request == liveDetectionRequest,
              analysisMode == .disks else { return }
        currentPeaks = peaks
    }

    /// Full-scan detection → BraggVectors + Bragg vector map.
    func runDiskDetection() async {
        guard let fourD, let descriptor else { return }
        if probeKernel == nil { await generateProbeKernel() }
        guard let kernel = probeKernel else { return }

        let cancellation = beginCancellableOperation(
            "Disk detection", status: "Detecting Bragg disks…",
            totalUnits: descriptor.rx * descriptor.ry
        )
        defer { finishCancellableOperation(cancellation) }

        let params = diskParams
        let d = descriptor
        do {
            let epoch = datasetEpoch
            let vectors = await DiskDetection.detectAll(
                data: fourD, descriptor: d, kernel: kernel,
                params: params, cancellation: cancellation
            ) { [weak self] fraction in
                Task { @MainActor [weak self] in
                    guard let self,
                          self.isCurrentOperation(cancellation),
                          !cancellation.isCancelled else { return }
                    self.progress = fraction
                    self.statusText = "Detecting Bragg disks… \(Int(fraction * 100)) %"
                }
            }
            guard epoch == datasetEpoch else { return }
            if cancellation.isCancelled {
                statusText = "Disk detection cancelled"
                return
            }
            guard let vectors else {
                present(SimpleError("Disk detection failed to initialize its FFT plan."))
                return
            }
            braggVectors = vectors
            braggPeakCount = vectors.totalPeakCount
            showBraggMap(vectors, descriptor: d)
            statusText = "Disks ✓  \(vectors.totalPeakCount) peaks (\(params.subpixel.rawValue) subpixel)"
        }
    }

    /// Show the Bragg vector map (log-scaled — the central beam dominates the
    /// raw histogram) in the result pane.
    private func showBraggMap(_ vectors: BraggVectors, descriptor d: DatasetDescriptor) {
        let calibrated = calibratedBraggVectors(vectors, descriptor: d).vectors
        let bvm = calibrated.map(qy: d.qy, qx: d.qx)
        restoredResultInfo = nil
        resultImage = FloatImage(width: bvm.width, height: bvm.height,
                                 pixels: bvm.pixels.map { log10(1 + max($0, 0)) })
        resultRGBA = nil
        resultVersion &+= 1
    }

    /// Raw peaks remain the source of truth; analysis calibration is derived
    /// on demand so imported or newly fitted origin/ellipse values immediately
    /// affect Bragg maps, strain, and ACOM without re-running detection.
    private func calibratedBraggVectors(
        _ vectors: BraggVectors,
        descriptor d: DatasetDescriptor
    ) -> (vectors: BraggVectors, origin: (x: Float, y: Float)) {
        let origin = calibration.meanOrigin
            ?? (x: Float(d.qx) / 2, y: Float(d.qy) / 2)
        return (vectors.calibrated(with: calibration, referenceOrigin: origin), origin)
    }

    // MARK: - Strain mapping

    /// Compute a strain map from the detected Bragg vectors (needs a prior
    /// disk-detection pass). Auto-picks reference lattice vectors and uses the
    /// scan-mean lattice as the unstrained reference.
    func runStrainMapping() async {
        guard let descriptor else { return }
        guard let bragg = braggVectors else {
            present(SimpleError("Run disk detection first — strain mapping needs detected Bragg peaks."))
            return
        }
        let cancellation = beginCancellableOperation(
            "Strain mapping", status: "Computing strain map…",
            totalUnits: descriptor.rx * descriptor.ry
        )
        defer { finishCancellableOperation(cancellation) }

        let calibrated = calibratedBraggVectors(bragg, descriptor: descriptor)
        let origin = calibrated.origin
        let referenceMask = strainReferenceMode == .selectedRegion
            ? realSpaceRegionMask(descriptor) : nil
        let initialBasis = strainBasisMode == .manual
            ? (g1: (x: strainG1X, y: strainG1Y),
               g2: (x: strainG2X, y: strainG2Y)) : nil
        let epoch = datasetEpoch
        let map = await Task.detached(priority: .userInitiated) {
            StrainMapping.compute(bragg: calibrated.vectors,
                                  originX: origin.x, originY: origin.y,
                                  referenceMask: referenceMask,
                                  initialBasis: initialBasis,
                                  cancellation: cancellation)
        }.value
        guard epoch == datasetEpoch else { return }
        if cancellation.isCancelled {
            statusText = "Strain mapping cancelled"
            return
        }
        guard let map else {
            present(SimpleError("Could not establish a lattice basis from the detected peaks (try detecting more disks)."))
            return
        }
        strainMap = map
        if strainBasisMode == .automatic {
            strainG1X = map.refG1.x; strainG1Y = map.refG1.y
            strainG2X = map.refG2.x; strainG2Y = map.refG2.y
        }
        colormap = .rdbu   // diverging colormap is the right default for strain
        applyStrainDisplay()
        statusText = String(format: "Strain ✓  %.0f%% indexed · %d ref positions · g1=(%.1f, %.1f) g2=(%.1f, %.1f)",
                            map.indexedFraction * 100,
                            map.referencePositionCount,
                            map.refG1.x, map.refG1.y, map.refG2.x, map.refG2.y)
    }

    /// Show the selected strain component; masked positions read 0 (the center
    /// of the diverging colormap).
    private func applyStrainDisplay() {
        guard let map = strainMap, analysisMode == .strain else { return }
        restoredResultInfo = nil
        resultImage = map.component(strainComponent)
        resultRGBA = nil
        resultVersion &+= 1
    }

    // MARK: - ACOM (orientation mapping)

    /// Build the orientation-plan template library for the selected crystal.
    func calibrateQFromCrystal() async {
        guard let descriptor, let rawBragg = braggVectors else {
            present(SimpleError("Detect Bragg disks before calibrating reciprocal pixels."))
            return
        }
        let crystal = resolvedACOMCrystal
        let calibrated = calibratedBraggVectors(rawBragg, descriptor: descriptor)
        let epoch = datasetEpoch
        let estimate = await Task.detached(priority: .userInitiated) {
            guard let firstShell = crystal.reflections(kMax: 2.5).first?.gLength else {
                return nil as QCalibrationEstimate?
            }
            return KnownCrystalQCalibration.estimate(
                bragg: calibrated.vectors, origin: calibrated.origin,
                referenceRadiusInvAngstrom: firstShell
            )
        }.value
        guard epoch == datasetEpoch else { return }
        guard let estimate else {
            present(SimpleError("Could not identify a non-central first Bragg shell."))
            return
        }
        acomScale = estimate.invAngstromPerPixel
        calibration.qPixelSize = estimate.invAngstromPerPixel
        calibration.qPixelUnits = "Å⁻¹"
        calibrationProvenance.qScale = .measuredInApp
        parallaxPreprocess = nil
        parallaxAlignment = nil
        statusText = String(
            format: "Q calibration ✓  %.6f Å⁻¹/px · first shell %.2f px · %d positions",
            estimate.invAngstromPerPixel, estimate.observedRadiusPixels,
            estimate.sampleCount
        )
    }

    /// Build the orientation-plan template library for the selected crystal.
    func generateOrientationPlan() async {
        guard descriptor != nil else { return }
        let cancellation = beginCancellableOperation(
            "Orientation plan", status: "Generating orientation plan…",
            totalUnits: 400
        )
        defer { finishCancellableOperation(cancellation) }

        let crystal = resolvedACOMCrystal
        let missing = crystal.unsupportedElements
        guard missing.isEmpty else {
            present(SimpleError("No scattering factors for element(s) Z = "
                + missing.map(String.init).joined(separator: ", ")
                + " — structure factors would be wrong."))
            return
        }
        let epoch = datasetEpoch
        let plan = await Task.detached(priority: .userInitiated) {
            OrientationPlan.generate(crystal: crystal, kMax: 1.2, zoneAxisCount: 400,
                                     cancellation: cancellation)
        }.value
        guard epoch == datasetEpoch else { return }
        if cancellation.isCancelled {
            statusText = "Orientation-plan generation cancelled"
            return
        }
        guard let plan else {
            present(SimpleError("Could not generate an orientation plan."))
            return
        }
        orientationPlan = plan
        hasOrientationPlan = true
        let label = acomCrystal == .custom
            ? "\(ScatteringFactors.symbols[customZ] ?? "Z\(customZ)") \(customStructure.rawValue), a = \(String(format: "%.3f", customLatticeA)) Å"
            : acomCrystal.rawValue
        statusText = "Orientation plan ✓  \(plan.count) templates (\(label))"
    }

    /// Match every scan position's Bragg peaks against the plan (needs a prior
    /// disk-detection pass; builds the plan first if needed).
    func runACOM() async {
        guard let descriptor, let bragg = braggVectors else {
            present(SimpleError("Detect Bragg disks first (Disks mode), then run ACOM."))
            return
        }
        if orientationPlan == nil { await generateOrientationPlan() }
        guard let plan = orientationPlan else { return }

        let cancellation = beginCancellableOperation(
            "ACOM matching", status: "Matching orientations…",
            totalUnits: descriptor.rx * descriptor.ry
        )
        defer { finishCancellableOperation(cancellation) }

        let calibrated = calibratedBraggVectors(bragg, descriptor: descriptor)
        let origin = calibrated.origin
        let scale = acomScale
        let epoch = datasetEpoch
        let map = await Task.detached(priority: .userInitiated) { [self] in
            OrientationMatching.matchAll(bragg: calibrated.vectors, plan: plan,
                                         originX: origin.x, originY: origin.y,
                                         invAngstromPerPixel: scale,
                                         cancellation: cancellation) { fraction in
                Task { @MainActor [weak self] in
                    guard let self,
                          self.isCurrentOperation(cancellation),
                          !cancellation.isCancelled else { return }
                    self.progress = fraction
                    self.statusText = "Matching orientations… \(Int(fraction * 100)) %"
                }
            }
        }.value
        guard epoch == datasetEpoch else { return }
        if cancellation.isCancelled {
            statusText = "ACOM matching cancelled"
            return
        }
        guard let map else {
            present(SimpleError("ACOM matching failed to initialize."))
            return
        }
        orientationMap = map
        hasOrientationMap = true
        applyACOMDisplay()
        statusText = "ACOM ✓  matched \(descriptor.rx) × \(descriptor.ry) positions"
    }

    private func applyACOMDisplay() {
        guard let map = orientationMap, analysisMode == .acom else { return }
        restoredResultInfo = nil
        switch acomDisplay {
        case .ipfZ:
            resultImage = nil
            resultRGBA = map.ipfZImage
            resultVersion &+= 1
            return
        case .reliability: resultImage = map.reliabilityImage
        case .disorientation: resultImage = map.symmetryDisorientationImage
        case .score:       resultImage = map.scoreImage
        case .inPlane:     resultImage = map.inPlaneAngleImage
        case .phi1:        resultImage = map.phi1Image
        case .Phi:         resultImage = map.PhiImage
        case .phi2:        resultImage = map.phi2Image
        }
        resultRGBA = nil
        resultVersion &+= 1
    }
}

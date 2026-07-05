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
    case annulus = "Annulus"
    case rectangle = "Rectangle"
    case point = "Point"

    var id: String { rawValue }
}

enum DPCDisplayMode: String, CaseIterable, Identifiable {
    case magnitude = "Magnitude"
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
            || self == .strain || self == .acom
    }
}

/// Crystal presets offered for ACOM template generation.
enum CrystalChoice: String, CaseIterable, Identifiable {
    case gold      = "Gold (FCC)"
    case aluminum  = "Aluminium (FCC)"
    case nickel    = "Nickel (FCC)"
    case copper    = "Copper (FCC)"
    case iron      = "Iron (BCC)"
    case silicon   = "Silicon (diamond)"
    var id: String { rawValue }

    var crystal: Crystal {
        switch self {
        case .gold:     return .gold
        case .aluminum: return .aluminum
        case .nickel:   return .nickel
        case .copper:   return .copper
        case .iron:     return .iron
        case .silicon:  return .silicon
        }
    }
}

/// Which ACOM result map to display.
enum ACOMDisplayMode: String, CaseIterable, Identifiable {
    case reliability = "Reliability"
    case inPlane     = "In-plane angle"
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

@Observable
final class AppState {
    private var reader: H5Reader?
    private var fourD: FourDArray?
    private var openURL: URL?

    var datasets: [DatasetDescriptor] = []
    var descriptor: DatasetDescriptor?
    var selectedScan = ScanPos(x: 0, y: 0)
    var acceleratingVoltage: Double?

    var currentPattern: DiffractionPattern?
    var resultImage: FloatImage?
    var resultRGBA: RGBAImage?

    var meanPattern: DiffractionPattern?
    var maxPattern: DiffractionPattern?
    var patternDisplayMode: PatternDisplayMode = .current {
        didSet { patternVersion &+= 1 }
    }

    var calibration = Calibration()
    var originFitFunction: OriginFitFunction = .plane
    var patternVersion = 0
    var resultVersion = 0

    // DPC: cached CoM shift field so display-mode switches don't re-run the GPU.
    @ObservationIgnored private var comField: [Float]?

    // Disk detection state.
    var probeKernel: ProbeKernel?
    var currentPeaks: [BraggPeak] = []
    var braggPeakCount: Int?
    private(set) var braggVectors: BraggVectors?
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
    var analysisMode: AnalysisMode = .virtualDetector

    var isBusy = false
    var statusText = "No file loaded"
    var errorMessage: String?

    /// Fractional progress [0,1] of the running long operation, or nil when
    /// idle / indeterminate. Drives the performance panel's progress bar.
    var progress: Double?
    /// Short label of what's currently running (for the performance panel).
    var activeOperation: String?

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
                let descriptor = try await reader.describe(path: datasetPath)
                if !datasets.contains(where: { $0.datasetPath == descriptor.datasetPath }) {
                    datasets.append(descriptor)
                }
                await activate(descriptor: descriptor, reader: reader)
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

        let accessed = url.startAccessingSecurityScopedResource()
        openURL = accessed ? url : nil

        do {
            let reader = try H5Reader(path: url.path)
            let descriptor = try await reader.discoverPrimaryDataset()
            self.reader = reader
            datasets = [descriptor]
            await activate(descriptor: descriptor, reader: reader)
        } catch {
            present(error)
        }
    }

    private func activate(descriptor: DatasetDescriptor, reader: H5Reader) async {
        guard descriptor.is4D else {
            present(H5Error.unsupportedRank(descriptor.shape.count))
            return
        }

        self.descriptor = descriptor
        fourD = FourDArray(reader: reader, descriptor: descriptor)
        selectedScan = ScanPos(x: 0, y: 0)
        aperture = Aperture(
            centerX: Float(descriptor.qx) / 2,
            centerY: Float(descriptor.qy) / 2,
            inner: 0,
            outer: Float(min(descriptor.qx, descriptor.qy)) / 4
        )
        acceleratingVoltage = await reader.readDoubleAttribute("accelerating_voltage")
        calibration = Calibration()
        patternDisplayMode = .current
        meanPattern = nil
        maxPattern = nil
        resultImage = nil
        resultRGBA = nil
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

        await loadCurrentPattern()
        statusText = "Loaded \(descriptor.fileName) at \(descriptor.datasetPath)"
        await runCurrentAnalysis()
    }

    private func loadCurrentPattern() async {
        guard let descriptor, let fourD else { return }

        do {
            currentPattern = try await fourD.pattern(ry: selectedScan.y, rx: selectedScan.x)
            patternVersion &+= 1
            statusText = "Pattern x \(selectedScan.x), y \(selectedScan.y) from \(descriptor.fileName)"
            await detectCurrentPattern()
        } catch {
            present(error)
        }
    }

    // MARK: - Analyses

    /// Run whatever analysis the current mode calls for. Only the virtual
    /// detector is wired in this slice; DPC / disks arrive in later slices.
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
        case .acom:
            if orientationMap != nil { applyACOMDisplay() }
        default: break
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
        aperture = newAperture
        scheduleLiveVirtualDetector()
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
            let cube = try await fourD.cubeBuffer()
            let pattern = try await Task.detached(priority: .userInitiated) {
                try VirtualDetector.diffraction(cube: cube, descriptor: d, region: region)
            }.value
            virtualDiffractionPattern = pattern
            patternVersion &+= 1
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

    /// Apply a standard detector geometry (BF/ADF/HAADF) and recompute.
    func applyDetectorPreset(_ preset: DetectorPreset) {
        guard let descriptor else { return }
        let qMax = Float(min(descriptor.qx, descriptor.qy)) / 2
        if let radii = preset.radii(maxRadius: qMax) {
            aperture.centerX = Float(descriptor.qx) / 2
            aperture.centerY = Float(descriptor.qy) / 2
            aperture.inner = radii.inner
            aperture.outer = radii.outer
        }
        if analysisMode != .virtualDetector { analysisMode = .virtualDetector }
        Task { await runVirtualDetector() }
    }

    /// Virtual-detector imaging over the whole cube. The annulus uses the
    /// analytic fast path; rectangle/point use the general mask kernel. The
    /// blocking GPU call is pushed off the main actor.
    func runVirtualDetector(quiet: Bool = false) async {
        guard let fourD, let descriptor else { return }
        if !quiet {
            isBusy = true
            statusText = "Computing virtual detector…"
        }
        defer { if !quiet { isBusy = false } }

        let ap = aperture
        let shapeMode = virtualShape
        let d = descriptor
        do {
            let cube = try await fourD.cubeBuffer()
            let image = try await Task.detached(priority: .userInitiated) { () throws -> FloatImage in
                switch shapeMode {
                case .annulus:
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
            resultImage = image
            resultRGBA = nil
            resultVersion &+= 1
            if !quiet {
                statusText = "Virtual detector ✓  (\(shapeMode.rawValue), \(d.rx) × \(d.ry))"
            }
        } catch {
            if !quiet { present(error) }
        }
    }

    // MARK: - Calibration

    /// Origin calibration (py4DSTEM get_origin + fit_origin): max pattern →
    /// probe size → per-pattern beam position → smooth fit. Also fills the
    /// mean/max pattern display modes as a side effect.
    func calibrateOrigin() async {
        guard let fourD, let descriptor else { return }
        isBusy = true
        statusText = "Calibrating origin…"
        defer { isBusy = false }

        let fitFn = originFitFunction
        let d = descriptor
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
            if let origin = calibration.meanOrigin {
                aperture.centerX = origin.x
                aperture.centerY = origin.y
            }
            let rms = result.origin.rmsResidual
            statusText = String(format: "Origin ✓  r ≈ %.1f px, fit RMS %.3f px (%@)",
                                result.probeRadius, rms, fitFn.rawValue)

            await runCurrentAnalysis()
        } catch {
            present(error)
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

        isBusy = true
        statusText = "Calibrating R–Q rotation…"
        defer { isBusy = false }

        let d = descriptor
        do {
            guard let com = try await computeCoMField() else { return }
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
            statusText = String(format: "Rotation ✓  θ = %.1f°%@",
                                result.rotationRad * 180 / .pi,
                                result.transpose ? ", detector transposed" : "")
        } catch {
            present(error)
        }
    }

    /// Measure the CoM shift field on the GPU, against calibrated origins when
    /// available. Shared by rotation calibration and (later) DPC.
    private func computeCoMField() async throws -> [Float]? {
        guard let fourD, let descriptor else { return nil }
        let origins = calibration.origin?.interleavedFitted
        let center = calibration.meanOrigin ?? (x: aperture.centerX, y: aperture.centerY)
        let d = descriptor
        let cube = try await fourD.cubeBuffer()
        let params = CoMParams(ry: UInt32(d.ry), rx: UInt32(d.rx),
                               qy: UInt32(d.qy), qx: UInt32(d.qx),
                               cx: center.x, cy: center.y, useOrigins: 0)
        return try await Task.detached(priority: .userInitiated) {
            try MetalEngine.shared.centerOfMass(cube: cube, params: params, origins: origins)
        }.value
    }

    // MARK: - DPC

    /// Measure the CoM field (against calibrated origins) and cache it, then
    /// render the selected DPC view. The field is cached so switching between
    /// magnitude / angle / color-wheel / iDPC is instant (no GPU re-run).
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
    /// The calibrated R–Q rotation/transpose is applied first so the field is
    /// in the scan frame. Cheap enough (scan-sized) to run on the main actor.
    private func applyDPCDisplay() {
        guard var com = comField, let d = descriptor, analysisMode == .dpc else { return }
        if let rotation = calibration.rotationRad {
            com = DPC.applyRotation(com: com, rotationRad: rotation,
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

    /// Live overlay: detect disks in the currently displayed pattern only.
    func detectCurrentPattern() async {
        guard analysisMode == .disks, let kernel = probeKernel,
              let pattern = currentPattern else {
            if !currentPeaks.isEmpty { currentPeaks = [] }
            return
        }
        let params = diskParams
        let peaks = await Task.detached(priority: .userInitiated) { () -> [BraggPeak] in
            guard let detector = DiskDetector(kernel: kernel) else { return [] }
            return detector.detect(pattern: pattern.pixels, params: params)
        }.value
        currentPeaks = peaks
    }

    /// Full-scan detection → BraggVectors + Bragg vector map.
    func runDiskDetection() async {
        guard let fourD, let descriptor else { return }
        if probeKernel == nil { await generateProbeKernel() }
        guard let kernel = probeKernel else { return }

        isBusy = true
        activeOperation = "Disk detection"
        progress = 0
        statusText = "Detecting Bragg disks…"
        defer { isBusy = false; progress = nil; activeOperation = nil }

        let params = diskParams
        let d = descriptor
        do {
            let cube = try await fourD.cubeBuffer()
            let vectors = await Task.detached(priority: .userInitiated) { [weak self] () -> BraggVectors? in
                DiskDetection.detectAll(cube: cube, descriptor: d, kernel: kernel, params: params) { fraction in
                    Task { @MainActor in
                        self?.progress = fraction
                        self?.statusText = "Detecting Bragg disks… \(Int(fraction * 100)) %"
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
            statusText = "Disks ✓  \(vectors.totalPeakCount) peaks (\(params.subpixel.rawValue) subpixel)"
        } catch {
            present(error)
        }
    }

    /// Show the Bragg vector map (log-scaled — the central beam dominates the
    /// raw histogram) in the result pane.
    private func showBraggMap(_ vectors: BraggVectors, descriptor d: DatasetDescriptor) {
        let bvm = vectors.map(qy: d.qy, qx: d.qx)
        resultImage = FloatImage(width: bvm.width, height: bvm.height,
                                 pixels: bvm.pixels.map { log10(1 + max($0, 0)) })
        resultRGBA = nil
        resultVersion &+= 1
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
        isBusy = true
        statusText = "Computing strain map…"
        defer { isBusy = false }

        let origin = calibration.meanOrigin
            ?? (x: Float(descriptor.qx) / 2, y: Float(descriptor.qy) / 2)
        let map = await Task.detached(priority: .userInitiated) {
            StrainMapping.compute(bragg: bragg, originX: origin.x, originY: origin.y)
        }.value
        guard let map else {
            present(SimpleError("Could not establish a lattice basis from the detected peaks (try detecting more disks)."))
            return
        }
        strainMap = map
        colormap = .rdbu   // diverging colormap is the right default for strain
        applyStrainDisplay()
        statusText = String(format: "Strain ✓  %.0f%% indexed · g1=(%.1f, %.1f) g2=(%.1f, %.1f)",
                            map.indexedFraction * 100,
                            map.refG1.x, map.refG1.y, map.refG2.x, map.refG2.y)
    }

    /// Show the selected strain component; masked positions read 0 (the center
    /// of the diverging colormap).
    private func applyStrainDisplay() {
        guard let map = strainMap, analysisMode == .strain else { return }
        resultImage = map.component(strainComponent)
        resultRGBA = nil
        resultVersion &+= 1
    }

    // MARK: - ACOM (orientation mapping)

    /// Build the orientation-plan template library for the selected crystal.
    func generateOrientationPlan() async {
        guard descriptor != nil else { return }
        isBusy = true
        statusText = "Generating orientation plan…"
        defer { isBusy = false }

        let crystal = acomCrystal.crystal
        let plan = await Task.detached(priority: .userInitiated) {
            OrientationPlan.generate(crystal: crystal, kMax: 1.2, zoneAxisCount: 400)
        }.value
        guard let plan else {
            present(SimpleError("Could not generate an orientation plan."))
            return
        }
        orientationPlan = plan
        hasOrientationPlan = true
        statusText = "Orientation plan ✓  \(plan.count) templates (\(acomCrystal.rawValue))"
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

        isBusy = true
        activeOperation = "ACOM matching"
        progress = 0
        statusText = "Matching orientations…"
        defer { isBusy = false; progress = nil; activeOperation = nil }

        let origin = calibration.meanOrigin
            ?? (x: Float(descriptor.qx) / 2, y: Float(descriptor.qy) / 2)
        let scale = acomScale
        let map = await Task.detached(priority: .userInitiated) { [weak self] in
            OrientationMatching.matchAll(bragg: bragg, plan: plan,
                                         originX: origin.x, originY: origin.y,
                                         invAngstromPerPixel: scale) { fraction in
                Task { @MainActor in
                    self?.progress = fraction
                    self?.statusText = "Matching orientations… \(Int(fraction * 100)) %"
                }
            }
        }.value
        orientationMap = map
        hasOrientationMap = true
        applyACOMDisplay()
        statusText = "ACOM ✓  matched \(descriptor.rx) × \(descriptor.ry) positions"
    }

    private func applyACOMDisplay() {
        guard let map = orientationMap, analysisMode == .acom else { return }
        switch acomDisplay {
        case .reliability: resultImage = map.reliabilityImage
        case .score:       resultImage = map.scoreImage
        case .inPlane:     resultImage = map.inPlaneAngleImage
        }
        resultRGBA = nil
        resultVersion &+= 1
    }
}

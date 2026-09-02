import Foundation
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif

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

enum PatternDisplayMode: String, CaseIterable, Identifiable {
    case current = "Current"
    case mean = "Mean"
    case max = "Max"

    var id: String { rawValue }
}

enum PatternScaleUnit: String, CaseIterable, Identifiable {
    case reciprocal = "Reciprocal"
    case milliradians = "mrad"
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
    /// Parallax (the staged bright-field reconstruction). Raw value kept —
    /// it is written into export provenance as `analysis_mode`.
    case ptychography = "Ptycho"
    /// v2.5 step 7a (plan §11b): single-slice iterative ptychography is its
    /// own task — it needs the datacube and calibration, never a parallax stage.
    case singleslicePtychography = "Single-slice ptycho"
    case acom = "ACOM"

    var id: String { rawValue }
    var isAdvanced: Bool { self == .ptychography || self == .singleslicePtychography }
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

enum ComparisonSlot: Equatable { case a, b }

/// What one analysis entry point did — returned by the five run functions so
/// S6's replay executor learns the verdict from a typed value written at the
/// exit site, never by scraping a UI string that a copy edit could reword
/// (Gate A findings A1/A2/B6, 2026-08-25). Interactive call sites ignore it.
enum AnalysisRunOutcome: Equatable {
    /// The result published — the recipe-recording path, exactly.
    case published
    /// The user (or a dataset change) stopped it; deliberately distinct from
    /// `failed` so an overnight summary never calls a cancel a failure.
    case cancelled
    /// Ran and did not publish, with the reason in the app's voice.
    case failed(String)
}

@Observable
final class AppState {
    private var reader: (any FourDDataSource)?
    private var fourD: FourDArray?

    /// The loaded view — the source descriptor, the load specification, and the
    /// descriptor derived from both. Read-only, and deliberately not the array:
    /// every consumer that hands a shape to a reader needs the pairing, and
    /// exposing them separately is what let three readers ignore the descriptor.
    var loadView: LoadView? { fourD?.view }

    /// Whether the open cube is held in memory, and the preload's progress.
    /// Owned by its own type, with no forwarding properties on `AppState` —
    /// see `DatasetResidency.swift` for why. Views read `residency.…`.
    let residency = DatasetResidency()

    /// Which part of the source file is loaded, and what moving the calibration
    /// into that frame cost. Stage L3's seam — see `App/LoadedView.swift`.
    let loadedView = LoadedView()

    /// A strided sample of the open dataset, built during the open so there is
    /// something real on screen before the first whole-cube pass.
    ///
    /// **Not a result** (invariant I4). It is deliberately its own type, which
    /// no product, export or session path accepts, and every view that draws it
    /// must show `summary` — which states the stride.
    private(set) var datasetPreview: DatasetPreview?
    private var openURL: URL?
    @ObservationIgnored private var pendingRecovery: DatasetRecoveryRecord?
    /// S1's seam (docs/development-process.md §7): the one owner of where this
    /// dataset's session sidecar is and whether the app may read it. Replaces a
    /// bare `scopedSessionSidecarURL` that eight call sites derived around in
    /// two different ways — see `App/SessionSidecarLocator.swift`.
    ///
    /// Injectable for the S1 reason one level up (v2 S7): the locator persists
    /// bookmarks into `UserDefaults`, and the demo dataset's file path is a
    /// CONSTANT — so a test that saves a sidecar for the demo through the real
    /// defaults plants a grant every other demo-opening test (including one in
    /// a parallel worker PROCESS, which shares the persisted domain) then
    /// resolves, adopting that test's calibration and recipe as session state.
    /// Measured 2026-08-25: `.mixed` replay frames and `sessionSidecar`-stamped
    /// Q scales appearing in unrelated suites. Tests that publish sidecars
    /// must construct `AppState(sessionSidecar:)` with a suite-private store.
    let sessionSidecar: SessionSidecarLocator

    init(sessionSidecar: SessionSidecarLocator = SessionSidecarLocator()) {
        self.sessionSidecar = sessionSidecar
        // The seam signals presentation changes (component switches); the
        // displayed image is shared display state, so the derivation stays
        // here. Weak: AppState owns the seam, never the reverse.
        strain.onPresentationChange = { [weak self] in
            self?.applyStrainDisplay()
        }
        // Same ownership direction as the strain seam: AppState owns
        // navigation, never the reverse. This closure is the recovery
        // persist the old stored `navigation.analysisMode`'s didSet performed.
        // 7c 4b: the ACOM effects that need the window. The scope drives the
        // region selection on the real-space pane; display writes republish
        // the map; an invalidated map clears the published product.
        acomSession.onScopeChange = { [weak self] scope in
            guard let self else { return }
            if scope == .selectedRegion {
                acomSession.regionSelectionActive = true
                realSpaceShape = .rectangle
                realSpaceRadius = Float(acomSession.regionRadius)
                Task { await self.ensureScanNavigator() }
            } else {
                acomSession.regionSelectionActive = false
            }
        }
        acomSession.onRegionRadiusChange = { [weak self] radius in
            guard let self, acomSession.scope == .selectedRegion else { return }
            acomSession.regionSelectionActive = true
            realSpaceRadius = Float(radius)
        }
        acomSession.onDisplayChange = { [weak self] in self?.applyACOMDisplay() }
        acomSession.onResultInvalidated = { [weak self] in
            guard let self, navigation.analysisMode == .acom else { return }
            publishedProduct = nil
            resultVersion &+= 1
        }
        navigation.onModeChange = { [weak self] in
            self?.persistRecoveryPosition()
        }
    }

    var datasets: [DatasetDescriptor] = []

    /// The recents list and its location labels. S3's seam
    /// (docs/development-process.md §7) — see `App/RecentDatasets.swift`.
    /// Views read `recents.…`; no forwarding properties. // v2 S3
    let recents = RecentDatasets()
    /// The session's recipe — which analyses ran, with which parameters. S5's
    /// seam (docs/development-process.md §7) — see `App/SessionReplay.swift`.
    /// No forwarding properties. // v2 S5
    let replay = SessionReplay()
    /// The state of the unattended promote run — S6's seam
    /// (docs/development-process.md §7) — see `App/ReplayRun.swift`.
    /// Views read `replayRun.…`; no forwarding properties. // v2 S6
    let replayRun = ReplayRun()
    /// The session's "may I?" policy gates — S7's seam
    /// (docs/development-process.md §7) — see `App/SessionGates.swift`.
    /// Views read `gates.…`; no forwarding properties. // v2 S7
    let gates = SessionGates()
    /// The strain product and its run controls — S8's seam
    /// (docs/development-process.md §7) — see `App/StrainProduct.swift`.
    /// Views read `strain.…`; no forwarding properties. // v2 S8
    let strain = StrainProduct()
    /// The last reciprocal-pixel calibration attempt — S13's seam
    /// (docs/development-process.md §7) — see `App/QCalibrationRun.swift`.
    /// Views read `qCalibration.…`; no forwarding properties. // v2 S13
    let qCalibration = QCalibrationRun()

    /// The ONE entry for recipe steps. Recording is suppressed while a
    /// dataset load is in flight: the automatic re-establishing pass on open
    /// (and after a promote or reconfigure) runs with whatever parameters the
    /// fresh session holds — DEFAULTS — and recording it would overwrite an
    /// adopted colleague's step with them. Merely opening a file must never
    /// mutate its recipe (Gate B-lite refutation F1, 2026-08-24). // v2 S5
    ///
    /// Also suppressed when the run was replay-initiated (`replaying`, passed
    /// down from the executor through the entry point): replaying a recipe
    /// must not mutate the recipe. Without this, a replayed disk detection's
    /// `invalidating:` would DELETE the strain and ACOM steps mid-run, so a
    /// replay that halted between them would have destroyed the very recipe
    /// it was executing. Keyed on the CALLER, not on `replayRun.isRunning` —
    /// a user-initiated run that interleaves with the replay is a real
    /// pipeline edit and suppressing it would silently diverge the recipe
    /// from the published results (Gate A findings A4/B3, 2026-08-25). The
    /// recipe keeps its rehearsal values; what actually ran is the results'
    /// own provenance and the run summary. // v2 S6
    private func recordReplayStep(kind: String,
                                  parameters: [String: String],
                                  invalidating downstream: [String] = [],
                                  replaying: Bool) {
        guard !isLoadingDataset, !replaying else { return }
        replay.record(kind: kind, parameters: parameters, invalidating: downstream,
                      under: ReplayParameterFrame.of(loadedView.specification))
    }
    private(set) var recoveryRecord: DatasetRecoveryRecord? = WorkspaceRecoveryStore.recovery()
    var descriptor: DatasetDescriptor?
    var selectedScan = ScanPos(x: 0, y: 0)

    var currentPattern: DiffractionPattern?
    /// v2.5 step 3f: the pixels live in `publishedProduct`; these two are
    /// read-only views of its payload for the readers not yet on the product.
    /// Deletion condition: zero readers.
    var resultImage: FloatImage? {
        if case .scalar(let image)? = publishedProduct?.payload { return image } else { return nil }
    }
    var resultRGBA: RGBAImage? {
        if case .rgba(let rgba)? = publishedProduct?.payload { return rgba } else { return nil }
    }

    /// v2.5 step 3 (2026-09-03): the one authoritative result value — the
    /// only storage for result pixels since 3c. Set by every compute and
    /// restore site; `displayedProduct` returns it. `restoredResult*` stays
    /// until the product carries its own restored-from marker.
    var publishedProduct: DisplayedProduct?

    /// v2.5 step 3b-6: a result restored from the sidecar is published as the
    /// product value straight from the map's own metadata — the status and
    /// domain recorded at save time, never re-inferred from strings.
    func publishRestoredProduct(
        kind: String, displayName: String, valueUnits: String, payload: ProductPayload,
        pixelSizeRow: Double?, pixelSizeColumn: Double?, pixelUnits: String?,
        provenance: [String: String]
    ) {
        let domain = provenance["display_domain"].flatMap(ProductDomain.init) ?? activeResultDomain
        let status = provenance["quantitative_status"].flatMap(ProductQuantitativeStatus.init)
            ?? quantitativeStatus(for: kind, units: valueUnits)
        publishedProduct = DisplayedProduct(
            origin: .restoredFromSidecar,
            kind: kind, displayName: displayName, payload: payload, domain: domain,
            sampling: ProductSampling(row: pixelSizeRow, column: pixelSizeColumn, units: pixelUnits),
            valueUnits: valueUnits, quantitativeStatus: status, provenance: provenance)
    }

    /// v2.5 step 3e: a compute site publishes its product with ITS OWN
    /// kind/name/units — condition 2 of plan §9d, one site at a time. Sampling
    /// and provenance still come from the per-mode persistence metadata.
    func publishProduct(
        kind: String, displayName: String, valueUnits: String, payload: ProductPayload,
        validityMask: [Bool]? = nil, qualityFields: [ProductQualityField] = [],
        overlays: [ProductOverlayDescriptor] = []
    ) {
        let persisted = currentScalarPersistenceMetadata
        let domain = activeResultDomain
        var provenance = persisted.provenance
        provenance["display_domain"] = domain.rawValue
        let status = provenance["quantitative_status"].flatMap(ProductQuantitativeStatus.init)
            ?? quantitativeStatus(for: kind, units: valueUnits)
        provenance["quantitative_status"] = status.rawValue
        publishedProduct = DisplayedProduct(
            kind: kind, displayName: displayName, payload: payload, domain: domain,
            validityMask: validityMask, qualityFields: qualityFields,
            sampling: ProductSampling(row: persisted.row, column: persisted.column, units: persisted.units),
            valueUnits: valueUnits, quantitativeStatus: status, provenance: provenance,
            overlays: overlays)
        resultVersion &+= 1
    }

    /// Last structural scan-space image available for positioning regions.
    /// This is navigation context, not a scientific result: selecting an ACOM
    /// region must not replace the Bragg map/result that can still be saved.
    var scanNavigationImage: FloatImage?
    private(set) var scanNavigationVersion = 0
    /// Set only while `resultImage` is the scalar map restored from the stable
    /// session sidecar. New scientific results clear it at publication.
    /// Read-only inventory of supported objects in the stable companion file.
    var sessionInventory: SessionSidecarInventory = .empty
    var comparisonProductA: DisplayedProduct?
    var comparisonProductB: DisplayedProduct?

    var meanPattern: DiffractionPattern?
    var maxPattern: DiffractionPattern?
    var patternDisplayMode: PatternDisplayMode = .current {
        didSet {
            patternVersion &+= 1
            Task { await detectCurrentPattern() }
        }
    }

    /// v2.5 step 4a: calibration state lives in `CalibrationSession`. Every
    /// reader goes there directly; the forwarders went in 7c slice 5b.
    let calibrationSession = CalibrationSession()
    private(set) var parallaxPreprocess: ParallaxPreprocessResult?
    private(set) var parallaxAberrationFit: ParallaxAberrationFitResult?
    private(set) var parallaxCorrection: ParallaxAberrationCorrectionResult?
    private(set) var parallaxSubpixel: ParallaxSubpixelResult?
    private(set) var parallaxDepth: ParallaxDepthResult?
    private(set) var singleslicePtychography: SingleslicePtychographyResult?
    var ptychographyIterations = 8
    var ptychographyMethod: SingleslicePtychographyMethod = .gradientDescent
    var ptychographyStepSize: Float = 0.5
    var ptychographyProjectionParameter: Float = 1
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
    private(set) var currentDiskDiagnostics: DiskDetectionPatternDiagnostics?
    var braggPeakCount: Int?
    private(set) var braggVectors: BraggVectors?
    private(set) var completedDiskParams: DiskDetectionParams?
    private(set) var completedDiskSummary: DiskDetectionScanSummary?
    @ObservationIgnored private var liveDetectionRequest: UInt64 = 0
    var diskParams = DiskDetectionParams() {
        didSet { Task { await detectCurrentPattern() } }   // live overlay tracks params
    }

    /// Return every detector control to the same size-aware defaults used
    /// when this dataset was opened — now including the fitted probe radius if
    /// one has been measured since, which is what makes the minimum-spacing
    /// default physically meaningful.
    func resetDiskDetectionParams() {
        guard let descriptor else { return }
        diskParams = .detectorAdapted(
            qy: descriptor.qy, qx: descriptor.qx, probeRadius: fittedProbeRadius
        )
    }

    /// The probe radius to scale detector defaults with: the generated
    /// kernel's, else the calibration's. Same precedence `diskDetectionContext`
    /// uses, so the controls validate against the value they were derived from.
    private var fittedProbeRadius: Float? {
        probeKernel?.probeRadius ?? calibrationSession.calibration.probeRadius
    }

    /// Re-derive the disk-detection defaults once a probe radius is known.
    ///
    /// `diskParams` is seeded at dataset load, before any calibration has run,
    /// so its minimum spacing is the detector-scaled placeholder rather than a
    /// probe-scaled value. Measuring the probe is what makes the real default
    /// computable — see `DiskDetectionParams.detectorAdapted`, where the
    /// detector-scaled value is shown to suppress the shortest g-vectors on
    /// two of the four training datasets.
    ///
    /// Only replaces the spacing if the user has not chosen one: it is
    /// compared against the placeholder's spacing *alone*, not the whole
    /// parameter struct. Whole-struct equality looks safer and is worse — a
    /// user who raises Maximum peaks (a natural response to a doubled yield)
    /// or nudges any unrelated control would then be pinned to the
    /// detector-scaled spacing permanently, with nothing on screen saying why.
    func refreshDiskDefaultsForMeasuredProbe() {
        guard let descriptor, let radius = fittedProbeRadius,
              radius.isFinite, radius > 0 else { return }
        let placeholder = DiskDetectionParams.detectorAdapted(
            qy: descriptor.qy, qx: descriptor.qx, probeRadius: nil
        )
        guard diskParams.minPeakSpacing == placeholder.minPeakSpacing else { return }
        diskParams.minPeakSpacing = DiskDetectionParams.detectorAdapted(
            qy: descriptor.qy, qx: descriptor.qx, probeRadius: radius
        ).minPeakSpacing
    }

    var diskDetectionContext: DiskDetectionContext? {
        guard let descriptor else { return nil }
        return DiskDetectionContext(
            qy: descriptor.qy, qx: descriptor.qx,
            probeRadius: probeKernel?.probeRadius ?? calibrationSession.calibration.probeRadius
        )
    }

    var diskDetectionValidationIssues: [DiskDetectionValidationIssue] {
        guard let context = diskDetectionContext else { return [] }
        return diskParams.validationIssues(in: context)
    }

    var diskDetectionConfigurationIsValid: Bool {
        !diskDetectionValidationIssues.contains { $0.severity == .error }
    }

    /// Full-scan vectors remain available for comparison, but downstream
    /// analysis must not silently imply that newly previewed settings produced
    /// them.
    var diskDetectionSettingsAreStale: Bool {
        guard braggVectors != nil, let completedDiskParams else { return false }
        return completedDiskParams != diskParams
    }

    var hasCurrentBraggVectors: Bool {
        braggVectors != nil && !diskDetectionSettingsAreStale
    }

    /// ACOM state, plan and map live in `ACOMSession` (v2.5 step 6a); the
    /// forwarders went in 7c 4b. The run functions stay here by owner
    /// decision (2026-09-03) and read the session directly; the session's
    /// hooks below carry the effects that need the window.
    let acomSession = ACOMSession()
    @ObservationIgnored private var acomLastMeasuredTemplateCount: Int?
    @ObservationIgnored private var acomLastMeasuredBackend: ACOMMatchingBackend?

    /// Automatic is an explicit, inspectable policy rather than a claim that
    /// the GPU is active. Real-data benchmarking may revise this policy, but
    /// the UI always names the backend that will actually execute.
    var effectiveACOMBackend: ACOMMatchingBackend {
        acomSession.backend == .automatic ? .cpu : acomSession.backend
    }

    var acomBackendSummary: String {
        acomSession.backend == .automatic
            ? "Automatic · \(effectiveACOMBackend.rawValue)"
            : effectiveACOMBackend.rawValue
    }

    private var acomScanSelection: ACOMScanSelection {
        switch acomSession.scope {
        case .preview:
            return .preview(maxDimension: 32)
        case .selectedRegion:
            return .square(
                centerX: selectedScan.x, centerY: selectedScan.y,
                radius: acomSession.regionRadius
            )
        case .fullScan:
            return .full
        }
    }

    var acomWorkPositionCount: Int {
        guard let descriptor else { return 0 }
        return acomScanSelection.positionCount(width: descriptor.rx, height: descriptor.ry)
    }

    var acomWorkSummary: String {
        "\(acomWorkPositionCount.formatted()) positions × \(acomSession.quality.templateCount) templates"
    }

    var acomEstimatedDuration: TimeInterval? {
        acomEstimatedDuration(forPositions: acomWorkPositionCount)
    }

    /// What a full-scan run would cost, using the same throughput the panel
    /// already shows for the current scope — deliberately not a second
    /// estimator, so the suggestion cannot disagree with the "Expected" row.
    var acomFullScanEstimatedDuration: TimeInterval? {
        guard let descriptor else { return nil }
        return acomEstimatedDuration(
            forPositions: ACOMScanSelection.full.positionCount(
                width: descriptor.rx, height: descriptor.ry
            )
        )
    }

    private func acomEstimatedDuration(forPositions positions: Int) -> TimeInterval? {
        let templates = Double(acomSession.quality.templateCount)
        let throughput: Double
        if let measured = acomSession.lastPositionsPerSecond,
           let measuredTemplates = acomLastMeasuredTemplateCount,
           acomLastMeasuredBackend == effectiveACOMBackend {
            throughput = measured * Double(measuredTemplates) / templates
        } else if effectiveACOMBackend == .cpu {
            // Hands-on M3 Release baseline: 1,150 positions/s at 400 templates.
            throughput = 1_150 * 400 / templates
        } else {
            return nil
        }
        return Double(positions) / max(throughput, 1)
    }

    /// A full scan this cheap is offered as one click instead of leaving the
    /// user on a 32×32 preview. Measured motivation: sim_Au's full 84×100 scan
    /// against 200 templates ran in 0.7 s while the panel estimated ~2 s.
    ///
    /// 5 s is the ceiling because the run is already cancellable and reports
    /// progress, so the cost of accepting is bounded and visible; and the
    /// estimate is only offered at all once it is grounded (a measured
    /// throughput, or the CPU baseline), never on an unmeasured GPU guess.
    /// Only offered from `.preview` — a user who deliberately chose a region
    /// is not second-guessed.
    var acomFullScanSuggestion: String? {
        guard acomSession.scope == .preview,
              let seconds = acomFullScanEstimatedDuration,
              seconds <= 5
        else { return nil }
        return seconds < 1
            ? "Run the full scan instead — under 1 s"
            : "Run the full scan instead — about \(Int(seconds.rounded())) s"
    }

    var acomEstimatedDurationText: String {
        guard let seconds = acomEstimatedDuration else {
            return "Run a preview to measure"
        }
        if seconds < 1 { return "under 1 s" }
        let total = Int(seconds.rounded(.up))
        return total >= 60
            ? String(format: "about %d:%02d", total / 60, total % 60)
            : "about \(total) s"
    }

    var acomPrimaryActionTitle: String {
        switch acomSession.scope {
        case .preview: "Preview Orientation"
        case .selectedRegion: "Map Selected Region"
        case .fullScan: "Run Full Orientation Map"
        }
    }

    /// The analysis canvas temporarily shows a scan-space reference while a
    /// region is being positioned. Results still reads the retained scientific
    /// result, so the Bragg-vector map is never discarded or relabelled.
    var showsACOMRegionReference: Bool {
        navigation.workspaceArea == .map
            && navigation.analysisMode == .acom
            && acomSession.scope == .selectedRegion
            && acomSession.regionSelectionActive
            && scanNavigationImage != nil
    }

    var displayedResultImage: FloatImage? {
        showsACOMRegionReference ? scanNavigationImage : resultImage
    }

    var displayedResultRGBA: RGBAImage? {
        showsACOMRegionReference ? nil : resultRGBA
    }

    var displayedResultName: String {
        showsACOMRegionReference
            ? "Select ACOM region · real-space reference"
            : currentResultDisplayName
    }

    var displayedResultKind: String {
        showsACOMRegionReference ? "acom_region_reference" : currentResultKind
    }

    var displayedResultValueUnits: String {
        showsACOMRegionReference ? "intensity" : currentResultValueUnits
    }

    var displayedResultColormap: ColormapKind {
        showsACOMRegionReference ? .viridis : resultColormap
    }

    var displayedResultRangeLo: Float {
        showsACOMRegionReference ? 0 : displayRangeLo
    }

    var displayedResultRangeHi: Float {
        showsACOMRegionReference ? 1 : displayRangeHi
    }

    var displayedResultGamma: Float {
        showsACOMRegionReference ? 1 : resultGamma
    }

    var displayedResultVersion: Int {
        showsACOMRegionReference ? scanNavigationVersion : resultVersion
    }

    var displayedResultPixelMetadata:
        (row: Double?, column: Double?, units: String?, provenance: [String: String]) {
        if showsACOMRegionReference {
            return (
                calibrationSession.calibration.rPixelSize, calibrationSession.calibration.rPixelSize,
                calibrationSession.calibration.rPixelUnits, ["display_role": "acom_region_reference"]
            )
        }
        return currentResultPersistenceMetadata
    }

    /// The only semantic source used by result viewers and comparison/export
    /// workflows. Legacy scalar/RGBA slots remain as frozen-v1 adapters.
    var displayedProduct: DisplayedProduct? {
        if showsACOMRegionReference, let image = scanNavigationImage {
            return DisplayedProduct(
                kind: "acom_region_reference",
                displayName: "Select ACOM region · real-space reference",
                payload: .scalar(image), domain: .scan,
                sampling: ProductSampling(
                    row: calibrationSession.calibration.rPixelSize, column: calibrationSession.calibration.rPixelSize,
                    units: calibrationSession.calibration.rPixelUnits
                ),
                valueUnits: "intensity", quantitativeStatus: .relative,
                provenance: ["display_role": "acom_region_reference"]
            )
        }
        // A product published by its compute site is authoritative; the
        // legacy assembly below serves the analyses not yet migrated.
        if let product = publishedProduct { return product }
        guard let payload: ProductPayload = resultImage.map(ProductPayload.scalar)
                ?? resultRGBA.map(ProductPayload.rgba) else { return nil }
        let metadata = currentResultPersistenceMetadata
        let domain = activeResultDomain
        let status = metadata.provenance["quantitative_status"]
            .flatMap(ProductQuantitativeStatus.init)
            ?? quantitativeStatus(for: currentResultKind, units: currentResultValueUnits)
        var quality: [ProductQualityField] = []
        var overlays: [ProductOverlayDescriptor] = []
        var validity: [Bool]?
        if navigation.analysisMode == .strain, let map = strain.map,
           map.width == payload.dimensions.width, map.height == payload.dimensions.height {
            validity = map.mask
            quality = [
                ProductQualityField(
                    name: "fit residual", units: "detector_px",
                    image: FloatImage(width: map.width, height: map.height,
                                      pixels: map.localResidualPixels)
                ),
                ProductQualityField(
                    name: "indexed", units: "boolean",
                    image: FloatImage(width: map.width, height: map.height,
                                      pixels: map.mask.map { $0 ? 1 : 0 })
                ),
            ]
            overlays.append(ProductOverlayDescriptor(
                kind: "local_lattice_fit", provenance: "retained Bragg-vector least-squares fit"
            ))
        } else if navigation.analysisMode == .acom, let map = acomSession.orientationMap,
                  map.width == payload.dimensions.width, map.height == payload.dimensions.height {
            validity = map.results.map { $0.templateIndex >= 0 }
            quality = [
                ProductQualityField(name: "reliability", units: "dimensionless",
                                    image: map.reliabilityImage),
                ProductQualityField(name: "score", units: "dimensionless",
                                    image: map.scoreImage),
            ]
            overlays.append(ProductOverlayDescriptor(
                kind: "matched_template", provenance: "selected ACOM orientation template"
            ))
        }
        return DisplayedProduct(
            kind: currentResultKind, displayName: currentResultDisplayName,
            payload: payload, domain: domain, validityMask: validity,
            qualityFields: quality,
            sampling: ProductSampling(row: metadata.row, column: metadata.column,
                                      units: metadata.units),
            valueUnits: currentResultValueUnits, quantitativeStatus: status,
            provenance: metadata.provenance, overlays: overlays
        )
    }

    var activeResultDomain: ProductDomain {
        switch navigation.analysisMode {
        case .disks: .detector
        case .ptychography, .singleslicePtychography: .reconstruction
        case .virtualDetector, .dpc, .strain, .acom: .scan
        }
    }

    func quantitativeStatus(for kind: String, units: String)
        -> ProductQuantitativeStatus {
        if kind.hasPrefix("acom_") {
            return acomSession.lastRunSemantics?.productStatus(for: kind) ?? .exploratory
        }
        if kind == "dpc_color" || kind.contains("ipf") { return .categorical }
        if kind == "idpc_qualitative" || units.contains("intensity")
            || units.contains("arbitrary") || units.contains("log_") {
            return .relative
        }
        // Only named families are quantitative. An unknown kind — a future
        // writer, a foreign sidecar — must not inherit the strongest claim
        // (v2.5 step 3, negative control 2; docs/v2.5-plan.md §9e).
        let quantitativeFamilies = ["strain", "local_lattice", "dpc", "idpc",
                                    "virtual_detector", "disk_detection", "matched_template"]
        if quantitativeFamilies.contains(where: { kind == $0 || kind.hasPrefix($0 + "_") }) {
            return .quantitative
        }
        return .relative
    }

    /// Viewer-level quality inspection: shows the displayed product's paired
    /// quality field (strain ↔ fit residual, ACOM ↔ reliability) in the result
    /// viewer without touching the retained product, exports, or persistence.
    var inspectQualityField = false

    /// The quality field currently shown instead of the scientific map, when
    /// inspection is on and the displayed product carries one.
    var displayedQualityField: ProductQualityField? {
        guard inspectQualityField else { return nil }
        return displayedProduct?.qualityFields.first
    }

    var selectedEulerText: String? {
        guard let map = acomSession.orientationMap,
              selectedScan.x >= 0, selectedScan.x < map.width,
              selectedScan.y >= 0, selectedScan.y < map.height else { return nil }
        let result = map[selectedScan.x, selectedScan.y]
        guard result.templateIndex >= 0 else { return nil }
        let degrees = result.euler.degrees
        return String(format: "%.1f°, %.1f°, %.1f°", degrees.0, degrees.1, degrees.2)
    }

    /// Whether the real-space ROI must be drawn on the scan image.
    ///
    /// This is now simply "is an ROI in force", because `displayedPattern`
    /// substitutes the ROI-summed pattern for the current one whenever
    /// `realSpaceShape != .point` — in *every* task, not just the ones that
    /// nominally use a region.
    ///
    /// The old rule listed the tasks where an ROI was *intended* (virtual
    /// detector, strain-from-region, ACOM-from-region), which meant that after
    /// setting a rectangle in Image, Bragg disks and Strain kept showing a
    /// summed CBED while the scan image drew only a point crosshair. That is
    /// not cosmetic: the summed pattern is what "Use Current CBED / ROI" builds
    /// the probe kernel from and what the "Current CBED · N peaks" read-out
    /// counts, so an invisible ROI silently changed the science. Reported by
    /// the release owner 2026-08-05.
    var realSpaceROIIsRelevant: Bool { realSpaceShape != .point }

    /// The explicitly selected complete phase model — never a filename- or
    /// dataset-derived fallback.
    var resolvedACOMModel: CrystalModel? {
        let model: CrystalModel?
        switch acomSession.modelSelection {
        case .none:
            model = nil
        case .library(let id):
            model = CrystalModelLibrary.model(id: id)
        case .customCubic:
            model = CrystalModelLibrary.customCubic(
                structure: acomSession.customStructure,
                latticeA: acomSession.customLatticeA,
                atomicNumber: acomSession.customZ
            )
        case .imported(let id):
            model = acomSession.importedCrystalModels.first { $0.id == id }
        }
        guard let model, model.isUsable else { return nil }
        return model
    }

    var acomModelSelectionIssue: String? {
        switch acomSession.modelSelection {
        case .none:
            return "Choose the phase model used to generate orientation templates."
        case .library(let id):
            guard let model = CrystalModelLibrary.model(id: id) else {
                return "The selected phase model is no longer available."
            }
            return model.validationIssues.first?.message
        case .customCubic:
            let model = CrystalModelLibrary.customCubic(
                structure: acomSession.customStructure,
                latticeA: acomSession.customLatticeA,
                atomicNumber: acomSession.customZ
            )
            return model.validationIssues.first?.message
        case .imported(let id):
            guard let model = acomSession.importedCrystalModels.first(where: { $0.id == id }) else {
                // Reached only if a selection ever outlives its model within
                // one run (e.g. a future "clear imports" action) — reopening
                // the app never hits this, since `acomModelSelection` itself
                // resets to `.none` on every dataset (re)activation.
                return "The imported phase model is no longer available in this session — import the CIF again."
            }
            return model.validationIssues.first?.message
        }
    }

    var acomScaleSemantics: ACOMScaleSemantics {
        if let value = calibrationSession.calibration.qPixelSize {
            let wavelength = calibrationSession.acceleratingVoltage.flatMap {
                DPC.electronWavelengthAngstrom(voltageKV: $0)
            }
            if let physical = CalibrationUnitConversion.reciprocalInvAngstromPerPixel(
                value: value, units: calibrationSession.calibration.qPixelUnits,
                wavelengthAngstrom: wavelength
            ) {
                return ACOMScaleSemantics(
                    invAngstromPerPixel: physical,
                    provenance: ACOMQScaleProvenance(calibrationSession.provenance.qScale)
                )
            }
        }
        return ACOMScaleSemantics(
            invAngstromPerPixel: acomSession.exploratoryScale,
            provenance: .exploratory
        )
    }

    var acomScale: Double { acomScaleSemantics.invAngstromPerPixel }

    var acomInterpretationLabel: String {
        acomScaleSemantics.provenance.isPhysical
            ? "Physical matching"
            : "Exploratory matching"
    }

    /// v2.5 step 6: the IPF map's confidence gate. Nil = automatic, the 10th
    /// percentile of matched reliabilities; a number overrides it (the
    /// colorbar chip's slider, when it lands). Positions below it draw grey.
    var acomEffectiveReliabilityThreshold: Float? {
        acomSession.reliabilityThreshold ?? acomSession.orientationMap?.reliabilityThreshold(percentile: 0.1)
    }

    /// Presentation-only orientation of the real-space viewer (backlog #17b).
    /// The retained product, its scan indices, and the scientific bundle are
    /// unaffected; see `RealSpaceDisplayOrientation` for why quarter turns only
    /// and why this is never offered for the diffraction pane.
    var realSpaceDisplayOrientation: RealSpaceDisplayOrientation = .identity

    /// Display-only horizontal mirror, composed after the rotation.
    var realSpaceDisplayMirrored = false

    /// The orientation as it applies to whatever is on screen right now.
    /// Identity for anything that is not scan-domain, so a detector-domain
    /// product shown in the same viewer is never transformed.
    var effectiveRealSpaceDisplayOrientation: RealSpaceDisplayOrientation {
        displayedProduct?.domain == .scan ? realSpaceDisplayOrientation : .identity
    }

    var effectiveRealSpaceDisplayMirrored: Bool {
        displayedProduct?.domain == .scan ? realSpaceDisplayMirrored : false
    }

    var realSpaceDisplayIsDefault: Bool {
        effectiveRealSpaceDisplayOrientation == .identity && !effectiveRealSpaceDisplayMirrored
    }

    /// Provenance recorded on every export so a rotated figure is never an
    /// unrecorded one (ROADMAP P1.1). The publication PNG applies the
    /// orientation; the scientific bundle stays in scan-index order and carries
    /// these keys as metadata describing what the user was looking at.
    var realSpaceDisplayProvenance: [String: String] {
        [
            "display_rotation_deg":
                String(Int(effectiveRealSpaceDisplayOrientation.degrees)),
            "display_flip": effectiveRealSpaceDisplayMirrored ? "horizontal" : "none"
        ]
    }

    /// The picker's setter. Distinguishes a human choice from the programmatic
    /// default below, which `didSet` alone cannot.
    func selectACOMDisplay(_ mode: ACOMDisplayMode) {
        acomSession.displayIsUserChosen = true
        acomSession.display = mode
    }

    /// py4DSTEM's `plot_orientation_maps` leads with the IPF coloring, and it
    /// is the map a user following the tutorial came for; Reliability is the
    /// quality check, one click away. Promoted only when the crystal actually
    /// has a symmetry to color by — `.identity` has no fundamental zone, so an
    /// IPF key there would be a fabricated legend.
    private func promoteIPFZDisplayIfDefault(for map: OrientationMap) {
        guard !acomSession.displayIsUserChosen,
              acomSession.display == .reliability,
              map.symmetry != .identity
        else { return }
        acomSession.display = .ipfZ
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
    /// CBED and scientific products deliberately own separate color choices.
    /// A diverging strain map must never recolor the diffraction evidence.
    /// Draw fit-verification overlays (origin/ellipse, strain lattice,
    /// matched ACOM template) on the diffraction pane.
    var showFitOverlay = true
    var patternColormap: ColormapKind = .viridis {
        didSet { patternVersion &+= 1 }
    }
    var patternScaleUnit: PatternScaleUnit = .reciprocal
    /// mrad labelling needs both a physical Q calibration and the voltage.
    var patternScaleMradAvailable: Bool { dpcMilliradiansPerDetectorPixel != nil }
    var resultColormap: ColormapKind = .viridis {
        didSet { resultVersion &+= 1 }
    }
    var logScale = true {
        didSet { patternVersion &+= 1 }
    }
    /// Display contrast window for the diffraction pane. Kept independent of
    /// the real-space result window so adjusting a CBED never changes a map.
    var patternDisplayRangeLo: Float = 0
    var patternDisplayRangeHi: Float = 1
    var patternGamma: Float = 1
    /// Navigation/selection seam (S22c): workspace, task and pane visibility
    /// live on `navigation`; the recovery persist that the old `navigation.analysisMode`
    /// didSet performed is wired through `navigation.onModeChange` in `init`.
    let navigation = WorkspaceNavigation()

    /// v2.5 step 5b: owned by `OperationCenter`; forwarded for the readers.
    let operationCenter = OperationCenter()
    var isBusy: Bool { operationCenter.isBusy }
    var statusText = "No file loaded" {
        didSet { appendLog(statusText) }
    }
    var errorMessage: String?

    /// Rolling log of meaningful status events, shown in the output strip
    /// below the image panes. Progress spam ("… 42 %") is filtered out.
    private(set) var logMessages: [String] = []
    private(set) var openDatasetRequest = 0
    private(set) var preprocessingExportRequest = 0

    func requestOpenDataset() {
        configureOnOpen = false
        openDatasetRequest &+= 1
    }

    /// Open the picker, then stop at L5's configurator instead of loading.
    /// Separate from `requestOpenDataset` rather than a parameter on it, so the
    /// plain path cannot acquire the configurator by accident.
    func requestOpenDatasetWithOptions() {
        configureOnOpen = true
        openDatasetRequest &+= 1
    }
    func requestPreprocessingExport() { preprocessingExportRequest &+= 1 }


    var productWorkflowReadiness: ProductWorkflowReadiness {
        let readyKinds = Set(calibrationSession.readiness.items.compactMap { item in
            item.status.isReady ? item.kind : nil
        })
        return ProductWorkflowReadiness(
            hasOriginProbe: readyKinds.contains(.originProbe),
            hasRotation: readyKinds.contains(.rotation),
            hasQScale: readyKinds.contains(.qScale),
            hasRScale: readyKinds.contains(.rScale),
            hasVoltage: calibrationSession.hasUsableVoltage,
            hasValidDiskDetectionSettings: diskDetectionConfigurationIsValid,
            hasBraggVectors: hasCurrentBraggVectors,
            hasACOMMaterial: acomSession.modelSelection != .none,
            hasSupportedACOMMaterial: resolvedACOMModel != nil,
            hasPhysicalACOMScale: acomScaleSemantics.provenance.isPhysical
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

    // Base-range caches: SwiftUI re-evaluates these colorbar endpoints far
    // more often than content changes, and the base scan is O(pixels). Keyed
    // on the same version counters as the normalized-pixel caches; the cheap
    // contrast-window arithmetic stays per-access so slider drags never
    // rescan the image.
    @ObservationIgnored private var resultValueRangeCache:
        (version: Int, regionReference: Bool, symmetric: Bool,
         low: Double, high: Double)?
    @ObservationIgnored private var patternValueRangeCache:
        (version: Int, log: Bool, low: Double, high: Double)?

    /// Raw-value endpoints currently assigned to the scalar result colorbar.
    var resultDisplayedValueRange: (low: Double, high: Double)? {
        guard let image = displayedResultImage else { return nil }
        let version = displayedResultVersion
        let regionReference = showsACOMRegionReference
        let symmetric = displayedResultColormap.isDiverging
        let baseLow: Double
        let baseHigh: Double
        if let c = resultValueRangeCache, c.version == version,
           c.regionReference == regionReference, c.symmetric == symmetric {
            baseLow = c.low
            baseHigh = c.high
        } else {
            let (rawLow, rawHigh) = image.minMax
            guard rawLow.isFinite, rawHigh.isFinite else { return nil }
            if symmetric {
                let magnitude = Double(max(abs(rawLow), abs(rawHigh)))
                baseLow = -magnitude
                baseHigh = magnitude
            } else {
                baseLow = Double(rawLow)
                baseHigh = Double(rawHigh)
            }
            resultValueRangeCache = (version, regionReference, symmetric,
                                     baseLow, baseHigh)
        }
        let span = baseHigh - baseLow
        return (baseLow + span * Double(displayedResultRangeLo),
                baseLow + span * Double(displayedResultRangeHi))
    }

    /// Raw-value endpoints of the quality field currently being inspected, for
    /// its colorbar. `nil` when no quality field is being inspected.
    var displayedQualityValueRange: (low: Double, high: Double)? {
        guard let field = displayedQualityField else { return nil }
        let (low, high) = field.image.minMax
        return (Double(low), Double(high))
    }

    /// Raw intensity endpoints currently assigned to the CBED colorbar. When
    /// log display is active, transform-space clipping is inverted back to
    /// intensity so the labels remain physically interpretable.
    var patternDisplayedValueRange: (low: Double, high: Double)? {
        guard let pattern = displayedPattern else { return nil }
        let low: Double
        let high: Double
        if let c = patternValueRangeCache, c.version == patternVersion,
           c.log == logScale {
            low = c.low
            high = c.high
        } else {
            var scanLow = Double.greatestFiniteMagnitude
            var scanHigh = -Double.greatestFiniteMagnitude
            for pixel in pattern.pixels where pixel.isFinite {
                let value = logScale ? log10(1 + Double(max(pixel, 0))) : Double(pixel)
                scanLow = min(scanLow, value)
                scanHigh = max(scanHigh, value)
            }
            guard scanLow <= scanHigh else { return nil }
            low = scanLow
            high = scanHigh
            patternValueRangeCache = (patternVersion, logScale, low, high)
        }
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
    var progress: Double? {
        get { operationCenter.progress }
        set { operationCenter.progress = newValue }
    }
    /// Dataset opening is deliberately tracked separately from analysis work:
    /// automatic first-result generation can update `statusText` before loading
    /// has visibly finished, which made the file-open progress disappear into a
    /// generic operation indicator.
    ///
    /// `datasetLoadingProgress` is **nil during phases whose duration is not
    /// knowable** (opening the file, parsing metadata, reading a sidecar). Those
    /// get a named spinner instead of an invented percentage — a bar that steps
    /// through fabricated waypoints is less honest than one that admits it does
    /// not know, and the fabricated version was what made the old load look like
    /// it jumped in blocks and then stalled. See `docs/load-pipeline-plan.md`
    /// (stage L1, invariant I5).
    var datasetLoadingProgress: Double?
    var datasetLoadingStatus: String?
    /// True for the whole open, including the first whole-cube pass — not
    /// derived from `datasetLoadingProgress`, which is legitimately nil while an
    /// unmeasurable phase runs.
    var isLoadingDataset: Bool = false

    /// Cancels the open in progress. Non-nil exactly while a dataset load is
    /// running, which is what the Cancel affordance binds its visibility to.
    ///
    /// **Why an open needs this at all** (release owner, 2026-08-18): picking
    /// the wrong file left quitting the app as the only exit, and the open is
    /// the longest uninterruptible wait in the product — worst on the slow
    /// network source the welcome screen already warns about. Every analysis
    /// operation could already be cancelled; the open could not.
    private(set) var datasetLoadCancellation: AnalysisCancellationToken?

    /// True while a cancellation has been requested but the load has not yet
    /// unwound. The button uses it to stop offering a second cancel.
    private(set) var isCancellingDatasetLoad = false

    var canCancelDatasetLoad: Bool {
        isLoadingDataset && datasetLoadCancellation != nil && !isCancellingDatasetLoad
    }

    /// Cooperative: it asks, and the load unwinds at its next checkpoint.
    func cancelDatasetLoad() {
        guard let token = datasetLoadCancellation, !isCancellingDatasetLoad else { return }
        isCancellingDatasetLoad = true
        token.cancel()
        datasetLoadingProgress = nil
        datasetLoadingStatus = "Cancelling…"
        statusText = "Cancelling…"
    }

    /// True once cancellation has been requested. Checked at every stage
    /// boundary of the open.
    private var datasetLoadWasCancelled: Bool {
        datasetLoadCancellation?.isCancelled == true
    }
    /// Short label and unit budget for the performance panel.
    var activeOperation: String? { operationCenter.activeOperation }

    var canCancelActiveOperation: Bool { operationCenter.canCancel }

    func beginCancellableOperation(
        _ name: String, status: String, totalUnits: Int? = nil
    )
        -> AnalysisCancellationToken {
        let token = operationCenter.begin(name: name, totalUnits: totalUnits)
        statusText = status
        return token
    }

    func finishCancellableOperation(_ token: AnalysisCancellationToken) {
        operationCenter.finish(token)
    }

    func activeOperationMetrics(at now: Date = Date())
        -> AnalysisOperationMetrics? {
        operationCenter.metrics(at: now)
    }

    /// Cross-file operation helpers keep extensions from reaching into the
    /// token identity itself while still rejecting late progress/status work.
    func isCurrentOperation(_ token: AnalysisCancellationToken) -> Bool {
        operationCenter.isCurrent(token)
    }

    func updateCancellableOperation(
        _ token: AnalysisCancellationToken, progress fraction: Double, status: String
    ) {
        guard operationCenter.update(token, progress: fraction) else { return }
        statusText = status
        // While the dataset is still opening, this operation IS the load: mirror
        // its measured progress into the welcome card rather than leaving that
        // card parked on its last named stage while work is visibly happening.
        if isLoadingDataset {
            datasetLoadingProgress = progress
            datasetLoadingStatus = status
        }
    }

    func cancelActiveOperation() {
        guard let name = operationCenter.cancel() else { return }
        statusText = "Cancelling \(name)…"
    }

    // Normalized-pixel caches: SwiftUI re-evaluates view bodies far more often
    // than content changes, and normalization is O(pixels) + an allocation.
    // Keyed on the version counters, so texture and cache invalidate together.
    @ObservationIgnored private var patternNormCache: (version: Int, log: Bool, pixels: [Float])?
    @ObservationIgnored private var resultNormCache:
        (version: Int, regionReference: Bool, symmetric: Bool,
         pixels: [Float], hasInvalid: Bool)?

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

    /// Display-normalized pixels of the active analysis canvas, cached per
    /// scientific-result or region-reference version.
    func normalizedResultPixels() -> [Float] {
        guard let image = displayedResultImage else { return [] }
        let regionReference = showsACOMRegionReference
        let version = displayedResultVersion
        let symmetric = displayedResultColormap.isDiverging
        if let c = resultNormCache, c.version == version,
           c.regionReference == regionReference, c.symmetric == symmetric {
            return c.pixels
        }
        let pixels = image.normalized(symmetric: symmetric)
        let hasInvalid = pixels.contains { $0 < 0 }
        resultNormCache = (version, regionReference, symmetric, pixels, hasInvalid)
        return pixels
    }

    @ObservationIgnored private var qualityNormCache: (version: Int, name: String, pixels: [Float])?

    /// Display-normalized pixels of the quality field currently being
    /// inspected, cached per (result version, field name) — mirrors
    /// `normalizedResultPixels()`.
    func normalizedQualityPixels() -> [Float] {
        guard let field = displayedQualityField else { return [] }
        let version = displayedResultVersion
        if let c = qualityNormCache, c.version == version, c.name == field.name {
            return c.pixels
        }
        let pixels = field.image.normalized(symmetric: false)
        qualityNormCache = (version, field.name, pixels)
        return pixels
    }

    /// True when the displayed scalar result contains masked (no-data) pixels,
    /// which render as neutral gray. Drives the colorbar's masked swatch.
    func displayedResultHasMaskedPixels() -> Bool {
        guard displayedResultImage != nil else { return false }
        _ = normalizedResultPixels()
        return resultNormCache?.hasInvalid ?? false
    }

    var displayedPattern: DiffractionPattern? {
        // A real-space region ROI drives the CBED with the summed pattern —
        // but only in Current mode (R20, owner 2026-09-01): Mean and Max are
        // whole-scan statistics, and a region sum silently replacing them
        // while their tab stayed selected was wrong. Point already behaved
        // this way; Rectangle/Circle now match it.
        if patternDisplayMode == .current,
           realSpaceShape != .point, let vd = virtualDiffractionPattern { return vd }
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
        // v2.5 step 3c: the published product survives a task switch on its
        // own; the navigation relabel cache that used to live here is gone.
        navigation.analysisMode = mode
        navigation.workspaceArea = mode.workspaceArea
        if mode == .acom, acomSession.scope == .selectedRegion {
            acomSession.regionSelectionActive = true
            Task { await ensureScanNavigator() }
        }
    }

    /// Navigate at the product level without starting scientific work. Whole-
    /// scan operations are always launched from an explicit action in their
    /// task panel, so moving around the app is immediate and side-effect free.
    func selectWorkspace(_ area: WorkspaceArea) {
        navigation.workspaceArea = area
        if let preferred = area.defaultAnalysisMode,
           !area.analysisModes.contains(navigation.analysisMode) {
            changeMode(preferred)
        }
    }

    /// The prominent, user-facing action for the current workspace. This is
    /// intentionally separate from `runCurrentAnalysis`, whose legacy contract
    /// only refreshes lightweight/cached views for some modes.
    func runPrimaryWorkspaceTask() async {
        switch navigation.workspaceArea {
        case .prepare:
            if !calibrationSession.calibration.hasFittedOrigin {
                await calibrateOrigin()
            } else if !calibrationSession.calibration.hasRotation {
                await calibrateRotation()
            }
        case .image:
            await runCurrentAnalysis()
        case .map:
            switch navigation.analysisMode {
            case .disks: await runDiskDetection()
            case .strain: await runStrainMapping()
            case .acom: await runACOM()
            default: break
            }
        case .reconstruct:
            if navigation.analysisMode == .dpc {
                await runCurrentAnalysis()
            } else if navigation.analysisMode == .singleslicePtychography {
                await runSingleslicePtychography()   // v2.5 step 7a: its own task
            } else if parallaxPreprocess == nil {
                await prepareParallaxPreview()
            } else if parallaxAlignment?.isComplete != true {
                await alignParallaxNextLevel()
            } else if parallaxHigherOrderFit == nil {
                fitParallaxAberrations()
            } else if parallaxCorrection == nil {
                await correctParallaxPhase()
            } else if parallaxSubpixel == nil {
                await upsampleParallaxBF()
            }
        case .results:
            break
        }
    }

    func openFile(url: URL) {
        Task { await openFileAsync(url: url) }
    }

    /// The load specification a previous session recorded for this file, if any.
    ///
    /// Read BEFORE the load, because it decides what gets read. Reopening a
    /// session reopens the **source** file and re-applies the specification to
    /// it — it never re-derives from reduced data, which is the property that
    /// makes a crop a view rather than a new dataset.
    ///
    /// A specification that no longer fits the file — the dataset was replaced,
    /// or a sidecar was copied next to a different cube — is dropped rather than
    /// clamped, with the reason said out loud. Loading a *different* region than
    /// the session recorded, silently, is the failure this guards.
    /// Internal rather than private so `SessionSidecarLocatorTests` can drive the
    /// WIRING, not just the pure decision. Gate D showed that reverting this
    /// function's URL derivation to the pre-S1 form — the literal defect S1
    /// exists to fix — left the whole suite green, because every test addressed
    /// the locator and none addressed the call site. // v2 S1
    func recordedLoadSpecification(
        forSourcePath path: String, source: DatasetDescriptor
    ) async -> LoadSpecification? {
        // THROUGH THE SEAM, not around it. This call site used to derive the
        // sidecar path itself and never consult the security-scoped bookmark, so
        // a companion the app *had* been granted access to was readable for
        // results and calibration and unreadable for the crop that produced
        // them. // v2 S1
        // Existence is checked AT the url we are about to read, not by a second
        // independent derivation. Gate D's mutation of this line was invisible
        // while the guard re-derived the path on its own: the call site could
        // read one file and test another. // v2 S1
        let url = sessionSidecar.location(forSourcePath: path)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }

        // NOT `try?`. A refused read and "this session recorded no crop" are
        // different facts, and collapsing them is what made this defect quiet:
        // the sidecar says the session was a cropped view, the read is refused,
        // nil comes back, and the dataset opens at FULL EXTENT without a word.
        // Right numbers, wrong extent. Measured cause is EPERM from the sandbox
        // (docs/open-items.md, 2026-08-19), which no amount of retrying fixes —
        // so it is said out loud instead. // v2 S1
        let read: Result<LoadSpecification?, Error>
        do {
            read = .success(try await Task.detached(priority: .utility) {
                try BraggVectorEMDWriter.loadSession(from: url)
            }.value.loadSpecification)
        } catch {
            read = .failure(error)
        }

        let specification: LoadSpecification
        switch SessionSidecarLocator.recordedOutcome(
            from: read, sidecar: url.lastPathComponent
        ) {
        case .noneRecorded:
            return nil
        case .unreadable(let message):
            // The LOCATOR, not `statusText`. Gate D measured that `statusText`
            // set here is overwritten three lines later by `activate`'s
            // `beginDatasetLoadingStage`, and again by the preview and whole-cube
            // passes — so the first version of this reported the refusal into a
            // channel the user could never read it from. // v2 S1
            sessionSidecar.noteUnreadable(message)
            // Loading proceeds at full extent, so from here on a sidecar
            // rewrite would erase the crop this session never restored and
            // relabel its results — refused until the dataset is reopened
            // with the recorded view restored (S5 finding F9). // v2 S7
            gates.noteSidecarRestoreFailed(.unreadable, message: message)
            statusText = message
            return nil
        case .recorded(let recorded):
            specification = recorded
        }
        guard (try? LoadView(source: source, specification: specification)) != nil else {
            let message = "The saved session describes a region this file does not have; loading it whole."
            // The gate, not only `statusText` — the sibling branch above
            // learned in S1 that `statusText` set here is overwritten before
            // anyone can read it, and this branch had kept exactly that
            // defect. The inspector renders the gate's failure. // v2 S7
            gates.noteSidecarRestoreFailed(.doesNotFit, message: message)
            statusText = message
            return nil
        }
        return specification
    }

    // MARK: - Configured open (L5)

    /// The dataset being configured before it is loaded, or nil. L5's seam —
    /// see `App/PendingLoad.swift`.
    /// The load specification recorded by the session sidecar for the open
    /// dataset, if any. Compared against `loadedView.specification` so a
    /// restored result computed on a different view can be labelled as such
    /// rather than read as describing what is on screen (L6 item 3).
    private(set) var sessionLoadSpecification: LoadSpecification?

    private(set) var pendingLoad: PendingLoad?

    /// Which destination the next file-importer result goes to. Set by the
    /// control that opened the panel; there is one importer and two entry
    /// points, and the direct one must stay exactly as it was.
    var configureOnOpen = false

    /// Open far enough to look at, then **stop and ask**.
    ///
    /// Reached only from "Open with options…" — `openFile` still loads the whole
    /// file with no interruption, which is the entry point almost every open
    /// uses. Everything done here is cheap: open the reader, discover the
    /// descriptor, sample a strided preview. The expensive pass waits for
    /// `commitPendingLoad`.
    func openFileForConfiguration(url: URL) {
        Task {
            beginDatasetLoading("Opening \(url.lastPathComponent)…")
            defer { if isLoadingDataset { finishDatasetLoading() } }
            let accessed = url.startAccessingSecurityScopedResource()
            do {
                let reader = try await Self.makeReader(for: url)
                beginDatasetLoadingStage("Reading file structure of \(url.lastPathComponent)…")
                let source = try await reader.discoverPrimaryDataset()
                guard source.is4D else {
                    if accessed { url.stopAccessingSecurityScopedResource() }
                    present(H5Error.unsupportedRank(source.shape.count))
                    return
                }
                if datasetLoadWasCancelled {
                    if accessed { url.stopAccessingSecurityScopedResource() }
                    return
                }
                let size = (try? FileManager.default
                    .attributesOfItem(atPath: url.path)[.size]) as? NSNumber
                let pending = PendingLoad(
                    source: source, reader: reader, url: url,
                    accessedSecurityScope: accessed,
                    fileByteCount: size?.intValue
                )
                // The preview is built against a full-extent view of the source:
                // it is what the user drags ON, so it must show the whole file
                // regardless of what they have configured so far. It reads
                // through the pending load's own array, so the single-DP pane's
                // first fetch hits a warm pattern cache instead of the disk.
                //
                // Same determinate progress as `buildDatasetPreview` — L1's
                // rule: no phase of an open reports indeterminately when the
                // work is countable. This call site used to omit the
                // `progress:` argument the normal open path passes, so the
                // same phase was determinate on one path and a bare spinner
                // on the other. // v2 S4
                beginDatasetLoadingStage("Sampling a preview…")
                pending.preview = try? await DatasetPreviewBuilder.make(
                    data: pending.data, descriptor: source,
                    cancellation: datasetLoadCancellation,
                    progress: previewProgressHandler(
                        rows: DatasetPreviewBuilder.sampledRowCount(for: source),
                        epoch: datasetEpoch
                    )
                )
                guard !datasetLoadWasCancelled else {
                    if accessed { url.stopAccessingSecurityScopedResource() }
                    return
                }
                // Only after the cancellation guard: a cancelled open must not
                // leave a detached pattern read running against a URL whose
                // security scope the lines above just released.
                pending.fetchDefaultSingleDP()
                pendingLoad = pending
                finishDatasetLoading()
            } catch {
                if accessed { url.stopAccessingSecurityScopedResource() }
                present(error)
            }
        }
    }

    /// The determinate "Sampling a preview · row N of M" reporter, shared by
    /// BOTH open paths (the plain open's `buildDatasetPreview` and the
    /// configurator's open) so the wording and the clamp cannot drift apart —
    /// drift is exactly the determinate-on-one-path defect S4 fixed. Built in
    /// a method so `[weak self]` is the closure's first capture — inline
    /// inside the open Task, the weak capture fights the Task's implicit
    /// strong self (#ImplicitStrongCapture, the warning class the S3 rider
    /// cleared).
    ///
    /// BOTH guards are load-bearing: `datasetEpoch` stops a cancelled open's
    /// late ticks from writing a stale row counter over the *next* open's
    /// progress (the next open sets `isLoadingDataset` back to true, so that
    /// guard alone cannot tell the two apart). // v2 S4
    private func previewProgressHandler(rows: Int, epoch: Int) -> @Sendable (Double) -> Void {
        { [weak self] fraction in
            Task { @MainActor [weak self] in
                guard let self, self.datasetEpoch == epoch,
                      self.isLoadingDataset else { return }
                let done = min(rows, max(0, Int((fraction * Double(rows)).rounded())))
                self.reportDatasetLoadingProgress(
                    fraction, "Sampling a preview · row \(done) of \(rows)"
                )
            }
        }
    }

    /// Load what the configurator was showing.
    func commitPendingLoad() {
        // The beam gate is enforced HERE, not only by the Load button's
        // `.disabled` — a gate that exists only in a view modifier is not a
        // gate (the SessionSidecarLocator rule): any second entry point, menu
        // command or test would commit a beam-excluding crop without it.
        // // v2 S4
        guard let pending = pendingLoad, pending.view != nil,
              pending.directBeamRefusal == nil else { return }
        pendingLoad = nil
        pending.cancelSingleDPFetch()
        Task {
            beginDatasetLoading("Opening \(pending.source.datasetPath)…")
            if let openURL { openURL.stopAccessingSecurityScopedResource() }
            openURL = pending.accessedSecurityScope ? pending.url : nil
            reader = pending.reader
            datasets = [pending.source]
            // This path changes the open dataset WITHOUT `openFileAsync`, so
            // it must drop the previous dataset's restore-failure flag itself
            // — Gate B found the flag surviving a configurator commit and
            // refusing the NEW dataset's saves with the OLD dataset's message
            // (2026-08-25). (`sessionSidecar`'s own state has the same
            // blind spot, recorded in docs/open-items.md — S1's surface, not
            // changed here.)
            gates.clearSidecarRestoreFailure()
            await activate(
                descriptor: pending.source, reader: pending.reader,
                specification: pending.configuration.specification,
                runInitialAnalysis: false
            )
            if datasetLoadWasCancelled || !hasDataset {
                await discardPartialLoad()
                finishDatasetLoading()
                return
            }
            await runCurrentAnalysis()
            if datasetLoadWasCancelled {
                await discardPartialLoad()
                finishDatasetLoading()
                return
            }
            rememberOpenedDataset(pending.url)
            finishDatasetLoading()
        }
    }

    /// Reopen the same source, whole — the promote control's action.
    /// Promotion is *removing* the load specification — `.fullExtent` is the
    /// identity — never re-deriving anything from the reduced data
    /// (docs/v2-release.md §1, commitment 2).
    ///
    /// Deliberately NOT `openFileAsync`: that path re-applies the sidecar's
    /// recorded specification, which is exactly the crop being promoted away.
    /// The reader and the security scope are the ones the rehearsal already
    /// holds, so this is `commitPendingLoad`'s shape with the one
    /// specification the configurator never needs to validate.
    ///
    /// The source is `loadView`'s own — the descriptor the loaded view
    /// declares it was cut from — never `datasets.first`. The two are equal on
    /// every shipped path, but the button's caption prices `loadView`'s
    /// source, and Gate A found the pairing unpinned: the moment a
    /// multi-dataset path can carry a specification, `datasets.first` reopens
    /// the wrong cube while the caption describes the right one. A LoadView
    /// source is 4D by construction (its init throws otherwise), so no
    /// separate rank check is needed.
    ///
    /// What the reopened dataset shows is decided by machinery that already
    /// exists: `activate` re-references calibration into the full-extent view,
    /// and a session result restored from the sidecar is labelled with the
    /// view it was computed on when that differs (L6 item 3). Cancelling
    /// unwinds to the welcome screen like any cancelled open — the rehearsal
    /// view is a specification, not state worth half-restoring.
    ///
    /// Internal rather than private so the WIRING can be tested — the S1
    /// lesson: a test that cannot reach the call site pins the pure decision
    /// and not the path the app takes. // v2 S3
    /// `runReestablishingAnalysis: false` is the replay path's option (v2 S6):
    /// when a recorded pipeline is about to replay, the current-mode pass
    /// would be a redundant whole-cube run — at promote scale, a real cost —
    /// immediately overwritten by the recipe's own first step.
    func promoteToFullExtent(runReestablishingAnalysis: Bool = true) async {
        // The recipe SURVIVES a promote: same session, same dataset — the
        // promote run is what the recipe exists to feed, and `activate`'s
        // reset (correct for a dataset change) would otherwise destroy every
        // unsaved step at exactly the moment they become useful
        // (Gate B-lite F11). Re-adopted after success below, with the frame
        // it was recorded under — the sidecar re-adopt during `activate`
        // would otherwise stand, and its frame tag with it. // v2 S6
        let recipeBeforePromote = replay.record
        let frameBeforePromote = replay.parameterFrame
        // `!isLoadingDataset` is the reentrancy gate. Without it the only
        // protections were the button's `.disabled` (which cannot see a load
        // that starts after the click renders) and an ordering accident —
        // `activate` resets `loadedView` before its first suspension, so a
        // double-fired Task happened to fail the guard below. An accident is
        // not a contract; a second `beginDatasetLoading` would replace the
        // shared cancellation token and Cancel would stop only the newer
        // load. Gate A review, 2026-08-19.
        guard !isLoadingDataset, let reader, let source = loadView?.source,
              !loadedView.isFullExtent else { return }
        // The recipe survives EVERY exit, not only success: `activate` resets
        // it and may re-adopt the sidecar's OLDER copy before a cancel is
        // noticed, so the pre-S6 success-only re-adopt let a cancelled
        // promote silently swap an unsaved recipe for the sidecar's stale one
        // (Gate A finding C5, 2026-08-25). `adopt` treats nil/absent as
        // absence, so an empty pre-promote record leaves whatever the sidecar
        // restore adopted in place. Registered after the guard: a refused
        // promote touched nothing and restates nothing.
        defer {
            replay.adopt(recipeBeforePromote.isEmpty ? nil : recipeBeforePromote,
                         recordedOn: frameBeforePromote)
        }
        beginDatasetLoading("Reopening \(source.fileName) at full extent…")
        await activate(
            descriptor: source, reader: reader,
            specification: .fullExtent,
            runInitialAnalysis: false
        )
        if datasetLoadWasCancelled || !hasDataset {
            await discardPartialLoad()
            finishDatasetLoading()
            return
        }
        guard loadedView.isFullExtent else {
            // `activate` presented its own error and left the rehearsal
            // loaded (its failure paths return before touching `loadedView`).
            // Unreachable today — a promotable source already survived a
            // rehearsal LoadView init, so the full-extent init cannot throw —
            // but without this bail a future error path in `activate` would
            // run the whole-cube pass under a "Reopening…" banner for a
            // reopen that never happened. Do not discard: the rehearsal is
            // intact and still what the user had.
            finishDatasetLoading()
            return
        }
        if runReestablishingAnalysis {
            await runCurrentAnalysis()
            if datasetLoadWasCancelled {
                await discardPartialLoad()
                finishDatasetLoading()
                return
            }
        }
        // The recipe re-adopt (Gate B-lite F11) now happens in the defer
        // above, covering the cancel and failure exits too. Re-stamp the
        // recovery record so the persisted (frame, position) pair describes
        // the promoted view now, not whenever the user next moves the cursor
        // (Gate B-lite F14). // v2 S5
        finishDatasetLoading()
        persistRecoveryPosition()
    }

    /// The promote control's action since v2 S6 — the release claim's
    /// "one action" (docs/v2-release.md §1, commitment 2): reopen at full
    /// extent, then replay the recorded pipeline sequentially, unattended,
    /// with the machine held awake. With an empty recipe this is exactly the
    /// S3 promote, re-establishing pass included.
    ///
    /// The record and its frame are captured BEFORE the reopen: the replay
    /// executes the recipe the user promoted, not whatever `activate`'s
    /// sidecar restore re-adopts mid-flight.
    func promoteAndReplayRecipe() async {
        let record = replay.record
        let frame = replay.parameterFrame ?? .unknown
        guard !record.isEmpty else {
            await promoteToFullExtent()
            return
        }
        // Replay is the promote's tail only — on an already-full-extent view
        // there is nothing this button's gesture means.
        guard !loadedView.isFullExtent, !isLoadingDataset else { return }
        // The plan is PURE, so every certain refusal is known before the
        // expensive reopen is paid for. A recipe whose FIRST step already
        // refuses will replay nothing — run the ordinary re-establishing
        // pass in that case so the morning is not "hours of reopen, zero
        // analyses, and a halt" (Gate A findings E1/B2, 2026-08-25).
        let planned = ReplayPlanner.plan(record, frame: frame)
        let firstStepRefused: Bool
        if case .failure = planned[0].result { firstStepRefused = true }
        else { firstStepRefused = false }
        // `begin` BEFORE the reopen: the keep-awake assertion must cover the
        // longest unattended phase (findings B1/C1), and its refusal is the
        // single-flight gate — a second overlapping call must not write into
        // this run's step table or release its assertion (finding A5).
        // The frame note travels into the run so the morning summary states a
        // re-referenced replay the same way the pre-click caption did — set
        // only when a planned step actually carries detector numbers. // v2 S10
        let frameNote: String?
        if let note = frame.reReferenceDescription,
           planned.contains(where: {
               if case .success(let plan) = $0.result {
                   plan.usesDetectorFrameParameters
               } else { false }
           }) {
            frameNote = "Recipe \(note)."
        } else {
            frameNote = nil
        }
        guard replayRun.begin(titles: planned.map(\.title), frameNote: frameNote) else { return }
        await promoteToFullExtent(runReestablishingAnalysis: firstStepRefused)
        // Replay only on the back of a promote that actually happened: a
        // refused or cancelled promote leaves the rehearsal (or nothing)
        // loaded, and running the recipe against it would be the promote
        // run's summary lying about which view the numbers describe.
        guard hasDataset, loadedView.isFullExtent, !isLoadingDataset else {
            replayRun.finish(haltReason: "the reopen did not complete, so nothing was replayed — the recipe is unchanged")
            statusText = "Promote run stopped — the reopen did not complete; nothing was replayed"
            return
        }
        await executeReplay(planned: planned)
    }

    /// Sequential replay — v2 S6. One step at a time, in recipe order; the
    /// first refusal, failure or cancellation HALTS the run (never silently
    /// past a failure, per the S6 brief) and everything after it stays "not
    /// reached" in the summary. `replayRun.begin` already ran — the caller
    /// holds the keep-awake assertion from before the reopen.
    private func executeReplay(planned: [PlannedReplayStep]) async {
        let epoch = datasetEpoch
        var haltReason: String?
        for (index, step) in planned.enumerated() {
            guard datasetEpoch == epoch, !isLoadingDataset else {
                haltReason = "the dataset changed while the promote run was executing"
                break
            }
            replayRun.willRun(step: index)
            switch step.result {
            case .failure(let refusal):
                replayRun.conclude(step: index, outcome: .refused(reason: refusal.reason))
                haltReason = "\(step.title) could not be replayed: \(refusal.reason)"
            case .success(let plan):
                let started = Date()
                switch await executeReplayStep(plan) {
                case .refused(let reason):
                    replayRun.conclude(step: index, outcome: .refused(reason: reason))
                    haltReason = "\(step.title) could not be replayed: \(reason)"
                case .ran(let outcome):
                    if datasetEpoch != epoch {
                        replayRun.conclude(step: index, outcome: .failed(
                            reason: "the dataset changed while this step was executing"))
                        haltReason = "the dataset changed while the promote run was executing"
                        break
                    }
                    switch outcome {
                    case .published:
                        // `statusText` here is the entry point's own success
                        // line — counts and fractions — written by the same
                        // function that just returned `.published`.
                        replayRun.conclude(step: index, outcome: .succeeded(
                            detail: statusText, seconds: Date().timeIntervalSince(started)))
                    case .cancelled:
                        replayRun.conclude(step: index, outcome: .cancelled)
                        haltReason = "\(step.title) was cancelled, and the run stopped there"
                    case .failed(let reason):
                        replayRun.conclude(step: index, outcome: .failed(reason: reason))
                        haltReason = "\(step.title) failed — \(reason)"
                    }
                }
            }
            if haltReason != nil { break }
        }
        replayRun.finish(haltReason: haltReason)
        statusText = haltReason.map { "Promote run halted — \($0)" }
            ?? "Promote run finished — \(planned.count) \(planned.count == 1 ? "analysis" : "analyses") replayed"
    }

    private enum ReplayStepExecution {
        /// The entry point ran and returned its own typed verdict.
        case ran(AnalysisRunOutcome)
        /// A recorded precondition this session cannot honour — the step never
        /// ran. Substituting the session's different value silently would be a
        /// parameter change no summary states.
        case refused(String)
    }

    /// Apply one parsed step's recorded parameters to live state and run the
    /// SAME entry point the user's click runs — replay must not grow a second
    /// execution path that can drift from the interactive one.
    /// v2.5 step 5a: a replayed step refuses for exactly the reason the live
    /// checklist would block the same task — one requirements list. Called
    /// after a step has written its recorded parameters, so the answer is
    /// about the state the run would actually see.
    func replayRefusal(for mode: AnalysisMode) -> String? {
        if case .unavailable(let reason) = ProductWorkflow.readiness(
            for: mode, readiness: productWorkflowReadiness) {
            return "this step cannot run on the promoted view — \(reason)"
        }
        return nil
    }

    private func executeReplayStep(_ plan: ReplayStepPlan) async -> ReplayStepExecution {
        switch plan {
        case .virtualDetector(let shape, let recordedAperture):
            virtualShape = shape
            aperture = recordedAperture
            if let reason = replayRefusal(for: .virtualDetector) { return .refused(reason) }
            return .ran(await runVirtualDetector(replaying: true))

        case .dpc(let wantsFittedOrigin):
            guard calibrationSession.calibration.hasFittedOrigin == wantsFittedOrigin else {
                // The wanted-but-absent direction is the EXPECTED one after a
                // promote: per-position origin maps are fitted at the
                // rehearsal's extent and do not carry across the reopen
                // (the same inverse-mapping family as S10's detector-frame
                // work — Gate A findings A2/C2, 2026-08-25). The refusal
                // must say what to do, not just what is missing.
                if wantsFittedOrigin {
                    return .refused("the recipe ran DPC against calibrated origins, and the rehearsal's per-position origin fit does not carry across a promote — calibrate the origin on the promoted view, then run DPC by hand")
                }
                return .refused("the recipe ran DPC against the global center, but this session holds a fitted origin — running it anyway would silently change the measurement's reference")
            }
            if let reason = replayRefusal(for: .dpc) { return .refused(reason) }
            return .ran(await runDPC(replaying: true))

        case .diskDetection(let params):
            diskParams = params
            if let reason = replayRefusal(for: .disks) { return .refused(reason) }
            return .ran(await runDiskDetection(replaying: true))

        case .strain(let strainPlan):
            strain.referenceMode = .wholeScan
            if let basis = strainPlan.manualBasis {
                strain.basisMode = .manual
                strain.g1X = basis.g1x
                strain.g1Y = basis.g1y
                strain.g2X = basis.g2x
                strain.g2Y = basis.g2y
            } else {
                strain.basisMode = .automatic
            }
            if let reason = replayRefusal(for: .strain) { return .refused(reason) }
            return .ran(await runStrainMapping(replaying: true))

        case .acom(let acomPlan):
            // Resolution is `ACOMReplayPlan.resolveMaterial` (pure, tested):
            // by id, never a fallback crystal; the custom-cubic arm exists
            // because `activate` reset the SELECTION but the fields survive
            // (Gate A finding C4), and it now also requires the rehearsed
            // lattice constant (Gate D 2026-09-02).
            switch acomPlan.resolveMaterial(in: .init(
                importedIDs: Set(acomSession.importedCrystalModels.map(\.id)),
                customStructure: acomSession.customStructure, customLatticeA: acomSession.customLatticeA,
                customZ: acomSession.customZ)) {
            case .library(let id): acomSession.modelSelection = .library(id)
            case .imported(let id): acomSession.modelSelection = .imported(id)
            case .customCubic: acomSession.modelSelection = .customCubic
            case .unavailable(let reason): return .refused(reason)
            }
            guard resolvedACOMModel?.id == acomPlan.materialID else {
                return .refused("the recipe's phase model '\(acomPlan.materialID)' is not available in this session — select or import the phase model it names, then run ACOM by hand")
            }
            let sessionScale = acomScaleSemantics.invAngstromPerPixel
            let recordedScale = acomPlan.scaleInvAngstromPerPixel
            guard abs(sessionScale - recordedScale) <= max(1e-12, abs(recordedScale) * 1e-6) else {
                return .refused(String(
                    format: "the recipe matched at %.6g Å⁻¹/px but this session's scale is %.6g Å⁻¹/px — matching at a different scale gets orientations wrong with nothing to catch it, so recalibrate Q or run ACOM by hand",
                    recordedScale, sessionScale))
            }
            acomSession.scope = acomPlan.scope
            acomSession.quality = acomPlan.quality
            if let reason = replayRefusal(for: .acom) { return .refused(reason) }
            return .ran(await runACOM(replaying: true))
        }
    }

    /// Walk away without loading. Releases the file access the pending open
    /// took, so a cancelled configuration leaves nothing held — and, as with a
    /// cancelled load, is not remembered.
    func discardPendingLoad() {
        guard let pending = pendingLoad else { return }
        pendingLoad = nil
        // Before releasing the scope: a dropped PendingLoad must not keep a
        // detached pattern read running against a URL the app no longer has
        // scoped access to. // v2 S4
        pending.cancelSingleDPFetch()
        if pending.accessedSecurityScope {
            pending.url.stopAccessingSecurityScopedResource()
        }
        statusText = "No file loaded"
    }

    /// The reader for a URL, by extension. Extracted so the configured open and
    /// the direct open cannot drift apart on which formats they accept.
    private static func makeReader(for url: URL) async throws -> any FourDDataSource {
        switch url.pathExtension.lowercased() {
        case "dm4", "dm3": return try await DM4Reader(path: url.path)
        case "mib": return try MIBReader(path: url.path)
        case "raw", "xml": return try EMPADReader(path: url.path)
        default: return try H5Reader(path: url.path)
        }
    }

    /// Reads and parses a local CIF file, adding the result to this run's
    /// imported-phase-model list and selecting it. Reading/parsing is Core's
    /// job even though it is triggered from a picker — `CIFImport` does the
    /// parsing, this just owns the file access and the resulting state.
    ///
    /// Failure here is routed like opening a dataset (`present`, the
    /// window-modal path), not `presentComputeFailure`: a bad CIF is a fresh
    /// file that never entered analysis state, so there is nothing mid-step
    /// to keep usable — same category as a corrupt or unreadable dataset
    /// file. `CIFImportError.errorDescription` names the offending tag,
    /// value, symbol, or point group, so the modal shows a specific reason.
    func importCrystalModel(from url: URL) {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            let baseName = url.deletingPathExtension().lastPathComponent
            let model = try CIFImport.crystalModel(from: text, fileBaseName: baseName)
            if let index = acomSession.importedCrystalModels.firstIndex(where: { $0.id == model.id }) {
                acomSession.importedCrystalModels[index] = model
            } else {
                acomSession.importedCrystalModels.append(model)
            }
            acomSession.modelSelection = .imported(model.id)
            statusText = "Imported phase model \"\(model.displayName)\" from \(url.lastPathComponent)"
        } catch {
            present(error)
        }
    }

    /// Deterministic in-memory dataset shared by UI automation, repeatable
    /// design walkthroughs, and the welcome screen's Try Demo Data path —
    /// every workspace works without a file and nothing on disk is touched.
    ///
    /// `specification` exists for tests that need a *reduced* view without a
    /// file on disk (the promote wiring, v2 S3). The app's own callers pass
    /// nothing and open the demo whole.
    func openDemoFixture(
        calibrated: Bool = true,
        specification: LoadSpecification = .fullExtent
    ) async {
        let source = DemoFourDDataSource(includesCalibration: calibrated)
        // Same rule as `commitPendingLoad`: a dataset change outside
        // `openFileAsync` drops the previous dataset's restore-failure flag.
        // // v2 S7
        gates.clearSidecarRestoreFailure()
        beginDatasetLoading("Opening demo dataset…")
        defer {
            if isLoadingDataset { finishDatasetLoading() }
        }
        do {
            beginDatasetLoadingStage("Reading file structure of the demo dataset…")
            let descriptor = try await source.discoverPrimaryDataset()
            reader = source
            datasets = [descriptor]
            openURL = nil
            await activate(descriptor: descriptor, reader: source,
                           specification: specification)
            // `activate` fails by presenting and returning, not by throwing —
            // without this guard a specification that does not fit the demo
            // cube still printed "Demo ready…" over the error status, with
            // reader/datasets already swapped and nothing loaded. Both checks
            // are needed: the specification comparison catches a failed
            // re-open OVER a previous demo (whose stale spec cannot equal the
            // failing one — a spec that fits the demo does not fail), and the
            // file-path comparison catches a previous real dataset that
            // happened to share the requested spec. Gate A review, 2026-08-19.
            guard loadView?.specification == specification,
                  self.descriptor?.filePath == datasets.first?.filePath else { return }
            finishDatasetLoading()
            acomSession.display = .ipfZ
            // S22c wording: the steps are Prepare / Imaging / Bragg / Phase /
            // Results — caught on screen by the consolidated drive after the
            // re-cut renamed them everywhere else.
            statusText = "Demo ready — follow Prepare → Imaging → Strain & ACOM (Bragg disks first) → Results; each task lists anything it still needs"
        } catch {
            present(error)
        }
    }

    func openRecent(_ recent: RecentDataset) {
        do {
            let resolved = try WorkspaceRecoveryStore.resolve(recent.bookmark)
            if recoveryRecord?.datasetID == recent.id { pendingRecovery = recoveryRecord }
            if resolved.stale { refreshStoredBookmark(for: resolved.url, id: recent.id) }
            openFile(url: resolved.url)
        } catch {
            // Two different facts, two different fates (Gate D second
            // reader, 2026-08-25): a volume that is merely NOT MOUNTED keeps
            // its entry — deleting it would destroy the only place the NAS
            // path is shown, for a dataset that is fine — while a genuinely
            // dead bookmark is still removed as before. `.withoutMounting`
            // (the same day's fix) is what makes the unmounted case reach
            // this catch fast instead of freezing the UI ~30 s per click.
            if let volume = WorkspaceRecoveryStore.unmountedVolumeName(
                forBookmark: recent.bookmark
            ) {
                present(SimpleError(
                    "The volume “\(volume)” is not mounted. Connect it in Finder, then open the dataset again."
                ))
            } else {
                recents.remove(id: recent.id)
                present(SimpleError("This recent dataset is no longer accessible. Open it again to renew permission."))
            }
        }
    }

    /// D4 (owner decision, 2026-09-01: "i can't even remove it"): ignoring a
    /// session is a REOPEN with the sidecar skipped for that one open — not
    /// in-session state surgery, the same shape as Change… (which "never
    /// adopts a calibration in-session; it retargets the file and asks for a
    /// reopen", Gate B 2026-08-25). The sidecar FILE is untouched; the skip
    /// is stamped with the dataset's identity so an open that fails part-way
    /// can never leak the skip onto an unrelated dataset.
    private var ignoreSessionForDatasetID: String?

    func reopenIgnoringSessionSidecar() {
        guard let recoveryRecord,
              let recent = recents.entry(withID: recoveryRecord.datasetID) else {
            present(SimpleError("The current dataset has no recorded reopen path."))
            return
        }
        ignoreSessionForDatasetID = recent.id
        openRecent(recent)
    }

    func reopenLastDataset() {
        guard let recoveryRecord,
              let recent = recents.entry(withID: recoveryRecord.datasetID) else {
            present(SimpleError("No recoverable dataset is available.")); return
        }
        openRecent(recent)
    }

    func removeRecent(_ recent: RecentDataset) {
        recents.remove(id: recent.id)
        if recoveryRecord?.datasetID == recent.id {
            recoveryRecord = nil
            WorkspaceRecoveryStore.clearRecovery()
        }
    }

    private func rememberOpenedDataset(_ url: URL) {
        do {
            let bookmark = try WorkspaceRecoveryStore.bookmark(for: url)
            let id = url.standardizedFileURL.path
            recents.remember(RecentDataset(id: id, displayName: url.lastPathComponent,
                                           bookmark: bookmark, lastOpened: Date()))
            recoveryRecord = DatasetRecoveryRecord(
                datasetID: id, bookmark: bookmark,
                selectedX: selectedScan.x, selectedY: selectedScan.y,
                analysisMode: navigation.analysisMode.rawValue, updated: Date(),
                loadSpecification: loadedView.specification
            )
            WorkspaceRecoveryStore.saveRecovery(recoveryRecord!)
        } catch {
            statusText = "Loaded data, but recent-file access could not be remembered: \(error.localizedDescription)"
        }
    }

    private func refreshStoredBookmark(for url: URL, id: String) {
        guard let bookmark = try? WorkspaceRecoveryStore.bookmark(for: url) else { return }
        recents.updateBookmark(bookmark, forID: id)
    }

    private func persistRecoveryPosition() {
        guard descriptor != nil, var record = recoveryRecord else { return }
        record.selectedX = selectedScan.x
        record.selectedY = selectedScan.y
        record.analysisMode = navigation.analysisMode.rawValue
        record.updated = Date()
        // Every stamp restates the frame, so a position persisted after a
        // promote is knowably full-extent, not silently reinterpreted by the
        // next crop-restoring relaunch. // v2 S5
        record.loadSpecification = loadedView.specification
        recoveryRecord = record
        WorkspaceRecoveryStore.saveRecovery(record)
    }

    func selectDataset(_ descriptor: DatasetDescriptor) {
        guard let reader else { return }
        Task {
            // Bracketed as a load, the way openFileAsync does it. `activate`
            // preloads the resident cube, and the preload's progress callback is
            // gated on `isLoadingDataset` — so without this bracket, switching
            // to a multi-gigabyte dataset set statusText to "Loaded …" with the
            // bar at 1.0 and then read the whole cube in complete silence. That
            // is #36's stall reintroduced one layer down, in the one path L1's
            // reordering did not cover. Found by adversarial review 2026-08-17.
            beginDatasetLoading("Opening \(descriptor.datasetPath)…")
            await activate(descriptor: descriptor, reader: reader)
            finishDatasetLoading()
        }
    }

    func openManualPath(_ datasetPath: String) {
        guard let reader else {
            present(SimpleError("Open a file before entering a dataset path."))
            return
        }

        Task {
            operationCenter.setBusy(true)
            defer { operationCenter.setBusy(false) }

            do {
                guard let h5 = reader as? H5Reader else {
                    present(SimpleError("Manual dataset paths are only supported for HDF5 files."))
                    return
                }
                let descriptor = try await h5.describe(path: datasetPath)
                if !datasets.contains(where: { $0.datasetPath == descriptor.datasetPath }) {
                    datasets.append(descriptor)
                }
                // Bracketed for the same reason as `selectDataset` above: every
                // stage line, the preview sampling and the resident preload are
                // gated on `isLoadingDataset`, so without this the whole open
                // runs in silence while `activate` reports "Loaded …" with the
                // bar at 1.0 — #36's stall, one layer down.
                //
                // **Unreachable today**: nothing calls `openManualPath`. Fixed
                // anyway, because the trap is laid for whoever wires it to a
                // control, and at that point the silence would look like a new
                // defect rather than an old one. Found by `/code-review ultra`,
                // 2026-08-18.
                beginDatasetLoading("Opening \(descriptor.datasetPath)…")
                await activate(descriptor: descriptor, reader: h5)
                finishDatasetLoading()
            } catch {
                present(error)
            }
        }
    }

    func selectScan(x: Int, y: Int) {
        if navigation.analysisMode == .acom, acomSession.scope == .selectedRegion {
            acomSession.regionSelectionActive = true
        }
        selectedScan = ScanPos(x: x, y: y)
        persistRecoveryPosition()
        Task { await loadCurrentPattern() }
    }

    /// Session-level failure (file open/read, dataset activation, export
    /// write): raises the window-modal "Something went wrong" alert in
    /// addition to the status bar + log.
    func present(_ error: Error) {
        errorMessage = error.localizedDescription
        statusText = "Error: \(error.localizedDescription)"
    }

    /// Recoverable compute failure (an analysis step that did not converge or
    /// whose preconditions are not met, e.g. no strain basis found): surfaces
    /// on the existing non-blocking status bar + log pane only, so the rest
    /// of the window stays usable (docs/ui-workflow-backlog.md #9).
    ///
    /// A data-source failure that reaches a compute catch block (corrupted or
    /// vanished file mid-scan) is NOT a compute failure — it invalidates the
    /// session, so it escalates to the modal path regardless of which stage
    /// surfaced it.
    func presentComputeFailure(_ error: Error) {
        if isDataSourceFailure(error) {
            present(error)
            return
        }
        statusText = "Error: \(error.localizedDescription)"
    }

    private func isDataSourceFailure(_ error: Error) -> Bool {
        // A tile-read failure WRAPS its data-source error (v2 S7's typed
        // attribution) — judge the wrapped error, or a mid-scan HDF5 failure
        // would stay off the modal path precisely because S7 gave it a type
        // (Gate B, 2026-08-25).
        if case DiskDetection.FullScanError.tileRead(_, let underlying) = error {
            return isDataSourceFailure(underlying)
        }
        if error is H5Error || error is DM4Error || error is VendorRawError
            || error is FourDError {
            return true
        }
        let ns = error as NSError
        return ns.domain == NSCocoaErrorDomain || ns.domain == NSPOSIXErrorDomain
    }

    private func openFileAsync(url: URL) async {
        beginDatasetLoading("Opening \(url.lastPathComponent)…")
        errorMessage = nil
        defer {
            if isLoadingDataset { finishDatasetLoading() }
        }

        let previousOpenURL = openURL
        let accessed = url.startAccessingSecurityScopedResource()

        do {
            let reader = try await Self.makeReader(for: url)
            beginDatasetLoadingStage("Reading file structure of \(url.lastPathComponent)…")
            let descriptor = try await reader.discoverPrimaryDataset()
            if datasetLoadWasCancelled {
                if accessed { url.stopAccessingSecurityScopedResource() }
                await discardPartialLoad()
                finishDatasetLoading()
                return
            }
            if let previousOpenURL {
                previousOpenURL.stopAccessingSecurityScopedResource()
            }
            sessionSidecar.release()
            // Paired with every `release()`: the restore-failure gate must
            // never outlive the dataset it describes. // v2 S7
            gates.clearSidecarRestoreFailure()
            openURL = accessed ? url : nil
            self.reader = reader
            datasets = [descriptor]
            let recorded = await recordedLoadSpecification(
                forSourcePath: url.path, source: descriptor
            )
            await activate(
                descriptor: descriptor, reader: reader,
                specification: recorded ?? .fullExtent,
                runInitialAnalysis: false
            )
            if datasetLoadWasCancelled || !hasDataset {
                // `activate` unwinds itself on cancellation; this catches the
                // case where it did, and stops the open continuing into an
                // analysis of a dataset that is no longer there.
                await discardPartialLoad()
                finishDatasetLoading()
                return
            }
            // The first whole-cube pass IS part of opening, from the user's
            // point of view: the welcome card is still on screen and the
            // workspace has no image yet. Finishing the load before it ran was
            // what left the bar parked at its last stage and then vanishing
            // into a generic operation indicator.
            await runCurrentAnalysis()
            if datasetLoadWasCancelled {
                await discardPartialLoad()
                finishDatasetLoading()
                return
            }
            // REMEMBERED ONLY ONCE THE LOAD HAS ACTUALLY FINISHED. Moved here
            // from before the whole-cube pass so that a cancel at any point
            // leaves Recents untouched — a cancelled file is one you did not
            // want, and putting it at the top of the list is backwards.
            rememberOpenedDataset(url)
            finishDatasetLoading()
        } catch {
            if accessed { url.stopAccessingSecurityScopedResource() }
            present(error)
        }
    }

    private func activate(
        descriptor sourceDescriptor: DatasetDescriptor,
        reader: any FourDDataSource,
        specification: LoadSpecification = .fullExtent,
        runInitialAnalysis: Bool = true
    ) async {
        guard sourceDescriptor.is4D else {
            present(H5Error.unsupportedRank(sourceDescriptor.shape.count))
            return
        }

        // Dataset replacement is also a cancellation boundary. The epoch still
        // independently prevents any non-cooperative GPU result from landing.
        operationCenter.reset()
        if !isBusy { progress = nil }
        datasetEpoch &+= 1
        beginDatasetLoadingStage("Reading calibration metadata…")
        // ONE view, built once and shared: the array reads through it, the
        // calibration is re-referenced into it, and `loadedView` records it. The
        // specification is `.fullExtent` on every shipped path — L5's
        // configurator is what will hand a real one in.
        // The specification is `.fullExtent` on every path except L5's
        // configurator. A specification that does not fit the source is a
        // caller error, not a user error — the configurator only offers ones it
        // has already validated — so falling back to full extent here would
        // silently load something other than what was asked for.
        let view: LoadView
        do {
            view = try LoadView(source: sourceDescriptor, specification: specification)
        } catch {
            present(error)
            return
        }
        self.descriptor = view.descriptor
        fourD = FourDArray(reader: reader, view: view)

        // EVERYTHING BELOW USES THE VIEW, and the parameter is deliberately
        // named `sourceDescriptor` so that reaching for the file's own extent is
        // something you have to type on purpose.
        //
        // The two are identical on every shipped path today, which is exactly
        // why this needed saying: an adversarial review on 2026-08-18 found four
        // detector-frame defaults still derived from the source, and a fifth —
        // the `minPeakSpacing` derivation — that this repo had already CLAIMED
        // followed the view. The unit test behind that claim called
        // `detectorAdapted` with a view descriptor directly, so it pinned the
        // function and not the call site. A crop or a bin would have made all
        // five wrong at once, and every one of them plausible.
        let descriptor = view.descriptor
        // A new array is a new (absent) buffer; the old cube dies with the old
        // array. Resetting here keeps the panel from claiming residency that
        // belonged to the previous dataset.
        residency.reset()
        loadedView.reset()
        sessionLoadSpecification = nil
        datasetPreview = nil
        selectedScan = ScanPos(x: 0, y: 0)
        displayRangeLo = 0
        displayRangeHi = 1
        resultGamma = 1
        patternDisplayRangeLo = 0
        patternDisplayRangeHi = 1
        patternGamma = 1
        lastRotationResult = nil
        calibrationSession.lastEllipseFit = nil
        parallaxPreprocess = nil
        parallaxAlignment = nil
        singleslicePtychography = nil
        parallaxResultProduct = .preprocess
        // THE VIEW'S detector, not the source's. These four are lengths and a
        // position in DETECTOR PIXELS, and a binned or cropped view has fewer
        // of them.
        //
        // They sat on `descriptor` — the source — until an adversarial review
        // found it on 2026-08-18. Unreachable then, because `activate` only ever
        // built a full-extent view, and a trap set for L5: on a 256 px detector
        // binned by 4 the "quarter of the detector" aperture would have come out
        // at 64 px on a 64 px detector, and `ellipseFitOuterRadius` at 115 px
        // entirely off it. Both are plausible-looking numbers, which is the
        // failure mode that matters here.
        //
        // `CalibrationReReference` takes the aperture CENTRE as a parameter on
        // the principle that every detector-frame rule belongs in one file.
        // These are defaults rather than re-referenced values — there is no
        // prior value to move — so they belong here, but they must be derived
        // from the same frame.
        let detectorHalfSize = Double(min(descriptor.qx, descriptor.qy)) / 2
        calibrationSession.ellipseFitInnerRadius = max(1, detectorHalfSize * 0.35)
        calibrationSession.ellipseFitOuterRadius = max(calibrationSession.ellipseFitInnerRadius + 2, detectorHalfSize * 0.9)
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
            calibrationSession.acceleratingVoltage = rawVoltage > 1_000 ? rawVoltage / 1_000 : rawVoltage
        } else {
            calibrationSession.acceleratingVoltage = nil
        }
        // The strain product dies BEFORE the calibration reset, not with the
        // other scan-indexed products further down: `activate` suspends on
        // reader awaits between here and those clears, the export menu item is
        // reachable during a suspension, and `currentResultPersistenceMetadata`
        // derives the strain frame keys from the LIVE calibration — so an
        // uncleared map would export the previous dataset's scan-frame pixels
        // under this reset's "rotation not calibrated" claim (Gate B finding 3,
        // 2026-08-25).
        strain.clear()
        // Same reasoning as `strain.clear()` above, one layer simpler: a Q
        // estimate and its self-check verdict describe dataset A's shells and
        // must not survive into dataset B's panel. // v2 S13
        qCalibration.clear()
        calibrationSession.calibration = Calibration()
        calibrationSession.provenance = CalibrationProvenance()
        clearSupersededFittedOrigin()
        // Pixel sizes from file metadata (DM4 tags or py4DSTEM EMD bundle).
        if let pc = await reader.pixelCalibration() {
            var rSize = pc.rSize
            var rUnits = pc.rUnits
            // Normalize µm → nm (STEM-scale bars read better in nm).
            if let r = rSize, ["µm", "um", "micron"].contains(rUnits?.lowercased() ?? "") {
                rSize = r * 1000
                rUnits = "nm"
            }
            calibrationSession.calibration.rPixelSize = rSize
            calibrationSession.calibration.rPixelUnits = rUnits
            calibrationSession.calibration.qPixelSize = pc.qSize
            calibrationSession.calibration.qPixelUnits = pc.qUnits
            if rSize.map({ $0.isFinite && $0 > 0 }) == true {
                calibrationSession.provenance.rScale = .importedFile
            }
            if pc.qSize.map({ $0.isFinite && $0 > 0 }) == true {
                calibrationSession.provenance.qScale = .importedFile
            }
            if let flip = pc.qrFlip { calibrationSession.calibration.transposeQR = flip }
            calibrationSession.calibration.rotationRad = pc.qrRotationRad.map(Float.init)
            calibrationSession.calibration.probeRadius = pc.probeSemiangle.map(Float.init)
            calibrationSession.calibration.ellipseA = pc.ellipseA
            calibrationSession.calibration.ellipseB = pc.ellipseB
            calibrationSession.calibration.ellipseTheta = pc.ellipseTheta
            if calibrationSession.calibration.hasRotation { calibrationSession.provenance.rotation = .importedFile }
            if calibrationSession.calibration.probeRadius.map({ $0.isFinite && $0 > 0 }) == true {
                calibrationSession.provenance.probe = .importedFile
            }
            if calibrationSession.calibration.hasEllipse { calibrationSession.provenance.ellipse = .importedFile }
            // AXIS SWAP (single documented conversion point — see
            // PixelCalibration.qx0Mean/qy0Mean doc comment): py4DSTEM indexes
            // patterns (qx, qy) with qx as the first/row axis, which is this
            // app's detector y; qy is the second/column axis, this app's x.
            // So app aperture x = qy0Mean, app aperture y = qx0Mean.
            if let qx0 = pc.qx0Mean, let qy0 = pc.qy0Mean {
                aperture.centerX = Float(qy0)
                aperture.centerY = Float(qx0)
                // v2 S13: the value gets a HOME, not just a provenance label.
                // Until now it lived only in the aperture, so it was lost the
                // moment the user moved the detector and every analysis fell
                // through to the detector's geometric middle while the
                // inspector went on displaying the file's origin (S11).
                calibrationSession.calibration.recordedOriginX = Float(qy0)
                calibrationSession.calibration.recordedOriginY = Float(qx0)
                calibrationSession.calibration.originProvenance = .fileMean
            }
            // Full py4DSTEM origin maps use real-space order [R_Nx, R_Ny],
            // matching app [Ry, Rx]. Detector coordinates still need the one
            // documented swap: py4DSTEM qx -> app y, qy -> app x.
            // Read at the SOURCE extent — a file's origin map describes the
            // whole scan, not the loaded crop — and moved into the view's frame
            // by `CalibrationReReference` below. Sizing this against the *view*
            // instead would fail the shape check and drop the origin silently,
            // which is the quiet-failure shape this stage exists to remove.
            if let maps = pc.originMaps,
               let appMaps = maps.appOriginMaps(width: sourceDescriptor.rx,
                                                height: sourceDescriptor.ry) {
                calibrationSession.calibration.origin = appMaps
                if let origin = calibrationSession.calibration.meanOrigin {
                    aperture.centerX = origin.x
                    aperture.centerY = origin.y
                }
                calibrationSession.calibration.originProvenance = .fileMaps
            }
        }

        // MOVE THE CALIBRATION INTO THE LOADED FRAME, or lose the values that
        // cannot make the trip — with a named reason for each.
        //
        // Everything above read the file at its SOURCE extent, because that is
        // what the file describes. This is the single point where those values
        // become values *about the view*. At full extent it is the identity, so
        // the shipped path is unchanged; it stops being the identity the moment
        // L5's configurator hands `activate` a real specification.
        //
        // The rules are in `CalibrationReReference`, deliberately not here: they
        // are pure geometry and they are testable without an AppState.
        let reReferenced = CalibrationReReference.apply(
            view, to: calibrationSession.calibration, provenance: calibrationSession.provenance,
            apertureCenter: .init(x: aperture.centerX, y: aperture.centerY)
        )
        calibrationSession.calibration = reReferenced.calibration
        calibrationSession.provenance = reReferenced.provenance
        if let center = reReferenced.apertureCenter {
            aperture.centerX = center.x
            aperture.centerY = center.y
        } else {
            // The beam is not inside the diffraction crop. Fall back to the
            // geometric default rather than leaving the aperture pointed at a
            // detector pixel that is no longer loaded.
            aperture.centerX = Float(view.descriptor.qx) / 2
            aperture.centerY = Float(view.descriptor.qy) / 2
            calibrationSession.calibration.originProvenance = .geometricDefault
        }
        loadedView.publish(
            view: view,
            pushdown: reader.loadPushdown(for: view),
            outcome: reReferenced
        )

        patternDisplayMode = .current
        meanPattern = nil
        maxPattern = nil
        publishedProduct = nil
        scanNavigationImage = nil
        scanNavigationVersion = 0
        sessionInventory = .empty
        sessionLoadSpecification = nil
        // The recipe belongs to the session it was built in. A restore of the
        // NEW dataset's sidecar re-adopts its own record two stages later —
        // this only guarantees the previous dataset's recipe cannot leak
        // into it. // v2 S5
        replay.reset()
        // The previous dataset's promote-run summary would be misread under a
        // new dataset. No-op while a run executes — the executor sees the
        // epoch change and halts through `finish`, keeping the keep-awake
        // release on its one path. // v2 S6
        replayRun.clearUnlessRunning()
        // Viewer-level inspection state belongs to the product being inspected,
        // not to the app. Left set, it carried a previous dataset's "show me the
        // fit residual instead" into a fresh file.
        inspectQualityField = false
        comField = nil
        probeKernel = nil
        braggVectors = nil
        completedDiskParams = nil
        completedDiskSummary = nil
        braggPeakCount = nil
        currentPeaks = []
        currentDiskDiagnostics = nil
        // L3 step 3 — "a real-space crop makes existing scan-indexed results
        // AMBIGUOUS, not stale" — is satisfied here rather than by a second
        // mechanism, and deliberately so. Changing the load specification is a
        // *reopen* (docs/v2-scope.md §6.1), a reopen runs `activate`, and
        // `activate` already clears every scan-indexed product below. What the
        // user needed and did not have is the *reason*, which
        // `loadedView.invalidatedCalibration` now carries. Adding a separate
        // invalidation pass would be a second code path clearing the same state.
        // (Strain cleared earlier, before the calibration reset — see the
        // Gate B finding 3 comment above the `calibration = Calibration()`
        // line.)
        acomSession.orientationPlan = nil
        acomSession.orientationMap = nil
        acomSession.hasOrientationPlan = false
        acomSession.hasOrientationMap = false
        acomSession.modelSelection = .none
        acomSession.lastRunScope = nil
        acomSession.lastRunQuality = nil
        acomSession.lastRunSemantics = nil
        acomSession.lastMatchedPositionCount = nil
        acomSession.lastPositionsPerSecond = nil
        acomSession.lastEndToEndDuration = nil
        acomLastMeasuredTemplateCount = nil
        acomLastMeasuredBackend = nil
        acomSession.regionSelectionActive = false
        acomSession.scope = .preview
        acomSession.displayIsUserChosen = false
        realSpaceDisplayOrientation = .identity
        realSpaceDisplayMirrored = false
        acomSession.regionRadius = max(8, min(descriptor.rx, descriptor.ry) / 12)
        activePane = .diffraction
        realSpaceShape = .point
        virtualDiffractionPattern = nil
        realSpaceRadius = Float(max(3, min(descriptor.rx, descriptor.ry) / 12))
        navigation.workspaceArea = .prepare

        // Seeded with the probe radius when the file already carried one (an
        // imported py4DSTEM/EMD calibration), so an import that never runs
        // Origin calibration still gets a probe-scaled minimum spacing. Read
        // after `probeKernel = nil` above, so this cannot pick up the previous
        // dataset's kernel radius.
        diskParams = .detectorAdapted(
            qy: descriptor.qy, qx: descriptor.qx, probeRadius: fittedProbeRadius
        )

        if let recovery = pendingRecovery,
           recovery.datasetID == URL(fileURLWithPath: descriptor.filePath).standardizedFileURL.path,
           // The position is applied only when it is honest in THIS view —
           // same frame, inside the extents. The old clamp forced a
           // full-extent position (e.g. persisted after a promote) into a
           // crop-restored view: a defensible pixel the user never chose
           // (S3's carried finding, fixed v2 S5). No position beats a
           // manufactured one.
           let position = recovery.position(
               inViewWith: loadedView.specification,
               rx: descriptor.rx, ry: descriptor.ry
           ) {
            selectedScan = ScanPos(x: position.x, y: position.y)
            // The remembered task is restored, but the WORKSPACE is not: a
            // reopened dataset always lands on Prepare. Dropping the user back
            // into Map or Reconstruct started them mid-flow, past the step that
            // confirms the dataset and its calibration are what they think —
            // and calibration is per-session state that the recovery record
            // does not carry. Reported by the release owner 2026-08-05.
            if let mode = AnalysisMode(rawValue: recovery.analysisMode) {
                navigation.analysisMode = mode
            }
        }
        pendingRecovery = nil

        if datasetLoadWasCancelled { await discardPartialLoad(); return }
        beginDatasetLoadingStage("Checking for a saved session…")
        let sessionSnapshot = await loadSessionSnapshot(for: descriptor)
        beginDatasetLoadingStage("Loading first diffraction pattern…")
        await loadCurrentPattern()
        if let sessionSnapshot {
            restoreSessionResult(from: sessionSnapshot, for: descriptor)
        }
        if isLoadingDataset {
            // statusText is about to be driven by the measured whole-cube pass;
            // don't flash a finished-looking bar in the performance panel first.
            beginDatasetLoadingStage("Preparing workspace…")
        } else {
            statusText = "Loaded \(descriptor.fileName) at \(descriptor.datasetPath)"
            progress = 1
        }
        if datasetLoadWasCancelled { await discardPartialLoad(); return }
        await buildDatasetPreview()
        if datasetLoadWasCancelled { await discardPartialLoad(); return }
        await preloadResidentCube()
        if datasetLoadWasCancelled { await discardPartialLoad(); return }
        if runInitialAnalysis {
            await runCurrentAnalysis()
        }
    }

    /// Sample a cheap preview before the expensive passes, so the open shows
    /// something real early. Bounded by a byte budget rather than a fixed grid,
    /// so the wait is roughly the same on a 64² and a 512² detector.
    ///
    /// Failure is not fatal and not reported: a preview is a convenience, and an
    /// error dialog for one would interrupt an open that is otherwise fine. It
    /// simply stays nil and no preview section appears.
    private func buildDatasetPreview() async {
        guard let fourD, let d = descriptor, d.is4D else { return }
        let epoch = datasetEpoch
        beginDatasetLoadingStage("Sampling a preview…")
        let preview = try? await DatasetPreviewBuilder.make(
            data: fourD, descriptor: d,
            cancellation: datasetLoadCancellation,
            progress: previewProgressHandler(
                rows: DatasetPreviewBuilder.sampledRowCount(for: d),
                epoch: epoch
            )
        )
        guard datasetEpoch == epoch else { return }
        datasetPreview = preview
    }

    /// Hold the cube in memory when this machine admits it, before the first
    /// whole-cube pass so that pass benefits from it.
    ///
    /// Reported in the same two quantities L1 established — patterns and MB —
    /// because on a multi-gigabyte cube this read is the longest single phase
    /// of the whole open. A silent preload would reintroduce the stall L1 just
    /// removed, one layer down (invariant I5). It is a *distinct* phase from
    /// the one L1 wired: L1 routes the first analysis pass, this is the read
    /// into the buffer that happens before it.
    ///
    /// Does nothing visible when the cube is not admitted, which today is
    /// always — the shipped default request is `.streamed` (`.automatic` was
    /// dropped, v2 S3), and nothing in the UI requests `.resident` yet.
    private func preloadResidentCube() async {
        guard let fourD, let d = descriptor else { return }
        let totalPatterns = d.ry * d.rx
        guard totalPatterns > 0 else { return }
        await residency.preload(fourD, cancellation: datasetLoadCancellation) { [weak self] fraction in
            guard let self, self.isLoadingDataset else { return }
            let processed = min(
                totalPatterns, max(0, Int((fraction * Double(totalPatterns)).rounded()))
            )
            self.reportDatasetLoadingProgress(
                fraction,
                Self.scanProgressStatus(
                    "Loading into memory", processed: processed,
                    total: totalPatterns, descriptor: d
                )
            )
        }
    }

    /// Give the cube's memory back. Streaming resumes on the next pass, with
    /// identical numbers — the parity harness asserts exactly that.
    func releaseResidentCube() async {
        await residency.release(fourD)
    }

    /// Unwind a cancelled open back to the welcome screen.
    ///
    /// **The failure mode this is written against is a half-loaded dataset that
    /// LOOKS loaded** — an inspector showing dimensions and a calibration for a
    /// cube whose pixels were never read. That would be worse than having no
    /// cancel at all, because every number computed afterwards would be about
    /// data the app never finished reading.
    ///
    /// The invariant that makes it tractable: `hasDataset` is
    /// `descriptor?.is4D == true`, and every workspace view is gated on the
    /// descriptor. So clearing the descriptor is what returns the app to the
    /// welcome screen, and the rest of this is releasing what was already
    /// allocated rather than hiding it.
    /// Internal rather than private **so the invariant can be tested**: the
    /// value of this function is entirely in what it leaves behind, and a test
    /// that could not call it would be testing the button instead of the
    /// property.
    func discardPartialLoad() async {
        if let fourD { await residency.release(fourD) }
        residency.reset()
        loadedView.reset()
        fourD = nil
        reader = nil
        descriptor = nil
        datasets = []
        datasetPreview = nil
        calibrationSession.calibration = Calibration()
        calibrationSession.provenance = CalibrationProvenance()
        // Every path that resets the calibration resets the Q run with it: an
        // estimate outlives the dataset it describes otherwise. The two are
        // adjacent here on purpose, so a third reset path is hard to add
        // without noticing. // v2 S13
        qCalibration.clear()
        // A cancelled open must not be remembered — the release owner's call,
        // 2026-08-18: you cancelled because it was the wrong file, so promoting
        // it to the top of Recents is precisely backwards. `openFileAsync` also
        // defers `rememberOpenedDataset` until the load has actually finished,
        // so on the normal path there is nothing here to undo.
        if let openURL {
            openURL.stopAccessingSecurityScopedResource()
            self.openURL = nil
        }
        sessionSidecar.release()
        gates.clearSidecarRestoreFailure() // paired with release() // v2 S7
        datasetEpoch &+= 1
        operationCenter.reset()
        statusText = "Load cancelled"
    }

    private func beginDatasetLoading(_ status: String) {
        isLoadingDataset = true
        datasetLoadCancellation = AnalysisCancellationToken()
        isCancellingDatasetLoad = false
        operationCenter.setBusy(true)
        progress = nil
        datasetLoadingProgress = nil
        datasetLoadingStatus = status
        statusText = status
    }

    private func finishDatasetLoading() {
        isLoadingDataset = false
        datasetLoadCancellation = nil
        isCancellingDatasetLoad = false
        operationCenter.setBusy(false)
        progress = nil
        datasetLoadingProgress = nil
        datasetLoadingStatus = nil
    }

    /// A named phase with no knowable denominator: spinner, no percentage.
    /// Deliberately does **not** fabricate a fraction — see the
    /// `datasetLoadingProgress` doc comment.
    private func beginDatasetLoadingStage(_ status: String) {
        guard isLoadingDataset else { return }
        datasetLoadingProgress = nil
        if activeOperation == nil { progress = nil }
        datasetLoadingStatus = status
        statusText = status
    }

    /// A measured phase: `fraction` must come from work actually completed,
    /// never from an estimate of how far through the open we probably are.
    private func reportDatasetLoadingProgress(_ fraction: Double, _ status: String) {
        guard isLoadingDataset else { return }
        let clipped = min(1, max(0, fraction))
        datasetLoadingProgress = clipped
        datasetLoadingStatus = status
        if activeOperation == nil { progress = clipped }
        statusText = status
    }

    private func loadSessionSnapshot(
        for descriptor: DatasetDescriptor
    ) async -> SessionSidecarSnapshot? {
        // D4: a one-shot, identity-stamped skip. Consumed unconditionally so
        // it cannot linger past this open; honored only when it names the
        // dataset actually being opened.
        if let ignored = ignoreSessionForDatasetID {
            ignoreSessionForDatasetID = nil
            if ignored == URL(fileURLWithPath: descriptor.filePath).standardizedFileURL.path {
                statusText = "Opened without the saved session — the sidecar file is untouched"
                return nil
            }
        }
        let url = sessionSidecar.location(for: descriptor)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let epoch = datasetEpoch
        do {
            let snapshot = try await Task.detached(priority: .utility) {
                try BraggVectorEMDWriter.loadSession(from: url)
            }.value
            guard epoch == datasetEpoch else { return nil }
            sessionInventory = snapshot.inventory
            sessionLoadSpecification = snapshot.loadSpecification ?? .fullExtent
            // A colleague's recipe becomes this session's starting point, so
            // a later save round-trips it instead of replacing it. Nil (no
            // recorded recipe) leaves the live record alone. // v2 S5
            // The recipe's parameters are expressed in the frame of the
            // sidecar's OWN recorded specification — not the view being
            // opened, which can legitimately differ after a reconfigure.
            // // v2 S6
            replay.adopt(snapshot.replayRecord,
                         recordedOn: ReplayParameterFrame.of(snapshot.loadSpecification))
            if let sessionCalibration = snapshot.calibration {
                applySessionCalibration(
                    sessionCalibration,
                    recordedOn: snapshot.loadSpecification ?? .fullExtent,
                    for: descriptor
                )
            }
            return snapshot
        } catch {
            guard epoch == datasetEpoch else { return nil }
            // The DURABLE channel, not only `statusText` — S1 measured
            // `statusText` set here being overwritten within the same
            // `activate` (three times). The minimum-reader refusal in
            // particular exists to be READ: without this, a too-new sidecar
            // opens as a dataset with no results and no reason
            // (Gate B-lite F7). // v2 S5
            sessionSidecar.noteUnreadable(
                "Could not restore \(url.lastPathComponent): \(error.localizedDescription)"
            )
            statusText = "Could not restore \(url.lastPathComponent): \(error.localizedDescription)"
            return nil
        }
    }

    private func applySessionCalibration(
        _ saved: PixelCalibration, recordedOn sessionSpecification: LoadSpecification,
        for descriptor: DatasetDescriptor
    ) {
        // P2 (Gate D, 2026-09-01): the sidecar's values are in ITS view's
        // frame, and this function used to adopt them raw regardless of what
        // is loaded now — a full-extent session restored onto a 2× binned
        // open put the aperture centre a whole frame off (the corner BF) and
        // fed strain a doubled-frame Q scale. Policy first; geometry, when
        // owed, through the same engine the file path uses (below).
        let framePolicy = SessionCalibrationFramePolicy.decide(
            session: sessionSpecification, loaded: loadedView.specification
        )
        if case .refuse(let reason) = framePolicy {
            loadedView.appendInvalidated([
                CalibrationInvalidation(field: .sessionCalibration, reason: reason)
            ])
            statusText = "Session calibration not adopted — it was recorded on a different view"
            return
        }
        // PHASES 1–2 (P2): pure translation — the sidecar's values into
        // their own frame, then through the engine when the policy says so.
        // Extracted to `SessionCalibrationTranslation` because the unit gate
        // stayed green across a known-flawed intermediate of this very code:
        // the wiring needs its own pins. Running the engine over the MERGED
        // live state instead would re-reference file-carried fields a second
        // time — the double-application caught in this fix's own review.
        guard let translated = SessionCalibrationTranslation.translate(
            saved: saved, policy: framePolicy, view: loadView, descriptor: descriptor
        ) else {
            // Unreachable by construction: a non-identity policy implies a
            // reduced loaded view, which only exists with a live LoadView.
            assertionFailure("reReference policy with no active LoadView")
            return
        }
        let mapped = translated.calibration
        let mappedCenter = translated.center
        let restoredMaps = translated.restoredMaps
        let sessionInvalidated = translated.invalidated
        if !sessionInvalidated.isEmpty {
            loadedView.appendInvalidated(sessionInvalidated)
        }

        // PHASE 3: merge — only the fields the sidecar actually carried, from
        // the mapped snapshot. Validity checks stay on the SAVED values
        // (finiteness and sign are frame-invariant under crop and bin).
        if let value = saved.rSize {
            calibrationSession.calibration.rPixelSize = mapped.rPixelSize
            calibrationSession.provenance.rScale = value.isFinite && value > 0 ? .sessionSidecar : nil
        }
        if saved.rUnits != nil { calibrationSession.calibration.rPixelUnits = mapped.rPixelUnits }
        if let value = saved.qSize {
            calibrationSession.calibration.qPixelSize = mapped.qPixelSize
            calibrationSession.provenance.qScale = value.isFinite && value > 0 ? .sessionSidecar : nil
        }
        if saved.qUnits != nil { calibrationSession.calibration.qPixelUnits = mapped.qPixelUnits }
        if saved.qrFlip != nil { calibrationSession.calibration.transposeQR = mapped.transposeQR }
        if let value = saved.qrRotationRad {
            calibrationSession.calibration.rotationRad = mapped.rotationRad
            calibrationSession.provenance.rotation = value.isFinite ? .sessionSidecar : nil
        }
        if let value = saved.probeSemiangle,
           !sessionInvalidated.contains(where: { $0.field == .probeRadius }) {
            calibrationSession.calibration.probeRadius = mapped.probeRadius
            calibrationSession.provenance.probe = value.isFinite && value > 0 ? .sessionSidecar : nil
            refreshDiskDefaultsForMeasuredProbe()
        }
        let savedEllipseCount = [saved.ellipseA, saved.ellipseB, saved.ellipseTheta]
            .compactMap { $0 }.count
        if savedEllipseCount > 0,
           !sessionInvalidated.contains(where: { $0.field == .ellipse }) {
            if saved.ellipseA != nil { calibrationSession.calibration.ellipseA = mapped.ellipseA }
            if saved.ellipseB != nil { calibrationSession.calibration.ellipseB = mapped.ellipseB }
            if saved.ellipseTheta != nil { calibrationSession.calibration.ellipseTheta = mapped.ellipseTheta }
            calibrationSession.provenance.ellipse = calibrationSession.calibration.hasEllipse
                ? (savedEllipseCount == 3 ? .sessionSidecar : .mixed)
                : nil
        }
        if restoredMaps, mapped.origin != nil {
            calibrationSession.calibration.origin = mapped.origin
            calibrationSession.calibration.originProvenance = .sessionMaps
            if let center = mappedCenter {
                aperture.centerX = center.x
                aperture.centerY = center.y
            }
        }
        // Engine-invalidated maps are already surfaced through
        // `appendInvalidated` above; the live origin is left untouched then.
        if !restoredMaps, saved.qx0Mean != nil, saved.qy0Mean != nil,
           !sessionInvalidated.contains(where: { $0.field == .origin }) {
            calibrationSession.calibration.origin = nil
            calibrationSession.calibration.recordedOriginX = mapped.recordedOriginX
            calibrationSession.calibration.recordedOriginY = mapped.recordedOriginY
            calibrationSession.calibration.originProvenance = .sessionMean
            if let center = mappedCenter {
                aperture.centerX = center.x
                aperture.centerY = center.y
            }
        }
        // No strain-display refresh here, deliberately (Gate B finding 4,
        // 2026-08-25): this function's only caller chain is
        // `loadSessionSnapshot` ← `activate`, which always runs after
        // `strain.clear()` — a refresh would be unconditionally the guarded
        // no-op. The S4 Change… path never adopts a calibration in-session
        // (it retargets the file and asks for a reopen). If an in-session
        // "adopt calibration" path is ever added, it must refresh the strain
        // display itself — the live sites are `calibrateRotation` and
        // `flipRotation180`. // v2 S8
    }

    private func restoreSessionResult(
        from snapshot: SessionSidecarSnapshot, for descriptor: DatasetDescriptor
    ) {
        let url = sessionSidecar.location(for: descriptor)
        if let map = snapshot.currentResult {
            publishRestoredProduct(   // v2.5 step 3b-6
                kind: map.kind, displayName: map.displayName, valueUnits: map.valueUnits,
                payload: .scalar(FloatImage(width: map.width, height: map.height, pixels: map.pixels)),
                pixelSizeRow: map.pixelSizeRow, pixelSizeColumn: map.pixelSizeColumn,
                pixelUnits: map.pixelUnits, provenance: map.provenance)
        } else if let map = snapshot.currentRGBAResult {
            guard map.width == descriptor.rx, map.height == descriptor.ry else {
                statusText = "Ignored \(url.lastPathComponent): saved RGBA map is \(map.width) × \(map.height), expected \(descriptor.rx) × \(descriptor.ry)"
                return
            }
            publishRestoredProduct(   // v2.5 step 3b-6
                kind: map.kind, displayName: map.displayName, valueUnits: map.valueUnits,
                payload: .rgba(RGBAImage(width: map.width, height: map.height, rgba: map.rgba)),
                pixelSizeRow: map.pixelSizeRow, pixelSizeColumn: map.pixelSizeColumn,
                pixelUnits: map.pixelUnits, provenance: map.provenance)
        } else {
            return
        }
        resultVersion &+= 1
        statusText = "Restored \(publishedProduct?.displayName ?? "result") ← \(url.lastPathComponent)"
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
        switch navigation.analysisMode {
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
            if strain.map != nil { applyStrainDisplay() }
        case .ptychography:
            if parallaxAlignment != nil { showParallaxProduct(.alignment) }
            else if parallaxPreprocess != nil { showParallaxProduct(.preprocess) }
        case .singleslicePtychography:
            if singleslicePtychography != nil { showParallaxProduct(.iterativePhase) }
        case .acom:
            if acomSession.orientationMap != nil { applyACOMDisplay() }
        }
    }

    /// Ensure ACOM region selection has a real-space canvas even when a
    /// recovered session opened directly into Map and never formed a virtual
    /// image. A quiet ADF image gives structural contrast without replacing the
    /// retained scientific result.
    /// Quietly build persistent real-space context used for region selection
    /// and for detector/reconstruction products. Failure is non-fatal because
    /// the primary scientific result remains usable without the convenience.
    func ensureScanNavigator() async {
        guard scanNavigationImage == nil,
              let fourD, let descriptor else { return }
        let d = descriptor
        let qRadius = Float(min(d.qx, d.qy)) / 2
        let center = calibrationSession.calibration.meanOrigin
            ?? (x: Float(d.qx) / 2, y: Float(d.qy) / 2)
        do {
            let epoch = datasetEpoch
            let image = try await VirtualDetector.tiledImage(
                data: fourD, descriptor: d,
                shape: .annulus(
                    centerX: center.x, centerY: center.y,
                    inner: 0.25 * qRadius, outer: 0.55 * qRadius
                )
            )
            guard epoch == datasetEpoch else { return }
            scanNavigationImage = image
            scanNavigationVersion &+= 1
        } catch {
            // Region selection can still use steppers if the reference image
            // cannot be formed; do not turn a navigation convenience into a
            // blocker for an otherwise valid ACOM run.
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

    /// Fitted origin maps displaced by a manual aperture-center drag. Kept
    /// out of `calibration` so export honesty holds (a manual center never
    /// silently coexists with stale maps) while an accidental nudge stays
    /// recoverable via Restore Fitted Origin.
    @ObservationIgnored private var supersededFittedOrigin:
        (maps: OriginMaps, provenance: OriginProvenance)?
    private(set) var canRestoreFittedOrigin = false

    private func clearSupersededFittedOrigin() {
        supersededFittedOrigin = nil
        canRestoreFittedOrigin = false
    }

    /// Undo a manual center that displaced fitted origin maps: reinstate the
    /// maps with their original provenance and recenter the aperture on
    /// their mean.
    func restoreFittedOrigin() {
        guard let superseded = supersededFittedOrigin else { return }
        clearSupersededFittedOrigin()
        calibrationSession.calibration.origin = superseded.maps
        calibrationSession.calibration.originProvenance = superseded.provenance
        if let mean = calibrationSession.calibration.meanOrigin {
            aperture.centerX = mean.x
            aperture.centerY = mean.y
        }
        parallaxPreprocess = nil
        parallaxAlignment = nil
        statusText = "Fitted origin restored — \(superseded.provenance.displayName)"
        scheduleLiveVirtualDetector()
    }

    /// Live aperture edit during a drag: store, then recompute the real-space
    /// image continuously (coalesced, quiet — no status/busy churn).
    func updateAperture(_ newAperture: Aperture) {
        activePane = .diffraction
        if newAperture.centerX != aperture.centerX || newAperture.centerY != aperture.centerY {
            // A manual center supersedes fitted per-position maps. Retaining
            // those maps inside `calibration` would make export silently
            // ignore the manual value — so they move to the recoverable
            // superseded slot instead of being destroyed.
            if let displaced = calibrationSession.calibration.origin {
                supersededFittedOrigin = (displaced, calibrationSession.calibration.originProvenance)
                canRestoreFittedOrigin = true
                statusText = "Manual aperture center — fitted origin set aside (Restore Fitted Origin in Calibration undoes this)"
            }
            calibrationSession.calibration.origin = nil
            // The file's recorded mean goes with them. Gate B, 2026-08-28: v2
            // S13 gave that value a home of its own and then did not clear it
            // here, so `referenceOrigin` returned `.recordedMean` — the FILE's
            // number — while `originProvenance` read `.manual`, and the CoM
            // field and the measured probe kernel silently stopped using the
            // centre the user had just dragged to. Discarding it restores the
            // pre-S13 semantics exactly (the aperture was the only carrier
            // then, and moving it destroyed the value); it is not recoverable
            // through `supersededFittedOrigin`, which holds maps only.
            calibrationSession.calibration.recordedOriginX = nil
            calibrationSession.calibration.recordedOriginY = nil
            calibrationSession.calibration.originProvenance = .manual
            parallaxPreprocess = nil
            parallaxAlignment = nil
        }
        aperture = newAperture
        scheduleLiveVirtualDetector()
    }

    var manualQPixelUnits: String {
        CalibrationUnitConversion.canonicalEditableReciprocalUnit(
            calibrationSession.calibration.qPixelUnits
        ) ?? "nm⁻¹"
    }

    /// Do not place an imported `1 pixels/px` placeholder beside the manual
    /// physical-unit picker. Until the user supplies a physical unit/value,
    /// the action field is intentionally empty (rendered as zero by SwiftUI).
    var manualQPixelSize: Double? {
        guard CalibrationUnitConversion.canonicalEditableReciprocalUnit(
            calibrationSession.calibration.qPixelUnits
        ) != nil else { return nil }
        return calibrationSession.calibration.qPixelSize
    }

    var manualRPixelUnits: String {
        CalibrationUnitConversion.canonicalEditableRealUnit(
            calibrationSession.calibration.rPixelUnits
        ) ?? "nm"
    }

    var manualRPixelSize: Double? {
        guard CalibrationUnitConversion.canonicalEditableRealUnit(
            calibrationSession.calibration.rPixelUnits
        ) != nil else { return nil }
        return calibrationSession.calibration.rPixelSize
    }

    func setManualQPixelSize(_ value: Double) {
        parallaxPreprocess = nil
        parallaxAlignment = nil
        if value.isFinite && value > 0 {
            calibrationSession.calibration.qPixelSize = value
            // A manual number is entered beside a physical-unit picker. If the
            // file only supplied `pixels`, replace that index placeholder with
            // the picker's visible default instead of retaining pixels/px.
            calibrationSession.calibration.qPixelUnits = manualQPixelUnits
            calibrationSession.provenance.qScale = .manual
            acomSession.invalidateResult()
        } else {
            calibrationSession.calibration.qPixelSize = nil
            calibrationSession.provenance.qScale = nil
            acomSession.invalidateResult()
        }
    }

    func setManualQPixelUnits(_ units: String) {
        guard let canonical =
                CalibrationUnitConversion.canonicalEditableReciprocalUnit(units)
        else { return }
        parallaxPreprocess = nil
        parallaxAlignment = nil
        calibrationSession.calibration.qPixelUnits = canonical
        if calibrationSession.calibration.qPixelSize.map({ $0.isFinite && $0 > 0 }) == true {
            calibrationSession.provenance.qScale = .manual
        }
        acomSession.invalidateResult()
    }

    func setManualRPixelSize(_ value: Double) {
        parallaxPreprocess = nil
        parallaxAlignment = nil
        if value.isFinite && value > 0 {
            calibrationSession.calibration.rPixelSize = value
            calibrationSession.calibration.rPixelUnits = manualRPixelUnits
            calibrationSession.provenance.rScale = .manual
        } else {
            calibrationSession.calibration.rPixelSize = nil
            calibrationSession.provenance.rScale = nil
        }
    }

    func setManualRPixelUnits(_ units: String) {
        guard let canonical = CalibrationUnitConversion.canonicalEditableRealUnit(units)
        else { return }
        parallaxPreprocess = nil
        parallaxAlignment = nil
        calibrationSession.calibration.rPixelUnits = canonical
        if calibrationSession.calibration.rPixelSize.map({ $0.isFinite && $0 > 0 }) == true {
            calibrationSession.provenance.rScale = .manual
        }
    }

    func setManualAcceleratingVoltage(_ value: Double) {
        parallaxPreprocess = nil
        parallaxAlignment = nil
        calibrationSession.acceleratingVoltage = value.isFinite && value > 0 ? value : nil
        if CalibrationUnitConversion.normalized(calibrationSession.calibration.qPixelUnits) == "mrad" {
            acomSession.invalidateResult()
        }
    }

    private func scheduleLiveVirtualDetector() {
        guard navigation.analysisMode == .virtualDetector else { return }
        if vdInFlight { vdPending = true; return }
        vdInFlight = true
        Task {
            await runVirtualDetector(quiet: true)
            vdInFlight = false
            if vdPending { vdPending = false; scheduleLiveVirtualDetector() }
        }
    }

    func commitApertureChange() {
        guard navigation.analysisMode == .virtualDetector else { return }
        Task { await runVirtualDetector() }   // final pass, with status
    }

    /// Live scan-position scrub (drag in the real-space image). A point ROI
    /// streams the single pattern; a region ROI streams the summed pattern.
    func scrubTo(x: Int, y: Int) {
        guard let d = descriptor else { return }
        activePane = .realSpace
        if navigation.analysisMode == .acom, acomSession.scope == .selectedRegion {
            acomSession.regionSelectionActive = true
        }
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
    /// Derived from the same DetectorShape as virtual diffraction so both
    /// consumers select the identical pixel set (the previous hand-written
    /// circle predicate diverged from the ROI by half a pixel).
    private func realSpaceRegionMask(_ d: DatasetDescriptor) -> [Bool] {
        VirtualDetector.makeMask(
            shape: realSpaceRegionShape(d), qy: d.ry, qx: d.rx
        ).map { $0 != 0 }
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
        if navigation.analysisMode != .virtualDetector { navigation.analysisMode = .virtualDetector }
        Task { await runVirtualDetector() }
    }

    /// Status line for a whole-cube pass, in the two quantities a user can
    /// check against their own file: patterns read, and bytes read.
    ///
    /// Bytes are the **float32 working size** — what is actually streamed —
    /// not the on-disk size, which differs whenever the file's dtype is not
    /// float32 (a uint16 cube streams at twice its file size). Reporting the
    /// file size here would be the more flattering number and the wrong one.
    nonisolated static func count(_ value: Int) -> String {
        value.formatted(.number.locale(Locale(identifier: "en_US")))
    }

    nonisolated static func scanProgressStatus(
        _ verb: String, processed: Int, total: Int, descriptor d: DatasetDescriptor
    ) -> String {
        let bytesPerPattern = d.qy * d.qx * MemoryLayout<Float>.stride
        // Fixed grouping rather than the user's locale, because the byte string
        // beside it is itself unlocalized (`SystemMonitor.byteString` always
        // formats "3.96 GB" with a period decimal point). Locale grouping put
        // two meanings of "." in one line — on a German system this read
        // "1.378 / 16.218 patterns · 3.96 GB", where the first two periods
        // group and the third is a decimal point. One convention per line.
        let patterns = "\(Self.count(processed)) / \(Self.count(total)) patterns"
        let bytes = "\(SystemMonitor.byteString(processed * bytesPerPattern))"
            + " of \(SystemMonitor.byteString(total * bytesPerPattern))"
        return "\(verb) \(patterns) · \(bytes)"
    }

    private func virtualDetectorProgressTileRows(for descriptor: DatasetDescriptor) -> Int {
        let bytesPerScanRow = descriptor.rx * descriptor.qy * descriptor.qx * MemoryLayout<Float>.stride
        let targetBytes = 16 * 1024 * 1024
        return max(1, min(descriptor.ry, targetBytes / max(1, bytesPerScanRow)))
    }

    /// Virtual-detector imaging over the whole cube. The annulus uses the
    /// analytic fast path; rectangle/point use the general mask kernel. The
    /// blocking GPU call is pushed off the main actor.
    /// Returns the typed run verdict — `.published` exactly on the path that
    /// records the recipe step. `replaying` marks a replay-initiated run,
    /// whose recording is suppressed. S6's executor is the consumer;
    /// interactive call sites ignore both. // v2 S6
    @discardableResult
    func runVirtualDetector(quiet: Bool = false, replaying: Bool = false) async -> AnalysisRunOutcome {
        guard let fourD, let descriptor else { return .failed("No dataset is loaded") }
        let totalPatterns = descriptor.rx * descriptor.ry
        let scanVerb = isLoadingDataset ? "Scanning patterns" : "Computing virtual detector…"
        let cancellation = quiet ? nil : beginCancellableOperation(
            "Virtual detector",
            status: Self.scanProgressStatus(
                scanVerb, processed: 0, total: totalPatterns, descriptor: descriptor
            ),
            totalUnits: totalPatterns
        )
        defer {
            if let cancellation { finishCancellableOperation(cancellation) }
        }

        let ap = aperture
        let shapeMode = virtualShape
        let d = descriptor
        let maximumTileRows = virtualDetectorProgressTileRows(for: d)
        do {
            let epoch = datasetEpoch
            if cancellation?.isCancelled == true {
                statusText = "Virtual detector cancelled"
                return .cancelled
            }
            let progressUpdate: (@Sendable (Double) -> Void)?
            if let token = cancellation {
                progressUpdate = { @Sendable [weak self] fraction in
                    Task { @MainActor [weak self] in
                        guard let self, self.isCurrentOperation(token) else { return }
                        let clipped = min(1, max(0, fraction))
                        let processed = min(totalPatterns, max(0, Int((clipped * Double(totalPatterns)).rounded())))
                        self.updateCancellableOperation(
                            token,
                            progress: clipped,
                            status: Self.scanProgressStatus(
                                scanVerb, processed: processed,
                                total: totalPatterns, descriptor: d
                            )
                        )
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
                    maximumTileRows: maximumTileRows,
                    cancellation: cancellation, progress: progressUpdate)
            case .annulus:
                image = try await VirtualDetector.tiledRun(
                    data: fourD, descriptor: d, aperture: ap,
                    maximumTileRows: maximumTileRows,
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
                    maximumTileRows: maximumTileRows,
                    cancellation: cancellation, progress: progressUpdate)
            case .point:
                image = try await VirtualDetector.tiledImage(
                    data: fourD, descriptor: d,
                    shape: .point(x: Int(ap.centerX.rounded()),
                                  y: Int(ap.centerY.rounded())),
                    maximumTileRows: maximumTileRows,
                    cancellation: cancellation, progress: progressUpdate)
            }
            guard epoch == datasetEpoch else { return .failed("The dataset changed during the run") }
            if cancellation?.isCancelled == true {
                statusText = "Virtual detector cancelled"
                return .cancelled
            }
            resultColormap = .viridis
            scanNavigationImage = image
            scanNavigationVersion &+= 1
            resultVersion &+= 1
            // The product value — kind, name, units and status decided HERE,
            // by the site that computed the pixels, not re-derived later from
            // strings (v2.5 step 3). Mirrors `currentScalarResultMetadata`'s
            // `.virtualDetector` case until that switch is deleted.
            publishedProduct = DisplayedProduct(
                kind: "virtual_\(shapeMode.rawValue.lowercased())",
                displayName: "Virtual detector · \(shapeMode.rawValue)",
                payload: .scalar(image), domain: .scan,
                sampling: ProductSampling(
                    row: calibrationSession.calibration.rPixelSize, column: calibrationSession.calibration.rPixelSize,
                    units: calibrationSession.calibration.rPixelUnits),
                valueUnits: "intensity", quantitativeStatus: .relative,
                // The persistence provenance (aperture etc.) plus this site's own keys.
                provenance: currentResultPersistenceMetadata.provenance.merging(
                    ["display_domain": "scan", "quantitative_status": "relative",
                     "virtual_shape": shapeMode.rawValue]) { _, site in site })
            if !quiet {
                statusText = "Virtual detector ✓  (\(shapeMode.rawValue), \(d.rx) × \(d.ry))"
            }
            // The recipe step, recorded at the SUCCESS publish and nowhere
            // earlier — a cancelled or failed run is not part of the pipeline.
            // (An earlier comment here claimed the automatic pass on open
            // "counts too" — refuted: it runs with defaults and would
            // overwrite an adopted recipe; `recordReplayStep` suppresses it.)
            // // v2 S5
            recordReplayStep(kind: "virtual_detector", parameters: [
                "shape": shapeMode.rawValue,
                "center_x": String(ap.centerX), "center_y": String(ap.centerY),
                "inner": String(ap.inner), "outer": String(ap.outer),
            ], replaying: replaying)
            return .published
        } catch {
            if cancellation?.isCancelled == true {
                statusText = "Virtual detector cancelled"
                return .cancelled
            }
            if !quiet { presentComputeFailure(error) }
            return .failed(error.localizedDescription)
        }
    }

    // MARK: - Calibration

    /// First parallax slice: build and preview py4DSTEM's normalized virtual-BF
    /// stack and incoherent BF initialization. No iterative reconstruction is
    /// performed or implied by this operation.
    func prepareParallaxPreview() async {
        // The view the array actually reads, not a descriptor assembled beside
        // it: a crop and the shape it produces must travel together.
        guard let source = reader, let fourD, let descriptor else { return }
        let view = fourD.view
        let physical: ParallaxPhysicalCalibration
        do {
            physical = try ParallaxPhysicalCalibration.resolve(
                calibration: calibrationSession.calibration,
                apertureCenterX: aperture.centerX,
                apertureCenterY: aperture.centerY,
                acceleratingVoltageKV: calibrationSession.acceleratingVoltage
            )
        } catch {
            presentComputeFailure(error)
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
                source: source, view: view, calibration: physical,
                cancellation: token, progress: progressUpdate
            )
            guard isCurrentOperation(token), datasetEpoch == epoch,
                  !token.isCancelled else { return }
            parallaxPreprocess = result
            parallaxAlignment = nil
            showParallaxProduct(.preprocess)   // v2.5 step 3e: one publish site
            resultGamma = 1
            displayRangeLo = 0
            displayRangeHi = 1
            resultVersion &+= 1
            Task { await ensureScanNavigator() }
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
            presentComputeFailure(error)
        }
    }

    /// Run the next source-locked coarse-to-fine bin with factor-8 matrix-DFT
    /// correlation. The last completed level remains published until the next
    /// one succeeds and passes the operation/dataset publication guards.
    func alignParallaxNextLevel() async {
        guard let preprocessing = parallaxPreprocess else {
            presentComputeFailure(SimpleError("Prepare the parallax preview before alignment."))
            return
        }
        let schedule = ParallaxAligner.defaultBinSchedule(
            detectorIndices: preprocessing.detectorIndices
        )
        guard !schedule.isEmpty else {
            presentComputeFailure(SimpleError("The bright-field mask cannot form an alignment level."))
            return
        }
        let completed = parallaxAlignment?.completedBins ?? []
        guard completed.count < schedule.count else {
            presentComputeFailure(ParallaxAligner.AlignmentError.alignmentComplete)
            return
        }
        let bin = schedule[completed.count]
        guard parallaxAlignment == nil
                || Array(schedule.prefix(completed.count)) == completed else {
            presentComputeFailure(SimpleError("Reset the stale parallax alignment before continuing."))
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
            showParallaxProduct(.alignment)   // v2.5 step 3e: one publish site
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
            presentComputeFailure(error)
        }
    }

    func resetParallaxAlignment() {
        guard !isBusy, parallaxPreprocess != nil else { return }
        parallaxAlignment = nil
        showParallaxProduct(.preprocess)   // v2.5 step 3e: one publish site
        resultGamma = 1
        displayRangeLo = 0
        displayRangeHi = 1
        resultVersion &+= 1
        statusText = "Parallax alignment reset to the preprocessed preview"
    }

    func fitParallaxAberrations() {
        guard let preprocessing = parallaxPreprocess,
              let alignment = parallaxAlignment else {
            presentComputeFailure(SimpleError("Complete parallax preprocessing and alignment first."))
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
            presentComputeFailure(error)
        }
    }

    func upsampleParallaxBF() async {
        guard let preprocessing = parallaxPreprocess,
              let alignment = parallaxAlignment, alignment.isComplete else {
            presentComputeFailure(SimpleError("Complete parallax alignment before KDE upsampling."))
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
            showParallaxProduct(.subpixel)   // v2.5 step 3e: one publish site
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
            presentComputeFailure(error)
        }
    }

    func computeParallaxDepthSections() async {
        guard let preprocessing = parallaxPreprocess,
              let alignment = parallaxAlignment,
              let fit = parallaxHigherOrderFit else {
            presentComputeFailure(SimpleError("Fit parallax aberrations before depth sectioning."))
            return
        }
        guard parallaxDepthPlaneCount > 0, parallaxDepthPlaneCount <= 257,
              parallaxDepthStartAngstrom.isFinite,
              parallaxDepthEndAngstrom.isFinite else {
            presentComputeFailure(SimpleError("Use 1–257 finite parallax depth planes."))
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
            presentComputeFailure(error)
        }
    }

    func runSingleslicePtychography() async {
        // As in `prepareParallaxPreview`: take the view from the array, so the
        // reader is told where the shape it is given sits in the file.
        guard let source = reader, let fourD, let descriptor else {
            presentComputeFailure(SimpleError("Open a 4D dataset before ptychographic reconstruction."))
            return
        }
        let view = fourD.view
        let physical: ParallaxPhysicalCalibration
        do {
            physical = try ParallaxPhysicalCalibration.resolve(
                calibration: calibrationSession.calibration, apertureCenterX: aperture.centerX,
                apertureCenterY: aperture.centerY,
                acceleratingVoltageKV: calibrationSession.acceleratingVoltage
            )
        } catch {
            presentComputeFailure(error)
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
                source: source, view: view, calibration: physical,
                probeRadiusPixels: aperture.outer, cancellation: token,
                progress: prepareProgress
            )
            var options = SingleslicePtychographyOptions()
            options.method = ptychographyMethod
            options.iterations = ptychographyIterations
            options.stepSize = ptychographyStepSize
            options.projectionParameter = ptychographyProjectionParameter
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
                format: "Single-slice ptychography ✓  %@ · %d iterations · error %.6f",
                result.options.method.rawValue,
                result.errorHistory.count, result.errorHistory.last ?? .nan
            )
        } catch SingleslicePtychography.ReconstructionError.cancelled {
            guard isCurrentOperation(token) else { return }
            statusText = "Single-slice ptychography cancelled; prior result retained"
        } catch {
            guard isCurrentOperation(token), datasetEpoch == epoch else { return }
            presentComputeFailure(error)
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

    /// The one publish site for every parallax and ptychography product: the
    /// image and its label are chosen together (v2.5 step 3e, condition 2).
    func showParallaxProduct(_ product: ParallaxResultProduct) {
        let image: FloatImage?
        let kind: String, name: String, units: String
        switch product {
        case .preprocess:
            image = parallaxPreprocess?.previewImage
            (kind, name, units) = ("parallax_preprocess", "Parallax incoherent BF preview", "normalized_intensity")
        case .alignment:
            image = parallaxAlignment?.previewImage
            (kind, name, units) = ("parallax_alignment", "Parallax aligned BF", "normalized_intensity")
        case .subpixel:
            image = parallaxSubpixel?.croppedBF
            (kind, name, units) = ("parallax_subpixel_bf", "Parallax subpixel BF", "normalized_intensity")
        case .correctedPhase:
            image = parallaxCorrection?.correctedPhase
            (kind, name, units) = ("parallax_corrected_phase", "Parallax corrected phase", "arbitrary_phase")
        case .depth:
            image = parallaxDepth?.croppedPlane(at: parallaxDepthSelectedIndex)
            let depth = parallaxDepth?.depthsAngstrom[parallaxDepthSelectedIndex] ?? 0
            (kind, name, units) = ("parallax_depth", String(format: "Parallax depth %.1f Å", depth), "arbitrary_phase")
        case .iterativePhase:
            image = singleslicePtychography?.objectPhase()
            (kind, name, units) = ("ptychography_object_phase", "Ptychography object phase", "rad")
        case .iterativeAmplitude:
            image = singleslicePtychography?.objectAmplitude()
            (kind, name, units) = ("ptychography_object_amplitude", "Ptychography object amplitude", "dimensionless")
        case .iterativeProbePhase:
            image = singleslicePtychography?.probePhase()
            (kind, name, units) = ("ptychography_probe_phase", "Ptychography probe phase", "rad")
        case .iterativeProbeAmplitude:
            image = singleslicePtychography?.probeAmplitude()
            (kind, name, units) = ("ptychography_probe_amplitude", "Ptychography probe amplitude", "dimensionless")
        }
        guard let image else { return }
        parallaxResultProduct = product
        resultGamma = 1
        displayRangeLo = 0
        displayRangeHi = 1
        publishProduct(kind: kind, displayName: name, valueUnits: units, payload: .scalar(image))
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
            presentComputeFailure(SimpleError("Fit parallax aberrations before phase correction."))
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
            showParallaxProduct(.correctedPhase)   // v2.5 step 3e: one publish site
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
            presentComputeFailure(error)
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
            else { presentComputeFailure(error) }
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

        let fitFn = calibrationSession.originFitFunction
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

            calibrationSession.calibration.probeRadius = result.probeRadius
            calibrationSession.provenance.probe = .measuredInApp
            refreshDiskDefaultsForMeasuredProbe()
            calibrationSession.calibration.origin = result.origin
            clearSupersededFittedOrigin()
            parallaxPreprocess = nil
            parallaxAlignment = nil
            meanPattern = DiffractionPattern(qy: d.qy, qx: d.qx, pixels: result.meanDP)
            maxPattern = DiffractionPattern(qy: d.qy, qx: d.qx, pixels: result.maxDP)
            patternVersion &+= 1

            // Recenter the aperture on the measured beam.
            if let origin = calibrationSession.calibration.meanOrigin {
                aperture.centerX = origin.x
                aperture.centerY = origin.y
                calibrationSession.calibration.originProvenance = .fitted
            }
            let rms = result.origin.rmsResidual ?? 0
            statusText = String(format: "Origin ✓  r ≈ %.1f px, fit RMS %.3f px (%@)",
                                result.probeRadius, rms, fitFn.rawValue)

            await runCurrentAnalysis()
        } catch {
            if cancellation.isCancelled { statusText = "Origin calibration cancelled" }
            else { presentComputeFailure(error) }
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
        if navigation.analysisMode == .disks, let vectors = braggVectors {
            // The displayed Bragg map is log-scaled for display and already
            // carries any active ellipse correction. The intensity-weighted
            // fit needs the measured evidence instead: raw peak intensities,
            // collapsed onto the mean origin, with no ellipse applied —
            // fitting an already-corrected map would converge toward no
            // distortion and overwrite a valid calibration.
            var uncorrected = calibrationSession.calibration
            uncorrected.ellipseA = nil
            uncorrected.ellipseB = nil
            uncorrected.ellipseTheta = nil
            let origin = calibrationSession.calibration.meanOrigin
                ?? (x: Float(descriptor.qx) / 2, y: Float(descriptor.qy) / 2)
            let bvm = vectors.calibrated(
                with: uncorrected, referenceOrigin: origin
            ).map(qy: descriptor.qy, qx: descriptor.qx)
            detectorPattern = DiffractionPattern(
                qy: descriptor.qy, qx: descriptor.qx, pixels: bvm.pixels
            )
            sourceName = "Bragg-vector map"
        } else {
            if meanPattern == nil { await computeDPStatistics() }
            guard let meanPattern else {
                presentComputeFailure(SimpleError("Compute a mean diffraction pattern before fitting ellipse distortion."))
                return
            }
            detectorPattern = meanPattern
            sourceName = "mean diffraction pattern"
        }
        guard calibrationSession.ellipseFitInnerRadius >= 0,
              calibrationSession.ellipseFitOuterRadius > calibrationSession.ellipseFitInnerRadius else {
            presentComputeFailure(SimpleError("Ellipse fit outer radius must be larger than its inner radius."))
            return
        }

        let centerQX = Double(aperture.centerY)
        let centerQY = Double(aperture.centerX)
        let inner = calibrationSession.ellipseFitInnerRadius
        let outer = calibrationSession.ellipseFitOuterRadius
        let epoch = datasetEpoch
        let cancellation = beginCancellableOperation(
            "Ellipse calibration", status: "Fitting detector ellipse…", totalUnits: 1
        )
        defer { finishCancellableOperation(cancellation) }
        do {
            let fit = try await Task.detached(priority: .userInitiated) {
                try EllipseCalibration.fitBestAvailable(
                    pattern: detectorPattern,
                    centerQX: centerQX, centerQY: centerQY,
                    innerRadius: inner, outerRadius: outer
                )
            }.value
            guard epoch == datasetEpoch, !cancellation.isCancelled else {
                statusText = "Ellipse calibration cancelled"
                return
            }
            calibrationSession.calibration.ellipseA = fit.a
            calibrationSession.calibration.ellipseB = fit.b
            calibrationSession.calibration.ellipseTheta = fit.theta
            calibrationSession.provenance.ellipse = .measuredInApp
            calibrationSession.lastEllipseFit = fit
            progress = 1

            // A displayed Bragg map can be reprojected immediately because
            // raw peak storage remains unchanged. Strain/ACOM are deliberately
            // not relabeled; users rerun those quantitative analyses.
            if navigation.analysisMode == .disks, let vectors = braggVectors {
                showBraggMap(vectors, descriptor: descriptor)
            }
            statusText = String(
                format: "Ellipse ✓  %@ · a %.2f · b %.2f · θ %.1f° · residual %.3f (%@)",
                fit.model.rawValue,
                fit.a, fit.b, fit.theta * 180 / .pi,
                fit.normalizedResidual, sourceName
            )
        } catch {
            if cancellation.isCancelled { statusText = "Ellipse calibration cancelled" }
            else { presentComputeFailure(error) }
        }
    }

    /// R–Q rotation calibration: find the rotation (and detector transpose)
    /// that makes the CoM field curl-free. Runs origin calibration first if
    /// needed — the solver wants the descan-corrected field.
    func calibrateRotation(maximizeDivergence: Bool = false) async {
        guard let descriptor else { return }

        if !calibrationSession.calibration.hasFittedOrigin {
            await calibrateOrigin()
            guard calibrationSession.calibration.hasFittedOrigin else { return }
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
                presentComputeFailure(SimpleError("Scan is too small for rotation calibration (need at least 3 × 3 positions)."))
                return
            }
            calibrationSession.calibration.rotationRad = result.rotationRad
            calibrationSession.calibration.transposeQR = result.transpose
            calibrationSession.provenance.rotation = .measuredInApp
            parallaxPreprocess = nil
            parallaxAlignment = nil
            lastRotationResult = result
            // A cached CoM field must not show a stale rotation — and if the
            // re-derivation itself refuses (iDPC), its message must not be
            // overwritten by the ✓ line (Gate B, 2026-08-25). The rotation
            // DID calibrate either way; only the status line changes.
            // A displayed strain map is derived from the same rotation and
            // re-derives on the same rule. // v2 S8
            applyStrainDisplay()
            if applyDPCDisplay() == nil {
                statusText = String(format: "Rotation ✓  θ = %.1f°%@",
                                    result.rotationRad * 180 / .pi,
                                    result.transpose ? ", detector transposed" : "")
            }
        } catch {
            if cancellation.isCancelled { statusText = "R–Q rotation cancelled" }
            else { presentComputeFailure(error) }
        }
    }

    /// Measure the CoM shift field on the GPU, against calibrated origins when
    /// available. Shared by rotation calibration and (later) DPC.
    private func computeCoMField(
        cancellation: AnalysisCancellationToken? = nil
    ) async throws -> [Float]? {
        guard cancellation?.isCancelled != true else { return nil }
        guard let fourD, let descriptor else { return nil }
        let origins = calibrationSession.calibration.origin?.interleavedFitted
        let center = calibrationSession.calibration.referenceOrigin(  // v2 S13: one derivation
            detectorQX: descriptor.qx, detectorQY: descriptor.qy,
            apertureCentre: (x: aperture.centerX, y: aperture.centerY)
        ).point
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
    /// Returns the typed run verdict — see `runVirtualDetector`'s note. // v2 S6
    @discardableResult
    func runDPC(replaying: Bool = false) async -> AnalysisRunOutcome {
        guard let descriptor else { return .failed("No dataset is loaded") }
        let cancellation = beginCancellableOperation(
            "DPC", status: "Computing DPC (center of mass)…",
            totalUnits: descriptor.rx * descriptor.ry
        )
        defer { finishCancellableOperation(cancellation) }

        do {
            let epoch = datasetEpoch
            let field = try await computeCoMField(cancellation: cancellation)
            guard epoch == datasetEpoch else { return .failed("The dataset changed during the run") }
            if cancellation.isCancelled {
                statusText = "DPC cancelled"
                return .cancelled
            }
            // A nil field here is not a publish: `computeCoMField` bails to
            // nil when the cube is gone. The first version ran the success
            // block anyway — "DPC ✓" over nothing, and a phantom recipe step
            // (Gate A finding A6, 2026-08-25).
            guard let field else {
                statusText = "DPC could not run — no data is loaded"
                return .failed("DPC could not run — no data is loaded")
            }
            comField = field
            // A failed display derivation (an iDPC integration refusal) must
            // not be papered over with "DPC ✓", must not become a recipe
            // step, and must not report `.published` over a blank pane —
            // Gate B refuted the first version on all three (2026-08-25).
            // `presentComputeFailure` inside the derivation already put the
            // reason in the durable log; withholding the ✓ line keeps it on
            // the status bar too.
            if let displayFailure = applyDPCDisplay() {
                return .failed(displayFailure)
            }
            let ref = calibrationSession.calibration.hasFittedOrigin ? "calibrated origins" : "global center"
            statusText = "DPC ✓  (\(dpcDisplay.rawValue) vs \(ref))"
            // Recipe step (v2 S5). ONLY the origin source: `computeCoMField`
            // takes no aperture at all — its parameterization is which origin
            // it subtracts (fitted per-position maps / mean origin, or the
            // geometric fallback), and those come from `calibration` at run
            // time exactly as they will at replay time. The first version
            // recorded the aperture here; refuted by the function 45 lines up
            // (Gate B-lite F2) — recording values the computation never used
            // is false precision a replay would faithfully reproduce wrongly.
            recordReplayStep(kind: "dpc", parameters: [
                "origin_reference": ref,
            ], replaying: replaying)
            return .published
        } catch {
            if cancellation.isCancelled {
                statusText = "DPC cancelled"
                return .cancelled
            }
            presentComputeFailure(error)
            return .failed(error.localizedDescription)
        }
    }

    /// Flip the calibrated R–Q rotation by 180° — the curl/divergence solver
    /// is blind to this (flipping both CoM components leaves both invariant),
    /// so inverted iDPC contrast is fixed here, by hand.
    func flipRotation180() {
        guard var rotation = calibrationSession.calibration.rotationRad else { return }
        rotation += .pi
        if rotation > .pi { rotation -= 2 * .pi }
        calibrationSession.calibration.rotationRad = rotation
        calibrationSession.provenance.rotation = .manual
        parallaxPreprocess = nil
        parallaxAlignment = nil
        // Same rule as `calibrateRotation`: the flip stands either way, but a
        // refused re-derivation keeps its own message on the status bar.
        // The strain tensor is mathematically invariant under a 180° flip
        // (ε' = (−I)·ε·(−I)ᵀ = ε), but the displayed frame label shows the
        // angle, so the display re-derives on the same one rule. // v2 S8
        applyStrainDisplay()
        if applyDPCDisplay() == nil {
            statusText = String(format: "Rotation flipped → θ = %.1f°", rotation * 180 / .pi)
        }
    }

    /// Derive the displayed image from the cached CoM field per `dpcDisplay`.
    /// The calibrated R–Q rotation/transpose is applied first so the field is
    /// in the scan frame. Cheap enough (scan-sized) to run on the main actor.
    ///
    /// Returns the failure reason when the derivation could not produce an
    /// image (today: an iDPC integration refusal), nil on success — so a
    /// caller that writes its own "✓" status line can withhold it. The first
    /// S7 version reported the failure only through `presentComputeFailure`
    /// and `runDPC` then overwrote it with "DPC ✓", recorded a recipe step
    /// and returned `.published` over a blank pane — the S1 channel defect
    /// plus the A6 phantom-step defect, both found by Gate B (2026-08-25).
    @discardableResult
    /// The one publish site for every DPC display mode: pixels and label
    /// chosen together (v2.5 step 3e, condition 2).
    private func applyDPCDisplay() -> String? {
        guard var com = comField, let d = descriptor, navigation.analysisMode == .dpc else { return nil }
        if let rotation = calibrationSession.calibration.rotationRad {
            com = DPC.applyRotation(com: com, rotationRad: rotation,
                                    transpose: calibrationSession.calibration.transposeQR ?? false)
        }
        let payload: ProductPayload
        let kind: String, name: String, units: String
        switch dpcDisplay {
        case .magnitude:
            resultColormap = .viridis
            payload = .scalar(DPC.magnitudeImage(com: com, width: d.rx, height: d.ry))
            (kind, name, units) = ("dpc_magnitude", "DPC magnitude", "detector_px")
        case .magnitudeMrad:
            resultColormap = .viridis
            if let scale = dpcMilliradiansPerDetectorPixel {
                payload = .scalar(DPC.physicalMagnitudeImage(
                    com: com, width: d.rx, height: d.ry, milliradiansPerPixel: scale))
                (kind, name, units) = ("dpc_magnitude_mrad", "DPC magnitude (mrad)", "mrad")
            } else {
                payload = .scalar(DPC.magnitudeImage(com: com, width: d.rx, height: d.ry))
                (kind, name, units) = ("dpc_magnitude", "DPC magnitude", "detector_px")
            }
        case .angle:
            resultColormap = .viridis
            payload = .scalar(DPC.angleImage(com: com, width: d.rx, height: d.ry))
            (kind, name, units) = ("dpc_angle", "DPC angle", "rad")
        case .colorWheel:
            resultColormap = .viridis
            payload = .rgba(DPC.colorWheelRGBA(com: com, width: d.rx, height: d.ry))
            (kind, name, units) = ("dpc_color", "DPC color wheel", "rgba")
        case .idpc:
            resultColormap = .rdbu
            // `integrateIDPC` now throws instead of returning a zero image
            // (v2 S7): a failed integration must leave NO image on screen —
            // neither a fabricated flat map nor the previous display's
            // pixels under an iDPC label — and must say why.
            do {
                if let physical = idpcPhysicalCalibration {
                    payload = .scalar(try DPC.integratePhysicalIDPC(
                        com: com, width: d.rx, height: d.ry,
                        calibration: physical, boundary: .zeroPadded, paddingFactor: 2))
                    (kind, name, units) = ("idpc_phase", "iDPC projected phase", "rad")
                } else {
                    payload = .scalar(try DPC.integrateIDPC(
                        com: com, width: d.rx, height: d.ry,
                        boundary: .zeroPadded, paddingFactor: 2))
                    (kind, name, units) = ("idpc_qualitative", "iDPC (qualitative)", "detector_px_scan_px")
                }
            } catch {
                publishedProduct = nil
                resultVersion &+= 1
                presentComputeFailure(error)
                return error.localizedDescription
            }
        }
        publishProduct(kind: kind, displayName: name, valueUnits: units, payload: payload)
        return nil
    }

    var dpcMilliradiansPerDetectorPixel: Float? {
        guard let qSize = calibrationSession.calibration.qPixelSize,
              qSize.isFinite, qSize > 0 else { return nil }
        if CalibrationUnitConversion.normalized(calibrationSession.calibration.qPixelUnits) == "mrad" {
            return Float(qSize)
        }
        guard let invAngstrom =
                CalibrationUnitConversion.reciprocalInvAngstromPerPixel(
                    value: qSize, units: calibrationSession.calibration.qPixelUnits
                ) else { return nil }
        guard let voltageKV = calibrationSession.acceleratingVoltage else { return nil }
        return DPC.milliradiansPerDetectorPixel(
            voltageKV: voltageKV, invAngstromPerPixel: invAngstrom
        )
    }

    /// Why physical iDPC specifically REFUSES the fitted origin, or nil.
    ///
    /// Distinct from "not yet calibrated" (missing origin, rotation or pixel
    /// sizes — the generic requirements note in the DPC controls): this is
    /// non-nil only when an origin fit EXISTS and the gate judges it
    /// non-quantitative, so the controls can say the true reason instead of
    /// listing requirements that are all met. // v2 S7
    ///
    /// Same JUDGEMENT as the gate (non-nil exactly when
    /// `gates.originQuantitativeRefusal` is), but with iDPC's own remedy:
    /// the Q-surface's "or enter the scale manually" cannot move this
    /// residual and so cannot bring physical iDPC back — a remedy that does
    /// nothing where it is printed (Gate B, 2026-08-25).
    var idpcOriginFitRefusal: String? {
        calibrationSession.calibration.originFitJudgement.map {
            $0 + " Try another Origin fit (Constant / Plane / Parabola) and "
                + "re-run Calibrate Origin."
        }
    }

    var idpcPhysicalCalibration: IDPCPhysicalCalibration? {
        // A scale alone is insufficient: quantitative integration also needs
        // per-position descan correction and a detector field rotated into the
        // scan frame.
        guard calibrationSession.calibration.hasFittedOrigin, calibrationSession.calibration.hasRotation else { return nil }
        // The SAME gate Q calibration takes, asked through the same owner
        // (`SessionGates`, S7's seam). This call site used to derive the
        // policy from `hasFittedOrigin` alone, so an origin fit whose RMS
        // residual exceeded the probe radius — refused for a Q measurement —
        // was still admitted into "iDPC projected phase (rad)". A fit the
        // gate refuses renders qualitative iDPC instead, with the refusal
        // shown by the DPC controls (`idpcOriginFitRefusal`). // v2 S7
        guard gates.originQuantitativeRefusal(for: calibrationSession.calibration) == nil else {
            return nil
        }
        return DPC.physicalIDPCCalibration(
            realPixelSize: calibrationSession.calibration.rPixelSize,
            realPixelUnits: calibrationSession.calibration.rPixelUnits,
            reciprocalPixelSize: calibrationSession.calibration.qPixelSize,
            reciprocalPixelUnits: calibrationSession.calibration.qPixelUnits,
            voltageKV: calibrationSession.acceleratingVoltage
        )
    }

    // MARK: - Disk detection

    /// Build the synthetic probe kernel from the calibrated probe radius,
    /// running origin calibration first if needed.
    func generateProbeKernel() async {
        guard let descriptor else { return }
        if calibrationSession.calibration.probeRadius == nil {
            await calibrateOrigin()
            guard calibrationSession.calibration.probeRadius != nil else { return }
        }
        guard let radius = calibrationSession.calibration.probeRadius else { return }

        guard let kernel = ProbeKernel.synthetic(radius: radius, qy: descriptor.qy, qx: descriptor.qx) else {
            presentComputeFailure(SimpleError("Could not build a probe kernel (radius \(radius) px)."))
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
        if calibrationSession.calibration.probeRadius == nil {
            await calibrateOrigin()
            guard calibrationSession.calibration.probeRadius != nil else { return }
        }
        guard let radius = calibrationSession.calibration.probeRadius, let d = descriptor else { return }
        let origin = calibrationSession.calibration.referenceOrigin(  // v2 S13: one derivation
            detectorQX: d.qx, detectorQY: d.qy,
            apertureCentre: (x: aperture.centerX, y: aperture.centerY)
        ).point
        guard let kernel = ProbeKernel.measured(
            pattern: pattern, originX: origin.x, originY: origin.y, radius: radius
        ) else {
            presentComputeFailure(SimpleError("The current CBED/ROI did not contain a usable measured probe."))
            return
        }
        probeKernel = kernel
        statusText = String(
            format: "Measured probe kernel ✓  r = %.1f px from current CBED/ROI", radius
        )
        await detectCurrentPattern()
    }

    // Same coalescing contract as the live virtual-detector drag: at most one
    // detection in flight; parameter changes during a slider drag mark work
    // pending instead of piling up detached detections that only get
    // discarded by the request counter after running to completion.
    @ObservationIgnored private var liveDetectionInFlight = false
    @ObservationIgnored private var liveDetectionPending = false

    /// Live overlay: detect disks in the currently displayed pattern only.
    func detectCurrentPattern() async {
        if liveDetectionInFlight {
            liveDetectionPending = true
            return
        }
        liveDetectionInFlight = true
        await performLiveDetection()
        liveDetectionInFlight = false
        if liveDetectionPending {
            liveDetectionPending = false
            Task { await detectCurrentPattern() }
        }
    }

    /// One live-detection pass over the latest displayed pattern/parameters.
    private func performLiveDetection() async {
        liveDetectionRequest &+= 1
        let request = liveDetectionRequest
        guard navigation.analysisMode == .disks, let kernel = probeKernel,
              let pattern = displayedPattern else {
            if !currentPeaks.isEmpty { currentPeaks = [] }
            currentDiskDiagnostics = nil
            return
        }
        let params = diskParams
        let context = DiskDetectionContext(
            qy: pattern.qy, qx: pattern.qx, probeRadius: kernel.probeRadius
        )
        guard !params.validationIssues(in: context).contains(where: {
            $0.severity == .error
        }) else {
            currentPeaks = []
            currentDiskDiagnostics = nil
            return
        }
        let epoch = datasetEpoch
        let result = await Task.detached(priority: .userInitiated) {
            () -> DiskDetectionPatternResult? in
            guard let detector = DiskDetector(kernel: kernel) else { return nil }
            return detector.detectWithDiagnostics(
                pattern: pattern.pixels, params: params
            )
        }.value
        guard epoch == datasetEpoch,
              request == liveDetectionRequest,
              navigation.analysisMode == .disks else { return }
        currentPeaks = result?.peaks ?? []
        currentDiskDiagnostics = result?.diagnostics
    }

    /// Full-scan detection → BraggVectors + Bragg vector map.
    /// Returns the typed run verdict — see `runVirtualDetector`'s note. // v2 S6
    @discardableResult
    func runDiskDetection(replaying: Bool = false) async -> AnalysisRunOutcome {
        guard let fourD, let descriptor else { return .failed("No dataset is loaded") }
        if probeKernel == nil { await generateProbeKernel() }
        guard let kernel = probeKernel else {
            return .failed("No probe kernel could be generated")
        }

        let params = diskParams
        let context = DiskDetectionContext(
            qy: descriptor.qy, qx: descriptor.qx, probeRadius: kernel.probeRadius
        )
        let errors = params.validationIssues(in: context).filter {
            $0.severity == .error
        }
        guard errors.isEmpty else {
            let reason = "Disk-detection settings are invalid: "
                + errors.map(\.message).joined(separator: " ")
            presentComputeFailure(SimpleError(reason))
            return .failed(reason)
        }

        let cancellation = beginCancellableOperation(
            "Disk detection", status: "Detecting Bragg disks…",
            totalUnits: descriptor.rx * descriptor.ry
        )
        defer { finishCancellableOperation(cancellation) }

        let d = descriptor
        // `detectAll` now throws a `FullScanError` naming what failed and
        // where; nil means cancelled and nothing else. The previous contract
        // returned nil for everything, and the guard below then attributed a
        // NAS tile-read failure to "its FFT plan" — the error-attribution
        // defect this session exists to fix. // v2 S7
        let epoch = datasetEpoch
        let vectors: BraggVectors?
        do {
            // P1 (Gate D, 2026-09-01): run the full-scan detection OFF the
            // main actor. `detectAll` is nonisolated async and ran on the
            // caller's executor here, and its `concurrentPerform` then
            // conscripted the MAIN thread as a dispatch_apply worker for each
            // tile's entire CPU-FFT workload — sampled live during the
            // owner's frozen run: 2518/2519 main-thread samples inside
            // FFT2D.transform, AX ping 7 s, progress unpaintable, Cancel
            // dead. The detached task keeps the worker pool saturated while
            // the runloop stays free. The progress closure already hopped to
            // the main actor explicitly, so it is unchanged.
            let data = fourD
            let progress: @Sendable (Double) -> Void = { [weak self] fraction in
                Task { @MainActor [weak self] in
                    guard let self,
                          self.isCurrentOperation(cancellation),
                          !cancellation.isCancelled else { return }
                    self.progress = fraction
                    self.statusText = "Detecting Bragg disks… \(Int(fraction * 100)) %"
                }
            }
            vectors = try await Task.detached(priority: .userInitiated) {
                try await DiskDetection.detectAll(
                    data: data, descriptor: d, kernel: kernel,
                    params: params, cancellation: cancellation,
                    progress: progress
                )
            }.value
        } catch {
            guard datasetEpoch == epoch else { return .failed("The dataset changed during the run") }
            if cancellation.isCancelled {
                statusText = braggVectors == nil
                    ? "Disk detection cancelled — no peaks were published"
                    : "Disk detection cancelled; the previous full-scan peaks are still shown"
                return .cancelled
            }
            presentComputeFailure(error)
            return .failed(error.localizedDescription)
        }
        guard epoch == datasetEpoch else { return .failed("The dataset changed during the run") }
        if cancellation.isCancelled {
                // `DiskDetection.detectAll` returns nil on cancellation — never
                // a partial `BraggVectors` — so nothing here is a half-finished
                // result. What stays on screen is the PREVIOUS completed run,
                // and saying so is the difference between this and the silent
                // "it showed a Bragg vector map regardless" the release owner
            // reported (backlog #34). Every other cancellable step in this
            // file already names what it retained; this one did not.
            statusText = braggVectors == nil
                ? "Disk detection cancelled — no peaks were published"
                : "Disk detection cancelled; the previous full-scan peaks are still shown"
            return .cancelled
        }
        guard let vectors else {
            // With the throwing contract, nil-and-not-cancelled cannot
            // happen; if it ever does, say that rather than invent a cause.
            let reason = "Disk detection returned no result and no reason — this is a defect; please report it."
            presentComputeFailure(SimpleError(reason))
            return .failed(reason)
        }
        braggVectors = vectors
        completedDiskParams = params
        // Recipe step (v2 S5): the canonical example of why the record exists
        // separately from per-result controls — detection's own product
        // (BraggVectors) is often never saved as a result, but strain's is,
        // and replaying strain without these parameters is impossible.
        // Re-detection INVALIDATES downstream steps: a strain or ACOM step
        // recorded against the old peaks would otherwise survive next to the
        // new detection — a recipe that replays neither the saved maps nor a
        // coherent pipeline (Gate B-lite F4). Re-running them re-records them.
        recordReplayStep(kind: "disk_detection", parameters: [
            "corr_power": String(params.corrPower),
            "sigma_dp": String(params.sigmaDP),
            "sigma_cc": String(params.sigmaCC),
            "subpixel": params.subpixel.provenanceID,
            "upsample_factor": String(params.upsampleFactor),
            "min_absolute_intensity": String(params.minAbsoluteIntensity),
            "min_relative_intensity": String(params.minRelativeIntensity),
            "relative_to_peak": String(params.relativeToPeak),
            "min_peak_spacing": String(params.minPeakSpacing),
            "edge_boundary": String(params.edgeBoundary),
            "max_peaks": String(params.maxNumPeaks),
            // The kernel class is a detection parameter even though
            // `DiskDetectionParams` does not carry it: the thresholds above
            // were tuned against ITS correlation response, and a replay that
            // regenerated a different class of kernel would silently move
            // every peak (Gate A finding C3, 2026-08-25). Vocabulary shared
            // with result provenance ("synthetic" / "measured_roi").
            "kernel_source": kernel.source.provenanceID,
        ], invalidating: ["strain", "acom"], replaying: replaying)
        completedDiskSummary = DiskDetectionScanSummary(
            vectors: vectors, maximumPeaks: params.maxNumPeaks
        )
        braggPeakCount = vectors.totalPeakCount
        showBraggMap(vectors, descriptor: d)
        if vectors.totalPeakCount == 0 {
            // An empty result is a dead end unless it points at the
            // evidence: the live acceptance funnel and scan summary in
            // the Bragg panel show which filter removed everything.
            statusText = "Disk detection accepted no peaks — check the acceptance funnel and warnings in the Bragg panel, then relax the intensity or spacing thresholds"
        } else {
            statusText = "Disks ✓  \(vectors.totalPeakCount) peaks (\(params.subpixel.rawValue) subpixel)"
        }
        return .published
    }

    /// Show the Bragg vector map (log-scaled — the central beam dominates the
    /// raw histogram) in the result pane.
    private func showBraggMap(_ vectors: BraggVectors, descriptor d: DatasetDescriptor) {
        let calibrated = calibratedBraggVectors(vectors, descriptor: d).vectors
        let bvm = calibrated.map(qy: d.qy, qx: d.qx)
        resultColormap = .viridis
        publishProduct(   // v2.5 step 3e: its own label
            kind: "bragg_vector_map", displayName: "Bragg vector map", valueUnits: "log_intensity",
            payload: .scalar(FloatImage(width: bvm.width, height: bvm.height,
                                        pixels: bvm.pixels.map { log10(1 + max($0, 0)) })))
        Task { await ensureScanNavigator() }
    }

    /// Raw peaks remain the source of truth; analysis calibration is derived
    /// on demand so imported or newly fitted origin/ellipse values immediately
    /// affect Bragg maps, strain, and ACOM without re-running detection.
    private func calibratedBraggVectors(
        _ vectors: BraggVectors,
        descriptor d: DatasetDescriptor,
        positions: [Int]? = nil
    ) -> (vectors: BraggVectors, origin: Calibration.ReferenceOrigin) {
        // v2 S13: ONE derivation, `Calibration.referenceOrigin`. This line used
        // to read `calibration.meanOrigin ?? (qx/2, qy/2)`, and `meanOrigin` is
        // nil in exactly the `.fileMean`/`.sessionMean` states — so the file's
        // recorded beam centre was replaced by the detector's geometric middle
        // in Q calibration, strain, ACOM and the Bragg map at once, while the
        // inspector went on displaying the file's origin (S11, 2026-08-28).
        // Three sibling call sites fell back to the aperture instead; they now
        // ask the same function, and the KIND travels with the value so a
        // caller that must not accept a stand-in can refuse on it.
        let origin = calibrationSession.calibration.referenceOrigin(
            detectorQX: d.qx, detectorQY: d.qy,
            apertureCentre: (x: aperture.centerX, y: aperture.centerY)
        )
        return (
            vectors.calibrated(
                with: calibrationSession.calibration, referenceOrigin: origin.point, positions: positions
            ),
            origin
        )
    }

    // MARK: - Strain mapping

    /// Compute a strain map from the detected Bragg vectors (needs a prior
    /// disk-detection pass). Automatic mode uses repeated-vector consensus;
    /// local fits and the reference population reject outliers independently.
    /// Returns the typed run verdict — see `runVirtualDetector`'s note. // v2 S6
    @discardableResult
    func runStrainMapping(replaying: Bool = false) async -> AnalysisRunOutcome {
        guard let descriptor else { return .failed("No dataset is loaded") }
        guard !diskDetectionSettingsAreStale else {
            let reason = "Detection settings changed — run Detect All Disks again before computing strain."
            presentComputeFailure(SimpleError(reason))
            return .failed(reason)
        }
        guard let bragg = braggVectors else {
            let reason = "Run disk detection first — strain mapping needs detected Bragg peaks."
            presentComputeFailure(SimpleError(reason))
            return .failed(reason)
        }
        let cancellation = beginCancellableOperation(
            "Strain mapping", status: "Computing strain map…",
            totalUnits: descriptor.rx * descriptor.ry
        )
        defer { finishCancellableOperation(cancellation) }

        let calibrated = calibratedBraggVectors(bragg, descriptor: descriptor)
        let origin = calibrated.origin.point
        let referenceMask = strain.referenceMode == .selectedRegion
            ? realSpaceRegionMask(descriptor) : nil
        let initialBasis = strain.manualInitialBasis
        let epoch = datasetEpoch
        let map = await Task.detached(priority: .userInitiated) {
            StrainMapping.compute(bragg: calibrated.vectors,
                                  originX: origin.x, originY: origin.y,
                                  referenceMask: referenceMask,
                                  initialBasis: initialBasis,
                                  cancellation: cancellation)
        }.value
        guard epoch == datasetEpoch else { return .failed("The dataset changed during the run") }
        if cancellation.isCancelled {
            statusText = "Strain mapping cancelled"
            return .cancelled
        }
        guard let map else {
            // Classify before wording: a starved peak population and an
            // ill-conditioned lattice are different failures with different
            // fixes, and naming both remedies every time (backlog #8) told the
            // user to go and change settings in a task that was not at fault.
            let cause: StrainFailureCause
            if let summary = completedDiskSummary, summary.positionCount > 0 {
                cause = .classify(
                    medianPeaks: summary.medianPeakCount,
                    emptyPercent: summary.zeroPeakPositionCount * 100 / summary.positionCount
                )
            } else {
                cause = .illConditionedBasis
            }
            strain.recordFailure(cause)

            var detail: String
            switch cause {
            case .starvedInput(let medianPeaks, let emptyPercent):
                detail = String(
                    format: "Only %.1f peaks per pattern were detected (%d%% of positions "
                        + "had none). Indexing a lattice needs the direct beam plus two "
                        + "more reflections, so lower the detection thresholds in Bragg "
                        + "disks and detect again.",
                    medianPeaks, emptyPercent
                )
            case .illConditionedBasis:
                detail = strain.basisMode == .manual
                    ? "The manual basis is ill-conditioned, or too few peaks index to it. "
                        + "Check g₁ and g₂, or switch the basis back to Automatic."
                    : "The peak population is healthy, but no single lattice explains "
                        + "enough of it — which is what happens when the reference "
                        + "averages over regions with different lattices. "
                        + (strain.referenceMode == .wholeScan
                           ? "Pick an unstrained region as the reference instead."
                           : "Try a different reference region, or set g₁ and g₂ manually.")
                if let summary = completedDiskSummary, summary.positionCount > 0 {
                    detail += String(
                        format: " (Detected input: median %.1f peaks per pattern, "
                            + "%d%% of positions empty.)",
                        summary.medianPeakCount,
                        summary.zeroPeakPositionCount * 100 / summary.positionCount
                    )
                }
            }
            if let warning = completedDiskSummary?.warnings.first {
                detail += " " + warning
            }
            presentComputeFailure(SimpleError("Could not publish strain. \(detail)"))
            return .failed("Could not publish strain. \(detail)")
        }
        // Snapshot the origin provenance WITH the map (Gate B, 2026-08-28):
        // these keys describe the fit this map was computed against, and
        // reading them at export time let them describe a different one.
        strain.publish(map, originProvenance: originFitProvenance)
        // Recipe step (v2 S5): the run's modes plus the RESOLVED basis — an
        // automatic basis re-derived on a different view can legitimately
        // differ, so the recipe records both; S6 decides which fidelity a
        // replay wants. Tokens are the RESULT-PROVENANCE vocabulary
        // ("consensus"/"manual", "selected-region"/"whole-scan"), not Swift
        // case names — the two carriers share keys and must share values
        // (Gate B-lite F10).
        recordReplayStep(kind: "strain", parameters: [
            "reference_mode": map.diagnostics.referenceMaskApplied
                ? "selected-region" : "whole-scan",
            "basis_mode": map.diagnostics.automaticBasis ? "consensus" : "manual",
            "resolved_g1_x": String(map.refG1.x), "resolved_g1_y": String(map.refG1.y),
            "resolved_g2_x": String(map.refG2.x), "resolved_g2_y": String(map.refG2.y),
        ], replaying: replaying)
        resultColormap = .rdbu   // diverging map without recoloring the CBED pane
        applyStrainDisplay()
        statusText = String(format: "Strain ✓  %.0f%% indexed · %.0f%% basis support · RMS %.3g px · κ %.2f · %d/%d ref",
                            map.indexedFraction * 100,
                            map.diagnostics.basisSupportFraction * 100,
                            map.diagnostics.basisResidualPixels,
                            map.diagnostics.basisConditionNumber,
                            map.referencePositionCount,
                            map.diagnostics.referenceCandidateCount)
        return .published
    }

    /// A whole-scan product computed earlier this session and still retained,
    /// so it can be brought back to the viewer without recomputing it.
    enum ComputedProduct: String, CaseIterable, Identifiable, Sendable {
        case strain, orientation
        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .strain: "Strain map"
            case .orientation: "Orientation map"
            }
        }
    }

    /// Products held in memory right now. `strain.map` and `orientationMap` are
    /// retained simultaneously — only the *displayed* one was ever
    /// single-valued, which is why running ACOM and then Strain looked like it
    /// had lost the first result (backlog #28).
    var availableComputedProducts: [ComputedProduct] {
        var products: [ComputedProduct] = []
        if strain.map != nil { products.append(.strain) }
        if acomSession.hasOrientationMap { products.append(.orientation) }
        return products
    }

    /// Bring a retained product back to the viewer.
    ///
    /// Deliberately an **explicit action**, not a side effect of `changeMode`:
    /// navigating between tasks must never silently relabel the visible
    /// result, which `testNavigationDoesNotRelabelTheVisibleScientificResult`
    /// pins. The navigation/restored overrides are cleared first, because the
    /// user is now asking for a specific product rather than carrying the
    /// previous one along.
    func showComputedProduct(_ product: ComputedProduct) {
        inspectQualityField = false
        switch product {
        case .strain:
            guard strain.map != nil else { return }
            navigation.analysisMode = .strain
            navigation.workspaceArea = .map
            applyStrainDisplay()
        case .orientation:
            guard acomSession.hasOrientationMap else { return }
            navigation.analysisMode = .acom
            navigation.workspaceArea = .map
            applyACOMDisplay()
        }
    }

    /// The frame strain is presented in right now, derived from the CURRENT
    /// calibration on every read (the `applyDPCDisplay` pattern) — a later
    /// rotation calibration changes what is shown, never silently desyncs
    /// from it. // v2 S8
    var strainPresentationFrame: StrainPresentationFrame {
        .resolve(rotationRad: calibrationSession.calibration.rotationRad,
                 transposeQR: calibrationSession.calibration.transposeQR)
    }

    /// Show the selected strain component, expressed in the presentation
    /// frame; masked positions remain NaN and render with the explicit
    /// no-data color, never as neutral zero strain.
    /// The one publish site for the strain product (v2.5 step 3e, condition 2).
    private func applyStrainDisplay() {
        guard let map = strain.map, navigation.analysisMode == .strain else { return }
        resultColormap = (strain.component == .residual || strain.component == .indexed)
            ? .viridis : .rdbu
        let kind: String, units: String
        switch strain.component {
        case .exx:      (kind, units) = ("strain_exx", "strain")
        case .eyy:      (kind, units) = ("strain_eyy", "strain")
        case .exy:      (kind, units) = ("strain_exy", "strain")
        case .theta:    (kind, units) = ("strain_theta", "rad")
        case .residual: (kind, units) = ("strain_fit_residual", "detector_px")
        case .indexed:  (kind, units) = ("strain_indexed", "boolean")
        }
        publishProduct(
            kind: kind, displayName: "Strain · \(strain.component.rawValue)", valueUnits: units,
            payload: .scalar(map.presented(in: strainPresentationFrame).component(strain.component)),
            validityMask: map.mask,
            qualityFields: [
                ProductQualityField(
                    name: "fit residual", units: "detector_px",
                    image: FloatImage(width: map.width, height: map.height, pixels: map.localResidualPixels)),
                ProductQualityField(
                    name: "indexed", units: "boolean",
                    image: FloatImage(width: map.width, height: map.height, pixels: map.mask.map { $0 ? 1 : 0 })),
            ],
            overlays: [ProductOverlayDescriptor(
                kind: "local_lattice_fit", provenance: "retained Bragg-vector least-squares fit")])
    }

    // MARK: - ACOM (orientation mapping)

    /// Build the orientation-plan template library for the selected crystal.
    func calibrateQFromCrystal() async {
        guard !diskDetectionSettingsAreStale else {
            presentComputeFailure(SimpleError("Detection settings changed — run Detect All Disks again before calibrating reciprocal pixels."))
            return
        }
        // Backlog #46. `calibratedBraggVectors` below re-centres every pattern
        // on the fitted origin, so this estimate is only ever as good as that
        // fit. On `downsample_Si_SiGe_exp` the fit RMS is 11.66 px against a
        // 5.03 px probe radius and a 14.9 px lattice period, and the Q pixel
        // size came out 2.56× too large — labelled `.measuredInApp`, which is
        // the string that travels into export, reopen and the QC log while the
        // warning stayed behind in the Origin row.
        //
        // The gate is asked through `SessionGates` (S7's seam), which answers
        // it from `Calibration.originFitRefusal` — the same predicate the
        // readiness row renders, so there is one owner. It is
        // deliberately *only* the residual test and not the whole `originProbe`
        // row: an origin that was never fitted has no residual to judge and is
        // not a known-bad number, which is a different question (#29) and not
        // this defect. The manual Q field stays rendered either way, so
        // refusing here is never a dead end.
        //
        // It runs *before* the input guards on purpose: the verdict does not
        // depend on having Bragg vectors, and re-detecting disks against a bad
        // origin is wasted work, so naming the origin first is the more useful
        // order. No dataset loaded means an empty `Calibration`, which has no
        // residual to judge and falls through to the guards below.
        guard let descriptor, let rawBragg = braggVectors else {
            presentComputeFailure(SimpleError("Detect Bragg disks before calibrating reciprocal pixels."))
            return
        }
        // v2 S13: the STRICTER of the two predicates. It still runs before the
        // model guard for the reason the old comment gives — naming the origin
        // first is more useful than re-detecting disks against a bad one — but
        // it now needs the descriptor, so the dataset guard moved above it.
        // What it adds over `originQuantitativeRefusal` is the second
        // requirement from the design's §2: the origin must be a MEASURED beam
        // centre. That is S11's worst finding closed structurally.
        if let refusal = gates.reciprocalMetrologyRefusal(
            for: calibrationSession.calibration, descriptor: descriptor,
            apertureCentre: (x: aperture.centerX, y: aperture.centerY)
        ) {
            qCalibration.record(refusal: refusal)
            presentComputeFailure(SimpleError(refusal))
            return
        }
        guard let model = resolvedACOMModel else {
            presentComputeFailure(SimpleError(acomModelSelectionIssue
                ?? "Choose a valid phase model before calibrating reciprocal pixels."))
            return
        }
        let modelRevision = model.revisionID
        let calibrated = calibratedBraggVectors(rawBragg, descriptor: descriptor)
        let epoch = datasetEpoch
        let probeRadiusPixels = calibrationSession.calibration.probeRadius.map(Double.init)
        let estimate = await Task.detached(priority: .userInitiated) {
            // DISTINCT shell lengths. `Crystal.reflections` returns every
            // symmetry equivalent separately, all at the same |g|, so the
            // "second shell" is the first length that DIFFERS — not
            // `reflections[1]`, which is another equivalent of the first.
            // Measured consequence of getting this wrong (S13 E1): the
            // self-check reads 1.020 on healthy sim_Au against an expected
            // 1.155 and fires on good data.
            let lengths = model.crystal.reflections(kMax: 2.5).map(\.gLength)
            var shells: [Double] = []
            for length in lengths where shells.last.map({ length > $0 * (1 + 1e-6) }) ?? true {
                shells.append(length)
            }
            guard let firstShell = shells.first else { return nil as QCalibrationEstimate? }
            return KnownCrystalQCalibration.estimate(
                bragg: calibrated.vectors, origin: calibrated.origin.point,
                referenceRadiusInvAngstrom: firstShell,
                secondShellRadiusInvAngstrom: shells.count > 1 ? shells[1] : nil,
                probeRadiusPixels: probeRadiusPixels
            )
        }.value
        guard epoch == datasetEpoch,
              modelRevision == resolvedACOMModel?.revisionID else { return }
        guard let estimate else {
            let reason = "Could not identify a non-central first Bragg shell."
            qCalibration.record(refusal: reason)
            presentComputeFailure(SimpleError(reason))
            return
        }
        // The estimator MEASURES a shell ratio and refuses nothing. v2 S13
        // shipped three plausibility thresholds here and Gate B refuted the
        // derivation of all three the same day (see `KnownCrystalQCalibration`
        // for what went wrong and what a later session needs). What survived is
        // the measurement, which `qCalibration.selfCheckSummary` surfaces.
        qCalibration.record(estimate)
        calibrationSession.calibration.qPixelSize = estimate.invAngstromPerPixel
        calibrationSession.calibration.qPixelUnits = "Å⁻¹"
        calibrationSession.provenance.qScale = .measuredInApp
        acomSession.invalidateResult()
        parallaxPreprocess = nil
        parallaxAlignment = nil
        var status = String(
            format: "Q calibration ✓  %.6f Å⁻¹/px · first shell %.2f px · %d positions",
            estimate.invAngstromPerPixel, estimate.observedRadiusPixels,
            estimate.sampleCount
        )
        switch estimate.shellCheck {
        case .notSelfChecked:
            status += " · shell ratio NOT self-checked"
        case .measured(let observed, let expected, _):
            status += String(format: " · shell ratio %.3f vs %.3f predicted", observed, expected)
        }
        statusText = status
    }

    /// Build the orientation-plan template library for the selected crystal.
    func generateOrientationPlan() async {
        guard descriptor != nil else { return }
        let templateCount = acomSession.quality.templateCount
        let cancellation = beginCancellableOperation(
            "Orientation plan", status: "Generating orientation plan…",
            totalUnits: templateCount
        )
        defer { finishCancellableOperation(cancellation) }

        guard let model = resolvedACOMModel else {
            presentComputeFailure(SimpleError(acomModelSelectionIssue
                ?? "Choose a valid phase model before generating an orientation plan."))
            return
        }
        let modelRevision = model.revisionID
        let missing = model.crystal.unsupportedElements
        guard missing.isEmpty else {
            presentComputeFailure(SimpleError("No scattering factors for element(s) Z = "
                + missing.map(String.init).joined(separator: ", ")
                + " — structure factors would be wrong."))
            return
        }
        let epoch = datasetEpoch
        // Without the beam energy the plan falls back to a flat Ewald sphere,
        // which makes every template exactly π-periodic in azimuth and leaves
        // the in-plane angle determined only modulo 180°. Pass the wavelength
        // whenever the dataset carries a voltage.
        let planWavelength = calibrationSession.acceleratingVoltage.flatMap {
            DPC.electronWavelengthAngstrom(voltageKV: $0)
        }
        let plan = await Task.detached(priority: .userInitiated) {
            OrientationPlan.generate(crystal: model.crystal, kMax: 1.2,
                                     zoneAxisCount: templateCount,
                                     symmetry: model.symmetry,
                                     wavelengthAngstrom: planWavelength,
                                     cancellation: cancellation)
        }.value
        guard epoch == datasetEpoch,
              modelRevision == resolvedACOMModel?.revisionID else { return }
        if cancellation.isCancelled {
            statusText = "Orientation-plan generation cancelled"
            return
        }
        guard let plan else {
            presentComputeFailure(SimpleError("Could not generate an orientation plan."))
            return
        }
        acomSession.orientationPlan = plan
        acomSession.hasOrientationPlan = true
        statusText = "Orientation plan ✓  \(plan.count) templates (\(model.displayName))"
    }

    /// Match the chosen preview, selected region, or full scan against the
    /// plan (needs a prior disk-detection pass; builds the plan first if needed).
    /// Returns the typed run verdict — see `runVirtualDetector`'s note. // v2 S6
    @discardableResult
    func runACOM(replaying: Bool = false) async -> AnalysisRunOutcome {
        let actionStarted = Date()
        guard !diskDetectionSettingsAreStale else {
            let reason = "Detection settings changed — run Detect All Disks again before ACOM."
            presentComputeFailure(SimpleError(reason))
            return .failed(reason)
        }
        guard let descriptor, let bragg = braggVectors else {
            let reason = "Detect Bragg disks first (Disks mode), then run ACOM."
            presentComputeFailure(SimpleError(reason))
            return .failed(reason)
        }
        guard let model = resolvedACOMModel else {
            let reason = acomModelSelectionIssue
                ?? "Choose a valid phase model before running ACOM."
            presentComputeFailure(SimpleError(reason))
            return .failed(reason)
        }
        if acomSession.orientationPlan == nil { await generateOrientationPlan() }
        guard let plan = acomSession.orientationPlan else {
            return .failed("No orientation plan could be generated")
        }

        let selection = acomScanSelection
        let scope = acomSession.scope
        let quality = acomSession.quality
        let workCount = selection.positionCount(
            width: descriptor.rx, height: descriptor.ry
        )
        let operationName: String
        switch scope {
        case .preview: operationName = "ACOM preview"
        case .selectedRegion: operationName = "ACOM selected region"
        case .fullScan: operationName = "ACOM full scan"
        }

        let cancellation = beginCancellableOperation(
            operationName, status: "\(operationName)…",
            totalUnits: workCount
        )
        defer { finishCancellableOperation(cancellation) }

        let selectedPositions = selection.sourceIndices(
            width: descriptor.rx, height: descriptor.ry
        )
        let calibrated = calibratedBraggVectors(
            bragg, descriptor: descriptor, positions: selectedPositions
        )
        let origin = calibrated.origin
        let scaleSemantics = acomScaleSemantics
        let scale = scaleSemantics.invAngstromPerPixel
        let runSemantics = ACOMRunSemantics(
            materialModelID: model.id,
            materialDescription: model.displayName,
            scale: scaleSemantics,
            materialProvenance: model.provenance
        )
        let modelRevision = model.revisionID
        let backend = effectiveACOMBackend
        let epoch = datasetEpoch
        let map = await Task.detached(priority: .userInitiated) { [self] in
            OrientationMatching.matchAll(bragg: calibrated.vectors, plan: plan,
                                         originX: origin.x, originY: origin.y,
                                         invAngstromPerPixel: scale,
                                         backend: backend,
                                         selection: selection,
                                         cancellation: cancellation) { fraction in
                Task { @MainActor [weak self] in
                    guard let self,
                          self.isCurrentOperation(cancellation),
                          !cancellation.isCancelled else { return }
                    let shown = max(self.progress ?? 0, fraction)
                    self.progress = shown
                    self.statusText = "\(operationName)… \(Int(shown * 100)) %"
                }
            }
        }.value
        guard epoch == datasetEpoch else { return .failed("The dataset changed during the run") }
        if cancellation.isCancelled {
            acomSession.lastEndToEndDuration = Date().timeIntervalSince(actionStarted)
            statusText = "ACOM matching cancelled"
            return .cancelled
        }
        guard let map else {
            presentComputeFailure(SimpleError("ACOM matching failed to initialize."))
            return .failed("ACOM matching failed to initialize.")
        }
        guard resolvedACOMModel?.revisionID == modelRevision,
              acomScaleSemantics == scaleSemantics else {
            statusText = "Discarded ACOM result because its material or Q scale changed"
            return .failed("Discarded ACOM result because its material or Q scale changed")
        }
        acomSession.orientationMap = map
        acomSession.hasOrientationMap = true
        // Recipe step (v2 S5). Everything from the CAPTURED run semantics,
        // nothing from live state: the first version recorded the exploratory
        // slider even when the run matched at the calibrated physical scale —
        // a replay at 0.01 Å⁻¹/px instead of the calibrated value gets every
        // orientation wrong with no shape check to catch it (Gate B-lite F3).
        // The material is recorded by ID: a replay that cannot resolve it
        // must fail by name, never fall back to a different crystal.
        // The custom id carries structure and Z but not a₀; the record also
        // carries lattice_a so replay can refuse a drifted a₀ by name.
        recordReplayStep(kind: "acom",
                         parameters: ReplayStepPlan.ACOMReplayPlan.recordedParameters(
                             model: model, scale: scale, backend: map.matchingBackend.rawValue,
                             scope: scope, quality: quality),
                         replaying: replaying)
        acomSession.lastRunScope = scope
        acomSession.lastRunQuality = quality
        acomSession.lastRunSemantics = runSemantics
        acomSession.lastMatchedPositionCount = workCount
        let elapsed = max(Date().timeIntervalSince(actionStarted), 0.001)
        acomSession.lastEndToEndDuration = elapsed
        acomSession.lastPositionsPerSecond = Double(workCount) / elapsed
        acomLastMeasuredTemplateCount = plan.count
        acomLastMeasuredBackend = map.matchingBackend
        acomSession.regionSelectionActive = false
        promoteIPFZDisplayIfDefault(for: map)
        applyACOMDisplay()
        statusText = String(
            format: "ACOM %@ ✓  %@ · %@ · %@ positions · %.1f s",
            scope.resultQualifier, map.matchingBackend.rawValue,
            runSemantics.scale.provenance.displayName,
            workCount.formatted(), elapsed
        )
        // R17 (owner, 2026-09-01): a landed preview's natural next step is
        // the full map, so the scope — and with it the header's primary
        // action — advances to it. The segmented control shows the change,
        // and the user can step back to Preview at any time.
        if scope == .preview { acomSession.scope = .fullScan }
        return .published
    }

    /// The one publish site for every ACOM display mode: pixels, label,
    /// validity and quality fields chosen together (v2.5 step 3e, condition 2).
    private func applyACOMDisplay() {
        guard let map = acomSession.orientationMap, navigation.analysisMode == .acom else { return }
        resultColormap = .viridis
        let payload: ProductPayload
        let baseKind: String
        switch acomSession.display {
        case .ipfZ:           payload = .rgba(map.ipfZImage(maskingReliabilityBelow: acomEffectiveReliabilityThreshold)); baseKind = "acom_ipf_z"
        case .reliability:    payload = .scalar(map.reliabilityImage);            baseKind = "acom_reliability"
        case .disorientation: payload = .scalar(map.symmetryDisorientationImage); baseKind = "acom_\(map.symmetry.rawValue)_fz_angle"
        case .score:          payload = .scalar(map.scoreImage);                  baseKind = "acom_score"
        case .inPlane:        payload = .scalar(map.inPlaneAngleImage);           baseKind = "acom_in_plane"
        case .phi1:           payload = .scalar(map.phi1Image);                   baseKind = "acom_phi1"
        case .Phi:            payload = .scalar(map.PhiImage);                    baseKind = "acom_Phi"
        case .phi2:           payload = .scalar(map.phi2Image);                   baseKind = "acom_phi2"
        }
        // All three scopes are named, including full scan: a product whose
        // label said least about how it was made was the most complete one.
        let scope = acomSession.lastRunScope ?? .fullScan
        let angular: Set<ACOMDisplayMode> = [.inPlane, .phi1, .Phi, .phi2, .disorientation]
        // The gate travels with the product: threshold and the fraction it keeps.
        var gateProvenance: [String: String] = [:]
        if let threshold = acomEffectiveReliabilityThreshold,
           let kept = map.fractionOfMatchedPositions(withReliabilityAtLeast: threshold) {
            gateProvenance["reliability_threshold"] = String(format: "%.3f", threshold)
            gateProvenance["fraction_above_reliability_threshold"] = String(format: "%.3f", kept)
        }
        publishProduct(
            kind: "acom_\(scope.resultQualifier)_\(baseKind.dropFirst(5))",
            displayName: "ACOM \(scope.rawValue.lowercased()) · \(acomSession.display.rawValue)",
            valueUnits: angular.contains(acomSession.display) ? "rad" : "dimensionless",
            payload: payload,
            validityMask: map.results.map { $0.templateIndex >= 0 },
            qualityFields: [
                ProductQualityField(name: "reliability", units: "dimensionless", image: map.reliabilityImage),
                ProductQualityField(name: "score", units: "dimensionless", image: map.scoreImage),
            ],
            overlays: [ProductOverlayDescriptor(
                kind: "matched_template", provenance: "selected ACOM orientation template")])
        if !gateProvenance.isEmpty, let product = publishedProduct {
            publishedProduct = DisplayedProduct(
                origin: product.origin, kind: product.kind, displayName: product.displayName,
                payload: product.payload, domain: product.domain, validityMask: product.validityMask,
                qualityFields: product.qualityFields, sampling: product.sampling,
                valueUnits: product.valueUnits, quantitativeStatus: product.quantitativeStatus,
                provenance: product.provenance.merging(gateProvenance) { _, gate in gate },
                overlays: product.overlays)
        }
    }

    // MARK: - Fit-verification overlays (diffraction pane)

    /// Fit overlays are only meaningful on the single pattern they were
    /// measured from: the per-position stored vectors do not describe the
    /// mean/max pattern or an ROI-summed virtual pattern.
    private var patternShowsSelectedPosition: Bool {
        realSpaceShape == .point && patternDisplayMode == .current
    }

    private var overlayReferenceOrigin: (x: Float, y: Float)? {
        guard let d = descriptor else { return nil }
        return calibrationSession.calibration.meanOrigin ?? (x: Float(d.qx) / 2, y: Float(d.qy) / 2)
    }

    /// Stored (raw detector) Bragg peaks at the selected scan position —
    /// the measured evidence the strain/ACOM overlays are judged against.
    var storedPeaksAtSelection: [BraggPeak] {
        guard let bragg = braggVectors, let d = descriptor,
              bragg.scanWidth == d.rx, bragg.scanHeight == d.ry,
              patternShowsSelectedPosition else { return [] }
        let scan = selectedScan.y * d.rx + selectedScan.x
        guard bragg.peaks.indices.contains(scan) else { return [] }
        return bragg.peaks[scan]
    }

    /// Local fitted lattice vs reference lattice at the selected position,
    /// mapped back onto the raw pattern.
    var strainFitOverlay: FitOverlays.StrainOverlay? {
        guard showFitOverlay, navigation.analysisMode == .strain,
              patternShowsSelectedPosition,
              let map = strain.map, let d = descriptor,
              map.width == d.rx, map.height == d.ry,
              let origin = overlayReferenceOrigin else { return nil }
        return FitOverlays.strainOverlay(
            map: map,
            scanIndex: selectedScan.y * d.rx + selectedScan.x,
            calibration: calibrationSession.calibration, referenceOrigin: origin,
            patternWidth: d.qx, patternHeight: d.qy
        )
    }

    /// The matched template's predicted reflections at the selected position.
    var acomFitOverlay: FitOverlays.TemplateOverlay? {
        guard showFitOverlay, navigation.analysisMode == .acom,
              patternShowsSelectedPosition,
              let plan = acomSession.orientationPlan, let map = acomSession.orientationMap,
              let d = descriptor, map.width == d.rx, map.height == d.ry,
              selectedScan.x >= 0, selectedScan.x < map.width,
              selectedScan.y >= 0, selectedScan.y < map.height,
              let origin = overlayReferenceOrigin else { return nil }
        let result = map[selectedScan.x, selectedScan.y]
        guard result.templateIndex >= 0 else { return nil }
        return FitOverlays.acomTemplateOverlay(
            result: result, plan: plan,
            invAngstromPerPixel: acomScale,
            calibration: calibrationSession.calibration, referenceOrigin: origin,
            scanIndex: selectedScan.y * d.rx + selectedScan.x,
            scanWidth: d.rx, scanHeight: d.ry,
            patternWidth: d.qx, patternHeight: d.qy
        )
    }

    /// The origin the calibration would use for the displayed pattern:
    /// per-position fitted origin for the current pattern, mean origin for
    /// the mean/max pattern.
    var originFitOverlayPoint: (x: Float, y: Float)? {
        guard showFitOverlay, navigation.workspaceArea == .prepare,
              calibrationSession.calibration.hasFittedOrigin, let d = descriptor,
              realSpaceShape == .point else { return nil }
        switch patternDisplayMode {
        case .current:
            guard let mean = calibrationSession.calibration.meanOrigin else { return nil }
            return FitOverlays.localOrigin(
                calibration: calibrationSession.calibration, referenceOrigin: mean,
                scanIndex: selectedScan.y * d.rx + selectedScan.x,
                scanWidth: d.rx, scanHeight: d.ry
            )
        case .mean, .max:
            return calibrationSession.calibration.meanOrigin
        }
    }

    /// Fitted ellipse sampled in raw detector pixels. Prefers the in-app fit
    /// (which carries its own center); a session/file ellipse without a center
    /// is drawn around the mean origin.
    var ellipseFitOverlayPolyline: [FitOverlays.Marker] {
        guard showFitOverlay, navigation.workspaceArea == .prepare,
              descriptor != nil else { return [] }
        if let fit = calibrationSession.lastEllipseFit {
            return FitOverlays.ellipsePolyline(
                centerX: Float(fit.centerQY), centerY: Float(fit.centerQX),
                a: fit.a, b: fit.b, theta: fit.theta
            )
        }
        guard calibrationSession.calibration.hasEllipse,
              let a = calibrationSession.calibration.ellipseA, let b = calibrationSession.calibration.ellipseB,
              let theta = calibrationSession.calibration.ellipseTheta,
              let mean = calibrationSession.calibration.meanOrigin else { return [] }
        return FitOverlays.ellipsePolyline(
            centerX: mean.x, centerY: mean.y, a: a, b: b, theta: theta
        )
    }

    /// True when the current mode/state could produce a fit overlay, so the
    /// toggle only appears where it has an effect.
    var fitOverlayIsAvailable: Bool {
        guard descriptor != nil else { return false }
        switch navigation.analysisMode {
        case .strain: return strain.map != nil
        case .acom: return acomSession.hasOrientationMap
        default:
            return navigation.workspaceArea == .prepare
                && (calibrationSession.calibration.hasFittedOrigin || calibrationSession.calibration.hasEllipse)
        }
    }
}

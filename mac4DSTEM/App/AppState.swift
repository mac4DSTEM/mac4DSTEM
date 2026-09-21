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

// `ParallaxResultProduct` moved to `Session/PhaseContrastProduct.swift` (seam
// 1, docs/appstate-seams-plan.md): a Session-layer owner cannot reference a
// type defined in App/, so it moved with the state that uses it.

/// Which image pane the user is currently operating on. Determines which ROI
/// tools the left panel shows and where interactions are routed.
enum ActivePane {
    case diffraction   // detector ROI → real-space image (virtual imaging)
    case realSpace     // region ROI → diffraction pattern (virtual diffraction)
}

// `RegionShape` moved to `Core/Analysis/VirtualDetector.swift` (C7 session 4,
// budget relocation) — a placement change, not a policy change.

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
    /// Seam 6 (docs/appstate-seams-plan.md): the live reader/array pair,
    /// dataset list, preview, loading state and stale-publish epoch. Readers go
    /// directly to the owner; AppState has no forwarding properties.
    let datasetSession = DatasetSession()

    /// Whether the open cube is held in memory, and the preload's progress.
    /// Owned by its own type, with no forwarding properties on `AppState` —
    /// see `DatasetResidency.swift` for why. Views read `residency.…`.
    let residency = DatasetResidency()

    /// Which part of the source file is loaded, and what moving the calibration
    /// into that frame cost. Stage L3's seam — see `Session/LoadedView.swift`.
    let loadedView = LoadedView()

    var openURL: URL?
    @ObservationIgnored var pendingRecovery: DatasetRecoveryRecord?
    /// S1's seam (docs/archive/development-process-2026-08-31.md §7): the one owner of where this
    /// dataset's session sidecar is and whether the app may read it. Replaces a
    /// bare `scopedSessionSidecarURL` that eight call sites derived around in
    /// two different ways — see `Session/SessionSidecarLocator.swift`.
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

    init(
        sessionSidecar: SessionSidecarLocator = SessionSidecarLocator(),
        materialsProject: MaterialsProjectSettings? = nil,
        preferences: AppPreferences? = nil,
        recents: RecentDatasets? = nil
    ) {
        self.sessionSidecar = sessionSidecar
        self.recents = recents ?? RecentDatasets()
        // Not a default *parameter* value: `MaterialsProjectSettings` is
        // `@MainActor`, and a default argument expression is always checked
        // as nonisolated, regardless of the initializer's own isolation — so
        // constructing the fallback here, inside the (MainActor) init body,
        // is what actually compiles.
        self.materialsProject = materialsProject ?? MaterialsProjectSettings()
        // Local `let`, not `self.preferences`, so the closures handed to
        // `OperationCenter` below capture a plain value instead of `self`
        // before every other stored property has one (two-phase init).
        //
        // Finding C (adversarial review, 2026-09-21): the fallback must not
        // be `AppPreferences()`, whose default store is the real
        // `UserDefaults.standard` — `sessionSidecar`/`materialsProject` keep
        // that same real store out of a bare `AppState()` by staying LAZY
        // (nothing touches the store until a caller asks a specific
        // question), but `AppPreferences.init` cannot be made lazy the same
        // way: by design (its own header) it decodes every key into a stored
        // `@Observable` property immediately, so it always has to read
        // something at construction. The mirror that fits here is instead
        // `AppPreferencesTests.scratchDefaults()`'s shape — a private,
        // uniquely named suite nothing else ever opens — applied
        // automatically so none of the ~123 bare `AppState()`/
        // `AppState(recents:)` call sites in mac4DSTEMTests (this file is
        // hosted inside mac4DSTEM.app under the unit gate, so `.standard` IS
        // the app's own domain) can seed from, or write into, the owner's
        // real Settings. Production never reaches this branch — the one
        // production call site (`App/mac4DSTEMApp.swift`) always supplies
        // its own `AppPreferences(defaults: .standard)` explicitly — so nothing
        // about shipped behaviour changes.
        let preferences = preferences ?? AppPreferences(defaults: Self.scratchPreferencesDefaults())
        self.preferences = preferences
        self.operationCenter = OperationCenter(
            beginKeepAwake: {
                guard preferences.keepAwake else { return nil }
                return ProcessInfo.processInfo.beginActivity(
                    options: [.idleSystemSleepDisabled],
                    reason: "mac4DSTEM analysis run"
                )
            },
            endKeepAwake: { ProcessInfo.processInfo.endActivity($0) }
        )
        // Session S21 (`ROADMAP.md` "Settings window"): a FRESH window's
        // starting colormap/intensity/engine choice, read once here — never
        // re-applied later, so an analysis's own colormap choice (a
        // diverging strain or DPC-difference map, `AppState+DPC.swift`,
        // `AppState+ResultPresentation.swift`) is never overridden by a
        // stale default.
        //
        // `patternColormap`/`logScale` bump `patternVersion` on every
        // assignment (their own `didSet`, below) — restore it after seeding
        // so this one-time default is invisible to version-gated caches, the
        // same reason `resultPresentation.seedInitialColormap` exists rather
        // than a plain `resultColormap =`.
        let priorPatternVersion = patternVersion
        patternColormap = preferences.diffractionColormap
        logScale = preferences.intensityDisplay.isLog
        patternVersion = priorPatternVersion
        resultPresentation.seedInitialColormap(preferences.mapColormap)
        acomSession.backend = preferences.enginePreference
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
            resultPresentation.replaceProduct(nil)
            resultPresentation.bumpResultVersion()
        }
        navigation.onModeChange = { [weak self] in
            self?.persistRecoveryPosition()
        }
        // Seam 3 (docs/appstate-seams-plan.md): the live overlay needs
        // `probeKernel`/`navigation`/`displayedPattern`, none of which
        // `diskDetection` holds — same hook shape as `strain
        // .onPresentationChange` above. Body unchanged from the pre-seam
        // `diskParams` `didSet`.
        diskDetection.onParamsChange = { [weak self] in
            Task { await self?.detectCurrentPattern() }
        }
        // Seam 4 (docs/appstate-seams-plan.md): the display derivation needs
        // `comField`/`descriptor`/`navigation`/`calibrationSession`, none of
        // which `dpc` holds — same hook shape as `diskDetection
        // .onParamsChange` above. Body unchanged from the pre-seam
        // `dpcDisplay` `didSet` (its return value was ignored there too).
        dpc.onDisplayChange = { [weak self] in
            _ = self?.applyDPCDisplay()
        }
    }

    /// A private, uniquely named `UserDefaults` suite for `init`'s
    /// `preferences` fallback — see Finding C's note above. Nothing this
    /// initializer does ever WRITES through it (only `AppPreferences.init`'s
    /// own reads, all misses against a fresh suite), so unlike
    /// `AppPreferencesTests.scratchDefaults()` there is nothing to remove
    /// afterward: an unwritten suite leaves no plist behind.
    private static func scratchPreferencesDefaults() -> UserDefaults {
        let suite = "mac4dstem.appstate-default-preferences.\(UUID().uuidString)"
        return UserDefaults(suiteName: suite) ?? .standard
    }

    /// The recents list and its location labels. S3's seam
    /// (docs/archive/development-process-2026-08-31.md §7) — see `Session/RecentDatasets.swift`.
    /// Views read `recents.…`; no forwarding properties. // v2 S3
    let recents: RecentDatasets
    /// The session's recipe — which analyses ran, with which parameters. S5's
    /// seam (docs/archive/development-process-2026-08-31.md §7) — see `Session/SessionReplay.swift`.
    /// No forwarding properties. // v2 S5
    let replay = SessionReplay()
    /// The state of the unattended promote run — S6's seam
    /// (docs/archive/development-process-2026-08-31.md §7) — see `Session/ReplayRun.swift`.
    /// Views read `replayRun.…`; no forwarding properties. // v2 S6
    let replayRun = ReplayRun()
    /// The configured-open slot consumed by commit or discard. The payload's
    /// preview/configuration remain owned by `PendingLoad`; no forwarding.
    let promotionRun = PromotionRun<PendingLoad>()
    /// The session's "may I?" policy gates — S7's seam
    /// (docs/archive/development-process-2026-08-31.md §7) — see `Session/SessionGates.swift`.
    /// Views read `gates.…`; no forwarding properties. // v2 S7
    let gates = SessionGates()
    /// The strain product and its run controls — S8's seam
    /// (docs/archive/development-process-2026-08-31.md §7) — see `Session/StrainProduct.swift`.
    /// Views read `strain.…`; no forwarding properties. // v2 S8
    let strain = StrainProduct()
    let diffractionGroups = DiffractionGroupsProduct()
    let phaseMapping = PhaseMappingProduct()
    /// Spatial precipitate objects. Session S3
    /// (`docs/v3-features.md#precipitates-mp-plan`) wired its first
    /// producer: `AppState+PhaseMapping.swift` publishes here from every
    /// finished vector-matched phase map, via the pure
    /// `PhaseMapObjectsBridge`. The pre-registered FULL-diffraction-pattern
    /// classification route this owner was originally scoped for
    /// (`docs/v3-features.md#precipitate-classification` §2) remains unbuilt and
    /// would be a second producer, not a replacement. Neither producer nor
    /// this owner makes a validation claim of its own — the phase map's
    /// `validation: "none"` badge covers what is read off it. Views read
    /// `precipitateClassification.…` directly; no forwarding properties.
    let precipitateClassification = PrecipitateClassificationProduct()
    /// Session S5: whether a Materials Project API key is stored, and the
    /// save/remove actions the Settings scene drives — composition only, no
    /// forwarding properties (`Session/MaterialsProjectSettings.swift`). This
    /// is the one piece of state the owner's product decision (Materials
    /// Project as the default phase source) needs on every window, so no
    /// other existing owner is the honest home for it. Injectable in `init`
    /// for the same reason `sessionSidecar` is: the default reads and writes
    /// the REAL Keychain item, which a test must never touch.
    let materialsProject: MaterialsProjectSettings
    /// The Settings window's state (session S21, `ROADMAP.md` "Settings
    /// window, Xcode-style sidebar"). Reached from here only for the few
    /// places `AppState` itself must consult a default — seeding a fresh
    /// window's colormap/intensity/engine choices and the primary "Open
    /// Dataset…" behaviour in `init`/`requestOpenDataset` below, and the
    /// keep-awake closure handed to `operationCenter`. Every VIEW reads
    /// `AppPreferences` from `.environment(preferences)` instead
    /// (`App/mac4DSTEMApp.swift`), never through this property. Injectable
    /// for the same reason `materialsProject` is — a test that wants to
    /// assert on a CHOSEN preference must supply its own suite-private
    /// `AppPreferences(defaults:)` (`AppPreferencesTests.scratchDefaults()`'s
    /// shape) — but unlike `materialsProject`/`sessionSidecar`, the omitted
    /// case is ALSO safe: `init`'s fallback is a private scratch suite, never
    /// `.standard` (Finding C, adversarial review 2026-09-21; see `init`'s
    /// `scratchPreferencesDefaults()`), so a bare `AppState()` cannot read or
    /// write the owner's real Settings either way.
    let preferences: AppPreferences
    /// Seam 5 (docs/appstate-seams-plan.md): the retained product, result
    /// controls and their derived caches. Views read `resultPresentation.…`;
    /// cross-owner combiners are placed in `AppState+ResultPresentation.swift`.
    let resultPresentation = ResultPresentation()
    /// The last reciprocal-pixel calibration attempt — S13's seam
    /// (docs/archive/development-process-2026-08-31.md §7) — see `Session/QCalibrationRun.swift`.
    /// Views read `qCalibration.…`; no forwarding properties. // v2 S13
    let qCalibration = QCalibrationRun()
    /// What happened this session, for the output strip — the 2026-09-04
    /// seam (docs/archive/development-process-2026-08-31.md §7) — see `App/ActivityLog.swift`.
    /// Views read `activityLog.messages`; no forwarding properties.
    let activityLog = ActivityLog()

    /// The ONE entry for recipe steps. Recording is suppressed while a
    /// dataset load is in flight: the automatic re-establishing pass on open
    /// (and after a promote or reconfigure) runs with whatever parameters the
    /// fresh session holds — DEFAULTS — and recording it would overwrite an
    /// adopted colleague's step with them. Merely opening a file must never
    /// mutate its recipe (Gate B-lite refutation F1, 2026-08-24). // v2 S5
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
    /// Widened from `private` (seam 2, docs/appstate-seams-plan.md):
    /// `App/AppState+ACOM.swift`'s `runACOM` calls it from outside this file.
    func recordReplayStep(kind: String,
                                  parameters: [String: String],
                                  invalidating downstream: [String] = [],
                                  replaying: Bool) {
        guard !datasetSession.isLoading, !replaying else { return }
        replay.record(kind: kind, parameters: parameters, invalidating: downstream,
                      under: ReplayParameterFrame.of(loadedView.specification))
    }
    var recoveryRecord: DatasetRecoveryRecord? = WorkspaceRecoveryStore.recovery()
    var descriptor: DatasetDescriptor?
    var selectedScan = ScanPos(x: 0, y: 0)

    var currentPattern: DiffractionPattern?
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
        resultPresentation.replaceProduct(DisplayedProduct(
            origin: .restoredFromSidecar,
            kind: kind, displayName: displayName, payload: payload, domain: domain,
            sampling: ProductSampling(row: pixelSizeRow, column: pixelSizeColumn, units: pixelUnits),
            valueUnits: valueUnits, quantitativeStatus: status, provenance: provenance))
    }

    /// v2.5 step 3e: a compute site publishes its product with ITS OWN
    /// kind/name/units — condition 2 of plan §9d, one site at a time. Sampling
    /// and provenance still come from the per-mode persistence metadata; a
    /// product that is not the mode's own (the disagreement map published from
    /// Disk detection, C7 session 3) passes its domain and its own keys.
    func publishProduct(
        kind: String, displayName: String, valueUnits: String, payload: ProductPayload,
        validityMask: [Bool]? = nil, qualityFields: [ProductQualityField] = [],
        overlays: [ProductOverlayDescriptor] = [],
        domain: ProductDomain? = nil, extraProvenance: [String: String] = [:]
    ) {
        let persisted = currentScalarPersistenceMetadata
        let domain = domain ?? activeResultDomain
        var provenance = persisted.provenance.merging(extraProvenance) { _, new in new }
        provenance["display_domain"] = domain.rawValue
        let status = provenance["quantitative_status"].flatMap(ProductQuantitativeStatus.init)
            ?? quantitativeStatus(for: kind, units: valueUnits)
        provenance["quantitative_status"] = status.rawValue
        resultPresentation.publish(DisplayedProduct(
            kind: kind, displayName: displayName, payload: payload, domain: domain,
            validityMask: validityMask, qualityFields: qualityFields,
            sampling: ProductSampling(row: persisted.row, column: persisted.column, units: persisted.units),
            valueUnits: valueUnits, quantitativeStatus: status, provenance: provenance,
            overlays: overlays))
    }

    /// Last structural scan-space image available for positioning regions.
    /// This is navigation context, not a scientific result: selecting an ACOM
    /// region must not replace the Bragg map/result that can still be saved.
    var scanNavigationImage: FloatImage?
    var scanNavigationVersion = 0
    func bumpScanNavigationVersion() { scanNavigationVersion &+= 1 }
    /// Set only while `resultPresentation.resultImage` is the scalar map restored from the stable
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
    /// Seam 1 (docs/appstate-seams-plan.md): the Parallax and single-slice
    /// ptychography products and their run controls. Every reader goes
    /// there directly; there are no forwarding properties.
    let phaseContrast = PhaseContrastProduct()
    let ptychography = PtychographySettings()
    /// Full rotation-calibration result (objective curves) for the
    /// diagnostics plot in the inspector.
    var lastRotationResult: RotationCalibration.Result?
    var patternVersion = 0

    // DPC: cached CoM shift field so display-mode switches don't re-run the
    // GPU. Widened from `private` (seam 4, docs/appstate-seams-plan.md):
    // `App/AppState+DPC.swift`'s `runDPC`/`applyDPCDisplay` read/write it
    // from a different file.
    @ObservationIgnored var comField: [Float]?

    // Disk detection state. `diskParams` and its pure size-aware defaulting
    // moved to `diskDetection` (seam 3, docs/appstate-seams-plan.md); these
    // stay because they read AppState-only or another owner's state
    // (`descriptor`, `probeKernel`, `calibrationSession`, `resultPresentation.braggVectors`)
    // that cannot move with it. `currentDiskDiagnostics`/`resultPresentation.braggVectors`/
    // `completedDiskSummary` widen from `private(set)` and
    // `liveDetectionRequest` from `private` — all four are now set/mutated
    // from `App/AppState+DiskDetection.swift`, a different file.
    var probeKernel: ProbeKernel?
    var currentPeaks: [BraggPeak] = []
    var currentDiskDiagnostics: DiskDetectionPatternDiagnostics?
    var completedDiskSummary: DiskDetectionScanSummary?
    @ObservationIgnored var liveDetectionRequest: UInt64 = 0
    /// Seam 3 (docs/appstate-seams-plan.md): the disk-detection run controls'
    /// one owner. Every reader goes there directly; there are no forwarding
    /// properties.
    let diskDetection = DiskDetectionProduct()

    /// Return every detector control to the same size-aware defaults used
    /// when this dataset was opened — now including the fitted probe radius if
    /// one has been measured since, which is what makes the minimum-spacing
    /// default physically meaningful. The pure construction is
    /// `diskDetection.reset(qy:qx:probeRadius:)`; this wrapper resolves the
    /// AppState-only inputs the owner cannot read itself.
    func resetDiskDetectionParams() {
        guard let descriptor else { return }
        diskDetection.reset(qy: descriptor.qy, qx: descriptor.qx, probeRadius: fittedProbeRadius)
    }

    /// The probe radius to scale detector defaults with: the generated
    /// kernel's, else the calibration's. Same precedence `diskDetectionContext`
    /// uses, so the controls validate against the value they were derived from.
    var fittedProbeRadius: Float? {
        probeKernel?.probeRadius ?? calibrationSession.calibration.probeRadius
    }

    /// Re-derive the disk-detection defaults once a probe radius is known.
    /// `diskParams` is seeded at dataset load, before any calibration has run,
    /// so its minimum spacing is the detector-scaled placeholder rather than a
    /// probe-scaled value. Measuring the probe is what makes the real default
    /// computable — see `DiskDetectionParams.detectorAdapted`, where the
    /// detector-scaled value is shown to suppress the shortest g-vectors on
    /// two of the four training datasets.
    /// Only replaces the spacing if the user has not chosen one: it is
    /// compared against the placeholder's spacing *alone*, not the whole
    /// parameter struct. Whole-struct equality looks safer and is worse — a
    /// user who raises Maximum peaks (a natural response to a doubled yield)
    /// or nudges any unrelated control would then be pinned to the
    /// detector-scaled spacing permanently, with nothing on screen saying why.
    /// The pure guard/compare/assign is `diskDetection.refreshForMeasuredProbe
    /// (qy:qx:probeRadius:)`; this wrapper resolves the AppState-only inputs.
    func refreshDiskDefaultsForMeasuredProbe() {
        guard let descriptor else { return }
        diskDetection.refreshForMeasuredProbe(qy: descriptor.qy, qx: descriptor.qx, probeRadius: fittedProbeRadius)
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
        return diskDetection.diskParams.validationIssues(in: context)
    }

    var diskDetectionConfigurationIsValid: Bool {
        !diskDetectionValidationIssues.contains { $0.severity == .error }
    }

    /// Full-scan vectors remain available for comparison, but downstream
    /// analysis must not silently imply that newly previewed settings
    /// produced them. C4(b): now also catches kernel/learned-detector drift.
    var diskDetectionSettingsAreStale: Bool {
        guard resultPresentation.braggVectors != nil else { return false }
        return ProductWorkflow.stalenessVerdict(recordedStep: recordedReplayStep(for: .disks),
            currentSignature: currentReplaySignature(for: .disks), hasProduct: true) != .current
    }

    var hasCurrentBraggVectors: Bool {
        resultPresentation.braggVectors != nil && !diskDetectionSettingsAreStale
    }

    /// ACOM state, plan and map live in `ACOMSession` (v2.5 step 6a); the
    /// forwarders went in 7c 4b. The run functions moved to
    /// `App/AppState+ACOM.swift` in seam 2 (docs/appstate-seams-plan.md) and
    /// still read the session directly; the session's hooks below carry the
    /// effects that need the window.
    let acomSession = ACOMSession()

    /// Learned-vs-classical detector option and state; no forwarding
    /// properties — see `Session/LearnedDetection.swift`.
    let learnedDetection = LearnedDetectionSession()

    /// Hand-clicked disk-centre labels (C7 session 4) — see `Session/DiskCentreLabels.swift`.
    let diskCentreLabels = DiskCentreLabelStore()

    /// `acomWorkPositionCount` and its dependents need `descriptor` (rx/ry),
    /// which only AppState holds, so they stay here as orchestration over
    /// `ACOMSession`'s moved `scanSelection`/`estimatedDuration` (seam 2,
    /// docs/appstate-seams-plan.md) rather than becoming forwarders — see the
    /// "seam 2 additions" note atop `Session/ACOMSession.swift`.
    var acomWorkPositionCount: Int {
        guard let descriptor else { return 0 }
        return acomSession.scanSelection(selectedX: selectedScan.x, selectedY: selectedScan.y)
            .positionCount(width: descriptor.rx, height: descriptor.ry)
    }

    var acomWorkSummary: String {
        "\(acomWorkPositionCount.formatted()) positions × \(acomSession.quality.templateCount) templates"
    }

    var acomEstimatedDuration: TimeInterval? {
        acomSession.estimatedDuration(forPositions: acomWorkPositionCount)
    }

    /// What a full-scan run would cost, using the same throughput the panel
    /// already shows for the current scope — deliberately not a second
    /// estimator, so the suggestion cannot disagree with the "Expected" row.
    var acomFullScanEstimatedDuration: TimeInterval? {
        guard let descriptor else { return nil }
        return acomSession.estimatedDuration(
            forPositions: ACOMScanSelection.full.positionCount(
                width: descriptor.rx, height: descriptor.ry
            )
        )
    }

    /// A full scan this cheap is offered as one click instead of leaving the
    /// user on a 32×32 preview. Measured motivation: sim_Au's full 84×100 scan
    /// against 200 templates ran in 0.7 s while the panel estimated ~2 s.
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
        showsACOMRegionReference ? scanNavigationImage : resultPresentation.resultImage
    }

    var displayedResultRGBA: RGBAImage? {
        showsACOMRegionReference ? nil : resultPresentation.resultRGBA
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
        showsACOMRegionReference ? .viridis : resultPresentation.resultColormap
    }

    var displayedResultRangeLo: Float {
        showsACOMRegionReference ? 0 : resultPresentation.displayRangeLo
    }

    var displayedResultRangeHi: Float {
        showsACOMRegionReference ? 1 : resultPresentation.displayRangeHi
    }

    var displayedResultGamma: Float {
        showsACOMRegionReference ? 1 : resultPresentation.resultGamma
    }

    var displayedResultVersion: Int {
        showsACOMRegionReference ? scanNavigationVersion : resultPresentation.resultVersion
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
        if let product = resultPresentation.product { return product }
        guard let payload: ProductPayload = resultPresentation.resultImage.map(ProductPayload.scalar)
                ?? resultPresentation.resultRGBA.map(ProductPayload.rgba) else { return nil }
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
        case .virtualDetector, .dpc, .strain, .acom, .diffractionGroups, .phaseMapping: .scan
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

    /// The quality field currently shown instead of the scientific map, when
    /// inspection is on and the displayed product carries one.
    var displayedQualityField: ProductQualityField? {
        resultPresentation.qualityField(for: displayedProduct)
    }

    var selectedEulerText: String? {
        acomSession.orientationMap?.eulerText(x: selectedScan.x, y: selectedScan.y)
    }

    /// Whether the real-space ROI must be drawn on the scan image.
    /// This is now simply "is an ROI in force", because `displayedPattern`
    /// substitutes the ROI-summed pattern for the current one whenever
    /// `realSpaceShape != .point` — in *every* task, not just the ones that
    /// nominally use a region.
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
        guard let model, model.isUsable, model.supportsOrientationMapping else { return nil }
        return model
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
    /// Widened from `private` (seam 2, docs/appstate-seams-plan.md):
    /// `App/AppState+ACOM.swift`'s `runACOM` calls it from outside this file.
    func promoteIPFZDisplayIfDefault(for map: OrientationMap) {
        guard !acomSession.displayIsUserChosen,
              acomSession.display == .reliability,
              map.symmetry != .identity
        else { return }
        acomSession.display = .ipfZ
    }

    var aperture = Aperture()

    // Active pane + real-space region (virtual diffraction).
    var activePane: ActivePane = .diffraction
    var realSpaceShape: RegionShape = .point
    var realSpaceRadius: Float = 6            // scan px half-extent / radius
    /// Seam 4 (docs/appstate-seams-plan.md): the DPC display choice's one
    /// owner, `dpc.dpcDisplay` (its `didSet` is now `dpc`'s own
    /// `onDisplayChange` hook, wired in `init()`). Every reader goes there
    /// directly; there are no forwarding properties.
    let dpc = DPCProduct()
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
    /// No default expression (unlike most of this file's stored properties):
    /// its keep-awake closures are wired from `preferences` in `init`, so it
    /// cannot be built before that resolves. See `OperationCenter`'s own
    /// header for why the seam lives on `isBusy`'s `didSet` rather than here.
    let operationCenter: OperationCenter
    var isBusy: Bool { operationCenter.isBusy }
    var statusText = "No file loaded" {
        didSet { activityLog.record(statusText) }
    }
    var errorMessage: String?

    private(set) var openDatasetRequest = 0
    private(set) var preprocessingExportRequest = 0

    /// The primary "Open Dataset…" gesture (⌘O, the sidebar's default
    /// button). `requestOpenDatasetWithOptions` below is always explicit —
    /// its own separate menu item/button — so `preferences.openBehaviour`
    /// only decides what THIS shared action does; it can never make the
    /// explicit "Open with Options…" action skip the configurator.
    func requestOpenDataset() {
        configureOnOpen = preferences.openBehaviour == .options
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
            hasPhysicalACOMScale: acomScaleSemantics.provenance.isPhysical,
            wantsLearnedDetector: learnedDetection.detectorClass == .learned,
            hasLearnedDetectorAsset: LearnedDiskDetector.bundledAssetURL() != nil
        )
    }

    /// C4(b): AppState gathers the live ingredients; `ProductWorkflow` dispatches by mode.
    func recordedReplayStep(for mode: AnalysisMode) -> SessionReplayRecord.Step? {
        ProductWorkflow.recordedReplayStep(for: mode, in: replay.record.steps)
    }

    /// The whole recorded pipeline, read-only — the bottom workspace's
    /// Lineage tab (ADR 034). `replay` itself carries mutation (`record`,
    /// `adopt`) that a view has no business calling, so it gets this forwarder
    /// rather than reaching `appState.replay.record.steps` directly.
    var replaySteps: [SessionReplayRecord.Step] { replay.record.steps }

    func currentReplaySignature(for mode: AnalysisMode) -> [String: String]? {
        let acomSignature = ReplayStepPlan.ACOMReplayPlan.currentSignatureIfResolved(
            model: resolvedACOMModel, scale: acomScaleSemantics.invAngstromPerPixel,
            backend: acomSession.effectiveBackend.rawValue, scope: acomSession.scope, quality: acomSession.quality)
        return ProductWorkflow.currentReplaySignature(for: mode, virtualDetectorShape: resultPresentation.virtualShape.rawValue, aperture: aperture,
            dpcOriginReference: calibrationSession.calibration.hasFittedOrigin ? "calibrated origins" : "global center", diskKernel: probeKernel,
            diskParams: diskDetection.diskParams, learnedDetectorParameters: learnedDetection.replayParameters(for: learnedDetection.detectorClass),
            strainSignature: strain.currentReplaySignature, acomSignature: acomSignature)
    }

    // The result-value cache moved to `resultPresentation` with the result
    // controls. The diffraction cache stays here with the CBED state.
    @ObservationIgnored private var patternValueRangeCache:
        (version: Int, log: Bool, low: Double, high: Double)?

    /// Raw-value endpoints currently assigned to the scalar result colorbar.
    var resultDisplayedValueRange: (low: Double, high: Double)? {
        resultPresentation.displayedValueRange(
            image: displayedResultImage,
            version: displayedResultVersion,
            regionReference: showsACOMRegionReference,
            colormap: displayedResultColormap,
            rangeLo: displayedResultRangeLo,
            rangeHi: displayedResultRangeHi
        )
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
    /// Cooperative: it asks, and the load unwinds at its next checkpoint.
    func cancelDatasetLoad() {
        guard datasetSession.requestCancellation() else { return }
        statusText = "Cancelling…"
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
        showReadout(status)   // progress is a readout; see ActivityLog.record
        // While the dataset is still opening, this operation IS the load: mirror
        // its measured progress into the welcome card rather than leaving that
        // card parked on its last named stage while work is visibly happening.
        if datasetSession.isLoading {
            datasetSession.mirrorOperationProgress(progress, status)
        }
    }

    func cancelActiveOperation() {
        guard let name = operationCenter.cancel() else { return }
        statusText = "Cancelling \(name)…"
    }

    // The result normalization caches moved to `resultPresentation`; the CBED
    // cache stays here with the diffraction-pattern state.
    @ObservationIgnored private var patternNormCache: (version: Int, log: Bool, pixels: [Float])?

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
        resultPresentation.normalizedResultPixels(
            image: displayedResultImage,
            version: displayedResultVersion,
            regionReference: showsACOMRegionReference,
            colormap: displayedResultColormap
        )
    }

    /// Display-normalized pixels of the quality field currently being
    /// inspected, cached per (result version, field name) — mirrors
    /// `normalizedResultPixels()`.
    func normalizedQualityPixels() -> [Float] {
        resultPresentation.normalizedQualityPixels(
            field: displayedQualityField, version: displayedResultVersion
        )
    }

    /// True when the displayed scalar result contains masked (no-data) pixels,
    /// which render as neutral gray. Drives the colorbar's masked swatch.
    func displayedResultHasMaskedPixels() -> Bool {
        resultPresentation.displayedResultHasMaskedPixels(
            image: displayedResultImage,
            version: displayedResultVersion,
            regionReference: showsACOMRegionReference,
            colormap: displayedResultColormap
        )
    }

    var displayedPattern: DiffractionPattern? {
        // A real-space region ROI drives the CBED with the summed pattern —
        // but only in Current mode (R20, owner 2026-09-01): Mean and Max are
        // whole-scan statistics, and a region sum silently replacing them
        // while their tab stayed selected was wrong. Point already behaved
        // this way; Rectangle/Circle now match it.
        if patternDisplayMode == .current,
           realSpaceShape != .point, let vd = resultPresentation.virtualDiffractionPattern { return vd }
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
    func currentDataSourceForExport() -> (any FourDDataSource)? { datasetSession.reader }

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
            } else if phaseContrast.parallaxPreprocess == nil {
                await prepareParallaxPreview()
            } else if phaseContrast.parallaxAlignment?.isComplete != true {
                await alignParallaxNextLevel()
            } else if phaseContrast.parallaxHigherOrderFit == nil {
                fitParallaxAberrations()
            } else if phaseContrast.parallaxCorrection == nil {
                await correctParallaxPhase()
            } else if phaseContrast.parallaxSubpixel == nil {
                await upsampleParallaxBF()
            }
        case .aiAnalysis:
            switch navigation.analysisMode {
            case .phaseMapping: await runPhaseMapping()
            default: await runDiffractionGroups()
            }
        case .results:
            break
        }
    }

    /// One load at a time: the bundled HDF5 is not thread-safe (`ConcurrentOpenRefusalTests`).
    func openFile(url: URL) {
        if datasetSession.isLoading { statusText = "Already opening a dataset — wait for that one to finish, or cancel it."; return }
        Task { await openFileAsync(url: url) }
    }

    /// The load specification a previous session recorded for this file, if any.
    /// Read BEFORE the load, because it decides what gets read. Reopening a
    /// session reopens the **source** file and re-applies the specification to
    /// it — it never re-derives from reduced data, which is the property that
    /// makes a crop a view rather than a new dataset.
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

    /// The load specification recorded by the session sidecar for the open
    /// dataset, if any. Compared against `loadedView.specification` so a
    /// restored result computed on a different view can be labelled as such.
    var sessionLoadSpecification: LoadSpecification?

    /// Which destination the next file-importer result goes to.
    var configureOnOpen = false

    /// Skip a session sidecar for exactly one reopen of this dataset identity.
    var ignoreSessionForDatasetID: String?

    /// Fitted origin maps displaced by a manual aperture-center drag.
    @ObservationIgnored var supersededFittedOrigin:
        (maps: OriginMaps, provenance: OriginProvenance)?
    var canRestoreFittedOrigin = false

    // MARK: - Calibration and phase contrast: AppState+Calibration.swift, AppState+PhaseContrast.swift (moved 2026-09-18)

    // MARK: - DPC: run + display derivation in AppState+DPC.swift, display
    // choice in Session/DPCProduct.swift (moved 2026-09-18, seam 4). What
    // stays here (`dpcMilliradiansPerDetectorPixel`, `idpcOriginFitRefusal`,
    // `idpcPhysicalCalibration`) are combiners over `calibrationSession`/
    // `gates` with no dependency on `dpc`'s own state — see
    // `Session/DPCProduct.swift`'s header for why the plan's "Moves" naming
    // of `dpcMilliradiansPerDetectorPixel` was corrected.
    //
    // Deleted (moved verbatim to `App/AppState+DPC.swift`; diffed against
    // the pre-seam file — identical apart from `dpcDisplay` →
    // `dpc.dpcDisplay`): `runDPC(replaying:)`, `flipRotation180()`,
    // `applyDPCDisplay() -> String?`.

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
    /// Distinct from "not yet calibrated" (missing origin, rotation or pixel
    /// sizes — the generic requirements note in the DPC controls): this is
    /// non-nil only when an origin fit EXISTS and the gate judges it
    /// non-quantitative, so the controls can say the true reason instead of
    /// listing requirements that are all met. // v2 S7
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
        guard let bragg = resultPresentation.braggVectors else {
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
        let epoch = datasetSession.epoch
        let map = await Task.detached(priority: .userInitiated) {
            StrainMapping.compute(bragg: calibrated.vectors,
                                  originX: origin.x, originY: origin.y,
                                  referenceMask: referenceMask,
                                  initialBasis: initialBasis,
                                  cancellation: cancellation)
        }.value
        guard epoch == datasetSession.epoch else { return .failed("The dataset changed during the run") }
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
        resultPresentation.resultColormap = .rdbu   // diverging map without recoloring the CBED pane
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
    /// Deliberately an **explicit action**, not a side effect of `changeMode`:
    /// navigating between tasks must never silently relabel the visible
    /// result, which `testNavigationDoesNotRelabelTheVisibleScientificResult`
    /// pins. The navigation/restored overrides are cleared first, because the
    /// user is now asking for a specific product rather than carrying the
    /// previous one along.

    // MARK: - Fit-verification overlays (diffraction pane)

    /// A value over a snapshot (`Session/FitOverlayPresentation.swift`, C5's
    /// first extraction): gating and the reopen boundary are pinned there.
    var fitOverlays: FitOverlayPresentation {
        FitOverlayPresentation(
            enabled: showFitOverlay,
            analysis: navigation.analysisMode == .strain ? .strain
                : navigation.analysisMode == .acom ? .acom : .other,
            inPrepare: navigation.workspaceArea == .prepare,
            showsCurrentPattern: patternDisplayMode == .current,
            pointSelection: realSpaceShape == .point,
            descriptor: descriptor, selectedX: selectedScan.x, selectedY: selectedScan.y,
            calibration: calibrationSession.calibration,
            ellipseFit: calibrationSession.lastEllipseFit,
            braggVectors: resultPresentation.braggVectors, strainMap: strain.map,
            orientationPlan: acomSession.orientationPlan,
            orientationMap: acomSession.orientationMap,
            hasOrientationMap: acomSession.hasOrientationMap,
            invAngstromPerPixel: acomScale
        )
    }
}

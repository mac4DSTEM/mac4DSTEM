//
//  SpectroscopyRoomController.swift
//  Role: Binds the Spectroscopy room's view model (`SpectroscopyRoomModel`, lane V) to the session owner
//        (`SpectroscopySession`) and the opened spectrum image (v5.0 WP2 R2). It decides nothing scientific: it asks
//        `Core` for sums, windows and maps, off the main actor, and puts what comes back into the model.
//
//  Owner: the room's PRESENTATION state (what the views show: tiles, rows, markers, the selected region's spectrum).
//  The facts (the image, the regions, the element roles, the selection) stay in `SpectroscopySession`; the model
//  mirrors them and the controller writes the user's edits back. `AppState` holds one instance because the model
//  carries SwiftUI types (it cannot live in DSTEMSession) and must outlive the room view, so the maps and the regions
//  survive a change of room.
//
//  Compute: a 1.7 GB Velox file is ~100 M events; one whole-map sum scans them all. Every pass runs in a detached task
//  and lands only if no newer request was made meanwhile (`generation`); spectra per region and net-count maps per
//  line window are cached (`SpectrumComputeCache`), so a new element set computes only the windows it has not seen.
//

import CoreGraphics
import Foundation
import Observation
import SwiftUI
#if canImport(DSTEMCore)
import DSTEMCore
import DSTEMSession
#endif

/// Spectra by region and maps by line window. Locked: written by detached tasks, read by the next one.
nonisolated final class SpectrumComputeCache: @unchecked Sendable {
    private let lock = NSLock()
    private var spectra: [Int: [UInt64]] = [:]
    private var maps: [String: [Double]] = [:]
    private var refinements: [String: AxisRefinementResult] = [:]
    private var proposals: [String: ProposalResult] = [:]

    func spectrum(_ region: Int) -> [UInt64]? { lock.withLock { spectra[region] } }
    func setSpectrum(_ s: [UInt64], _ region: Int) { lock.withLock { spectra[region] = s } }
    func map(_ key: String) -> [Double]? { lock.withLock { maps[key] } }
    /// The "int" mode's maps are another quantity on the same windows: keyed apart from the net ones.
    static func key(_ w: ResolvedWindow, integrated: Bool) -> String { (integrated ? "int|" : "") + key(w) }
    func setMap(_ m: [Double], _ key: String) { lock.withLock { maps[key] = m } }
    func refinement(_ key: String) -> AxisRefinementResult? { lock.withLock { refinements[key] } }
    func setRefinement(_ r: AxisRefinementResult, _ key: String) { lock.withLock { refinements[key] = r } }
    /// The unlisted-line check's proposer runs, keyed by region, listed elements and fit settings (`unlistedKey`).
    func proposal(_ key: String) -> ProposalResult? { lock.withLock { proposals[key] } }
    func setProposal(_ p: ProposalResult, _ key: String) { lock.withLock { proposals[key] = p } }
    /// A region that is gone takes its spectrum, its refinements and its proposer runs with it: its id may be given to a new one.
    func forget(region: Int) {
        lock.withLock {
            spectra[region] = nil
            for k in refinements.keys where k.hasPrefix("\(region)|") { refinements[k] = nil }
            for k in proposals.keys where k.hasPrefix("\(region)|") { proposals[k] = nil }
        }
    }

    /// The proposer's inputs for the unlisted-line check: the region's spectrum, the axis the fit used and the proposer's
    /// settings (listed elements, width, range, continuum, escape; least squares). The estimator, k, absorption and the
    /// dismissed elements do not change the proposal, so a dismissal or an estimator switch reuses it.
    static func unlistedKey(region: Int, _ q: PooledQuantification) -> String {
        "\(region)|\(q.usedAxis)|\(UnlistedLineChecker.proposerSettings(q))"
    }

    /// One window's map key: the channel ranges decide the map, nothing else does.
    static func key(_ w: ResolvedWindow) -> String {
        ([w.signal] + (w.background.map { [$0.left, $0.right] } ?? [])).map { "\($0.lowerBound)-\($0.upperBound)" }.joined(separator: "|")
            + (w.background.map { "|s\($0.scale)" } ?? "")
    }
}

@MainActor @Observable
final class SpectroscopyRoomController {
    let model: SpectroscopyRoomModel

    @ObservationIgnored private weak var session: SpectroscopySession?
    @ObservationIgnored private var source: (any SpectrumImageSource)?
    @ObservationIgnored private(set) var generation = 0
    @ObservationIgnored private var cache = SpectrumComputeCache()
    @ObservationIgnored private var seenTiles = Set<Int>()
    @ObservationIgnored private var regionCounts: [Int: UInt64] = [:]
    @ObservationIgnored private var hasFourDCube = false
    /// The element selection last acted on: the view's change callback also fires for the reset `bind` makes.
    @ObservationIgnored private var lastElements = ElementSelection()
    /// The lines each quantified element's map used ("Al Kα+Kβ"), keyed by Z, as of the last compute; `mapLinesParameters` records them.
    @ObservationIgnored private(set) var mapLineSummaries: [Int: String] = [:]
    /// The same for the elements whose family or lines the person chose: what a tile header names.
    @ObservationIgnored private(set) var tileLineLabels: [Int: String] = [:]
    /// The Quantify verb has run: the pooled fit is live from here on (every setting re-fits, no Apply).
    @ObservationIgnored private(set) var quantifyActive = false
    /// The computed-k and absorption data files, read once (Resources/Spectroscopy); nil when the bundle lacks them.
    private nonisolated static let tables: QuantificationTables? = QuantificationTables.bundled()
    @ObservationIgnored private(set) var lastFit: PooledQuantification?
    /// The whole-map comparison line, shown with the region's fit (A2: the check blanks no at%, so it gates nothing; `present`).
    @ObservationIgnored private var heldWholeLine: String?
    @ObservationIgnored private var pendingWaiters: [CheckedContinuation<Void, Never>] = []

    /// The window's operation hooks (spec 2 D-12), set by `AppState`: the controller holds no `AppState`. `operation` begins a
    /// cancellable operation (the infobar's bar, elapsed time and Stop) and returns its token; `finishOperation` ends it. Nil
    /// in a controller used alone (a test): the runs then go on unbracketed, as before.
    @ObservationIgnored var operation: (@MainActor (_ name: String, _ status: String) -> AnalysisCancellationToken)?
    @ObservationIgnored var finishOperation: (@MainActor (AnalysisCancellationToken) -> Void)?

    /// One running operation: its token and the task that turns the infobar's Stop (a cancelled token) into the run's own cancel.
    @MainActor final class RunningOperation {
        let token: AnalysisCancellationToken
        var watcher: Task<Void, Never>?
        var finished = false
        init(token: AnalysisCancellationToken) { self.token = token }
    }
    @ObservationIgnored private var autoIDOperation: RunningOperation?
    /// The Quantify verb is between its start and its end: an Auto ID restart waits for it (a new operation would cancel this one).
    @ObservationIgnored private var quantifying = false
    @ObservationIgnored private var quantifyStopped = false

    /// Begins the operation named, or returns nil when no hook is set. `onStop` runs on the main actor when the token is cancelled
    /// (the infobar's Stop, or another operation replacing this one); the watcher polls at 10 Hz and ends with the operation.
    private func beginOperation(_ name: String, _ status: String, onStop: @escaping @MainActor () -> Void) -> RunningOperation? {
        guard let operation else { return nil }
        let run = RunningOperation(token: operation(name, status))
        run.watcher = Task { @MainActor in
            while !Task.isCancelled {
                if run.token.isCancelled { onStop(); return }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
        return run
    }

    /// Ends `run` once: the watcher stops and the window's operation is finished (every path out calls this).
    private func endOperation(_ run: RunningOperation?) {
        guard let run, !run.finished else { return }
        run.finished = true
        run.watcher?.cancel()
        finishOperation?(run.token)
    }

    /// The verb may run: a spectrum image is bound and at least one element is switched on.
    var canQuantify: Bool { model.isLive && !model.elements.activeZ.isEmpty }
    /// Why the verb is disabled, for its hover; nil when it can run.
    var quantifyBlocker: String? { model.isLive && model.elements.activeZ.isEmpty ? "Pick elements in the periodic table first." : nil }

    init() {
        let empty = SpectrumSeries(energyStart: 0, energyStep: 0.01, data: [0, 0], background: [], model: [], overlay: nil)
        model = SpectroscopyRoomModel(series: empty)
    }

    // MARK: Binding

    /// Starts the room over on `source` (the session has just opened it). Everything shown is recomputed.
    func bind(_ source: any SpectrumImageSource, session: SpectroscopySession, hasFourDCube: Bool) {
        self.source = source
        self.session = session
        self.hasFourDCube = hasFourDCube
        lastRefresh?.cancel()   // the previous image's recompute is about a source that is gone
        cache = SpectrumComputeCache()
        quantifyActive = false
        lastFit = nil; heldWholeLine = nil
        seenTiles = []
        regionCounts = [:]
        generation += 1

        let m = model
        let meta = source.metadata
        let axis = source.energyAxis
        m.isLive = true
        m.scanPixel = meta.scanPixelSize.flatMap { size in meta.scanPixelUnit.map { (size, $0) } }
        m.hasFit = false
        m.resultsFooter = "window net counts"
        m.fitFooter = ""
        m.elements = ElementSelection()
        lastElements = m.elements
        mapLineSummaries = [:]; tileLineLabels = [:]
        m.mixed = []; m.tiles = []; m.results = []; m.markers = []
        m.elementColors = [:]; m.mapDisplays = [:]; m.haadfColormap = .gray
        m.mapMode = .netCounts; m.pins = []; m.compare = .wholeMap; m.viewportIsManual = false
        liveRegionID = nil; livePending = false
        m.fitWarnings = []; m.abundanceNote = nil; m.abundanceWithoutAbsorption = false; m.fitFailure = nil; m.isFitting = false; m.ratioLine = nil
        m.validation = nil; m.wholeMapLine = nil; m.pendingExport = nil; m.exportNote = nil
        checkTask?.cancel(); checkTask = nil
        m.unlisted = nil
        m.onAddUnlistedAsFitOnly = { [weak self] in self?.addUnlistedAsFitOnly() }
        m.onDismissUnlisted = { [weak self] in self?.dismissUnlisted() }
        m.export = ExportSettings()
        var qs = QuantifySettings(method: session.method, fileBeamKnown: meta.beamEnergyKeV != nil,
                              fileBeam: meta.beamEnergyKeV, fileBeamPhrase: meta.beamEnergyKeV == nil ? nil : meta.beamEnergySource.phrase)
        qs.syncTypedElements(session.method.elements.filter { $0.role == .quantify }.map(\.symbol))
        if qs.typedDate.isEmpty { qs.typedDate = Self.today() }
        m.quantify = qs
        m.gridWidth = source.nx; m.gridHeight = source.ny
        m.backdrop = Self.normalised(source.scanImage, count: source.nx * source.ny)
        m.tileRevision += 1
        m.regionOutline = nil
        m.series = SpectrumSeries(energyStart: axis.offset, energyStep: axis.scale,
                                  data: [Double](repeating: 0, count: axis.size), background: [], model: [], overlay: nil)
        m.viewport = SpectrumViewport(domain: m.series.domain, minimumSpan: 2 * axis.scale)
        // A Velox axis runs to 80 keV (4096 channels of 20 eV): the first view is the 20 keV an EDX spectrum is read in.
        if m.viewport.hi > 20 { m.viewport.hi = max(20, m.viewport.lo + m.viewport.minimumSpan) }
        m.image = Self.imageSettings(meta, hasFourDCube: hasFourDCube)
        m.regionSettings = RegionSettings()
        autoIDTask?.cancel(); autoIDTask = nil
        endOperation(autoIDOperation); autoIDOperation = nil
        m.resetAutoID()
        m.onAutoID = { [weak self] in self?.runAutoID() }
        m.onCancelAutoID = { [weak self] in self?.cancelAutoID() }
        m.onRegionEdit = { [weak self] shape, final in self?.editRegion(shape, final: final) }
        m.onRemoveRegion = { [weak self] id in self?.removeRegion(id: id) }
        m.onPin = { [weak self] in self?.pinRegion() }
        m.onUnpin = { [weak self] id in self?.unpin(id) }
        // A candidate picked from the spectrum's cursor menu is the periodic table's own click (the Host's change callback follows).
        m.onPickElement = { [weak self] z in self?.model.elements.click(z) }
        m.spectrumPixels = source.nx * source.ny
        m.windowBands = []
        syncRegionsFromSession()
        let first = refresh()
        // ADR 057 item 4: Auto ID runs on open, after the first sums have landed, and applies its picks. It needs the beam
        // energy, so a file without one says so (the Auto ID row).
        autoIDOnOpen?.cancel()
        autoIDOnOpen = Task { [weak self] in
            if let first { await self?.awaitNewestRefresh(from: first) }   // a click during the open's sums cancels them: wait for the ones that stand
            guard !Task.isCancelled else { return }
            self?.runAutoID()
        }
    }
    /// Internal read so a test about something else can cancel the open's run before it starts.
    @ObservationIgnored private(set) var autoIDOnOpen: Task<Void, Never>?
    @ObservationIgnored private var autoIDRestart = false

    func unbind() {
        generation += 1
        autoIDOnOpen?.cancel(); autoIDOnOpen = nil
        cancelAutoID()
        checkTask?.cancel(); checkTask = nil
        lastRefresh?.cancel()
        source = nil
        session = nil
        model.isLive = false
    }

    /// The window gained or lost its 4D cube after the image was opened: the Source row follows.
    func setFourDCube(_ present: Bool) {
        guard present != hasFourDCube, let source else { hasFourDCube = present; return }
        hasFourDCube = present
        let readouts = Self.imageSettings(source.metadata, hasFourDCube: present)
        model.image.sourceWarning = readouts.sourceWarning
        model.image.sourceNote = readouts.sourceNote
    }

    // MARK: Edits

    /// The display kernel changed (Elements › Smooth): every tile's picture is rebuilt from its raw counts with the new kernel
    /// (filter first, clamp after), so a change back to none returns the first picture exactly. Nothing is recomputed: no sums, no
    /// spectra, no fit, and the raw counts, the backdrop and the ColorMix's membership are untouched. A fixture tile has no counts and stays.
    func smoothingChanged() {
        let m = model
        guard !m.tiles.isEmpty else { return }
        var tiles = m.tiles   // one assignment: the views are told once, not twice per tile
        for i in tiles.indices where !tiles[i].counts.isEmpty {
            let t = tiles[i]
            let shown = Self.display(of: t.counts, width: t.width, height: t.height, smoothing: m.smoothing)
            tiles[i].values = shown.values
            tiles[i].scale = shown.scale
        }
        m.tiles = tiles
        m.tileRevision += 1
    }

    /// The element roles or lines changed in the periodic table.
    func elementsChanged() {
        guard model.elements != lastElements else { return }
        lastElements = model.elements
        mirrorElementsToSession()
        model.quantify.syncTypedElements(model.elements.quantified.map { PeriodicLayout.symbol($0) })
        refresh()
    }

    // MARK: Auto ID

    @ObservationIgnored private(set) var autoIDTask: Task<Void, Never>?

    /// Auto ID: the element proposer on the selected region's spectrum with the listed elements as the current set. 0.4 to
    /// 20 s depending on the channel count, so it runs detached and lands only if it was not cancelled, superseded or
    /// overtaken by an edit (`refresh` cancels it). Its picks are applied at once (ADR 057 item 4).
    func runAutoID() {
        guard let source, let session, let region = session.regions.first(where: { $0.id == session.selectedRegionID }),
              !model.autoID.running, !quantifying else { return }
        let token = model.beginAutoID()
        guard let beam = session.method.beamEnergyKeV ?? source.metadata.beamEnergyKeV, beam > 0 else {
            model.failAutoID(token: token, message: SpectroscopyRoomModel.autoIDNeedsBeamNote)
            return
        }
        // D-12: the run is an operation (infobar bar, elapsed time, Stop); every way out ends it (`endOperation`).
        let run = beginOperation("Auto ID", "Identifying elements…") { [weak self] in self?.cancelAutoID() }
        autoIDOperation = run
        let current = model.elements.activeZ.map { PeriodicLayout.symbol($0) }
        let computedK = model.quantify.kSource == .computed   // a computed k covers K lines only (`AutoIDPresentation.outcome`)
        let mask = session.mask(of: region)
        let regionID = region.id, name = region.name
        let cache = cache
        autoIDTask = Task.detached(priority: .userInitiated) {
            let spectrum: [UInt64]
            if let s = cache.spectrum(regionID) { spectrum = s } else {
                spectrum = source.sum(mask: mask)
                cache.setSpectrum(spectrum, regionID)
            }
            var outcome: AutoIDOutcome?
            var failure: String?
            do {
                // DEVIATION: the file's axis and the default continuum (empirical, Al K step), not the Quantify inspector's
                // choices: Auto ID screens, it does not quantify.
                let settings = FitSettings.standard(elements: current, axis: source.energyAxis,
                                                    resolutionMnKaEV: ElementWindows.defaultResolutionMnKaEV, beamEnergy: beam)
                let result = try ElementProposer().propose(counts: spectrum.map { Double($0) }, axis: source.energyAxis, settings: settings)
                // WP4 (2026-10-07): the shipped rule set (R1 hygiene only; R2 and R3 refuted as registered) re-selects the proposer's
                // candidates; the raw result stays beside the picks and every withheld pick is named in the notes.
                let ruled = ProposalRules.shipped.apply(result, resolutionMnKaEV: settings.resolutionMnKaEV)
                outcome = AutoIDPresentation.outcome(result, region: name, beside: AutoIDPresentation.besideCheck(settings: settings, axis: source.energyAxis),
                                                     computedK: computedK, rules: ruled)
            } catch ProposerError.cancelled { return   // cancelled or overtaken: a silent discard, no note (whoever cancelled it ended the operation)
            } catch { failure = "Auto ID could not fit this spectrum: \((error as? LocalizedError)?.errorDescription ?? "\(error)")" }
            if Task.isCancelled { return }
            let finalOutcome = outcome, finalFailure = failure   // immutable copies for the main-actor closure (no mutable capture)
            await MainActor.run { [weak self] in
                guard let self else { return }
                if self.autoIDOperation === run { self.autoIDOperation = nil }
                self.endOperation(run)   // this run's own operation, never a newer run's
                if let outcome = finalOutcome {
                    // D-3: the suggestions are applied (picked, mapped at once); with none to apply no listed pick moved, so the
                    // fit and its in-flight unlisted-line check are left alone (the view's change callback must not refresh for the suggestions).
                    if self.model.finishAutoID(token: token, outcome: outcome) {
                        if self.applyAutoIDPicks() { self.model.markListedAfterPicks(); self.elementsChanged() } else { self.lastElements = self.model.elements }
                    }
                } else { self.model.failAutoID(token: token, message: finalFailure ?? "Auto ID failed.") }
            }
        }
    }

    /// D-3: Auto ID applies its picks. Every suggestion the run left standing becomes a pick through the table's own click (the
    /// proposed role: Quantify, or Fit only for a FIB question). `finishAutoID` has already dropped the suggestions of an
    /// element the person decided (`ElementSelection.manual`, which an Off by hand is part of), and that is checked again here:
    /// a person's own Off is never re-added, by this run or the next. True when a pick was made.
    @discardableResult
    func applyAutoIDPicks() -> Bool {
        var applied = false
        for s in model.elements.suggestions where !model.elements.manual.contains(s.z) {
            model.elements.click(s.z)
            applied = true
        }
        return applied
    }

    /// The fit range's end for the opening view's ceiling: the Quantify default (min(axis end, beam, 20 keV)) or the typed one.
    private func fitEnd(for source: any SpectrumImageSource) -> Double? {
        guard let beam = session?.method.beamEnergyKeV ?? source.metadata.beamEnergyKeV, beam > 0, let method = session?.method else { return nil }
        let axis = source.energyAxis
        let end = FitRangeChoice(method: method, fileAxis: axis, usedAxis: axis, beamEnergy: beam).toKeV
        model.fitEndKeV = end
        return end
    }

    /// The opening view's fallback end (UX #5): where 99.5 % of the shown spectrum's counts lie.
    private static func countsEnergy(_ s: SpectrumSeries) -> Double? {
        SpectrumAutoZoom.countsEnergy(data: s.data, energyStart: s.energyStart, energyStep: s.energyStep)
    }

    func cancelAutoID() {
        autoIDTask?.cancel()
        autoIDTask = nil
        endOperation(autoIDOperation); autoIDOperation = nil
        model.cancelAutoID()
    }

    // MARK: Quantify

    /// The settings last written into the session's method: a change that leaves them equal (the results writing the fit
    /// quality back into the same struct, the typed table following the elements) must not re-fit.
    @ObservationIgnored private var lastApplied: QuantificationMethod?

    /// Writes the inspector's controls into the session's method; true when the method changed.
    @discardableResult
    private func applySettingsToSession() -> Bool {
        guard let session else { return false }
        var m = session.method
        model.quantify.apply(to: &m)
        var previous = lastApplied
        previous?.elements = m.elements
        if m == previous { return false }
        lastApplied = m
        session.method = m
        return true
    }

    /// The Quantify inspector changed. After the verb has run the pooled fit follows live (no Apply).
    func quantifySettingsChanged() {
        let changed = applySettingsToSession()
        // A beam energy typed under Quantification answers Auto ID's "needs the beam energy" note. It does not re-run Auto ID
        // (a run starts on open, on a pick or region change, and on the button); the button is enabled and the note is gone.
        if changed, let beam = session?.method.beamEnergyKeV ?? source?.metadata.beamEnergyKeV, beam > 0 { model.clearAutoIDBeamNote() }
        guard changed, quantifyActive else { return }
        refresh()
    }

    /// The Quantify verb: fits the selected region's pooled spectrum with the session's method and, from now on, keeps it
    /// live. Returns true when a fit landed; the caller records the replay step (`recordQuantification`) then. The
    /// session's method takes the run's own (a computed k's source string filled in), so the record names it.
    func quantify() async -> Bool {
        guard canQuantify, let session else { return false }
        // D-12: the verb is an operation (infobar bar, elapsed time, Stop). Stop puts the room back as it was and records nothing.
        let wasActive = quantifyActive
        quantifying = true; quantifyStopped = false
        let run = beginOperation("Quantify", "Fitting the spectrum…") { [weak self] in self?.stopQuantify(restoring: wasActive) }
        defer {
            endOperation(run)
            quantifying = false
            if autoIDRestart { autoIDRestart = false; runAutoID() }   // held back while the verb ran (`apply`)
        }
        quantifyActive = true
        model.quantify.syncTypedElements(model.elements.quantified.map { PeriodicLayout.symbol($0) })
        applySettingsToSession()
        guard let first = refresh() else { return false }
        await awaitNewestRefresh(from: first)
        guard !quantifyStopped, !model.isFitting, model.fitFailure == nil, let fit = lastFit else { return false }
        session.method = fit.method
        lastApplied = nil   // the filled method differs from the controls' by the k source only; the next edit re-applies
        return true
    }

    /// Waits for the NEWEST recompute: Auto ID landing (or an edit) while one runs starts another, which cancels this one (it returns
    /// early, landing nothing) and replaces its answer; a caller must report the state that stands, not the one that was overtaken.
    private func awaitNewestRefresh(from first: Task<Void, Never>) async {
        var task = first
        while true {
            await task.value
            guard let latest = lastRefresh, latest != task else { break }
            task = latest
        }
    }

    /// The infobar's Stop during the verb: the fit that is running is superseded (a refresh bumps `generation`, so its answer
    /// is dropped) and the room returns to what it showed before the verb; no step is recorded (`quantify` answers false).
    private func stopQuantify(restoring wasActive: Bool) {
        guard quantifying, !quantifyStopped else { return }
        quantifyStopped = true
        quantifyActive = wasActive
        if !wasActive { lastFit = nil }
        refresh()
    }

    private static func today() -> String {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withFullDate]
        return f.string(from: Date())
    }

    /// The region picker changed `model.selectedRegion`.
    func regionPicked() {
        guard let session, let id = model.selectedRegion, id != session.selectedRegionID,
              session.regions.contains(where: { $0.id == id }) else { return }
        session.selectedRegionID = id
        syncRegionsFromSession()
        refresh()
    }

    /// A region chosen anywhere (the sidebar's rows, the picker): the session, the model and the numbers all follow.
    func selectRegion(id: Int) {
        guard let session, session.regions.contains(where: { $0.id == id }) else { return }
        session.selectedRegionID = id
        syncRegionsFromSession()
        refresh()
    }

    // MARK: Live region (ADR 056)

    /// The one region the person is working with: drawn on a map, then moved and resized in place. Its id is fixed from the
    /// first edit; Pin freezes copies of it, so the live one is never a list.
    @ObservationIgnored private(set) var liveRegionID: Int?
    @ObservationIgnored private var liveBusy = false
    @ObservationIgnored private var livePending = false
    /// Measurement for the report and the tests: spectra summed while the pointer was down, and the time they took.
    @ObservationIgnored private(set) var liveSums = 0
    @ObservationIgnored private(set) var liveSumSeconds = 0.0

    /// A shape drawn, moved or resized on a map. While the pointer is down (`final` false) only the spectrum follows: one
    /// sum at a time, the newest shape waiting, so a drag over a 926 x 215 x 4096 store never queues a backlog. At the end
    /// (`final`) the whole selection is recomputed: the net counts, the maps' region numbers and, after Quantify, the fit.
    func editRegion(_ shape: SpectrumRegionShape, final: Bool) {
        guard let session, source != nil else { return }
        if let id = liveRegionID, session.regions.contains(where: { $0.id == id }) {
            guard session.replaceShape(ofRegion: id, with: shape) else { return }
        } else {
            guard let r = session.addDrawnRegion(shape) else { return }
            liveRegionID = r.id
        }
        session.selectedRegionID = liveRegionID
        syncRegionsFromSession()
        if final {
            if let id = liveRegionID { cache.forget(region: id); regionCounts[id] = nil }
            refresh()
        } else { scheduleLiveSum() }
    }

    private func scheduleLiveSum() {
        guard let source, let session, let id = session.selectedRegionID,
              let region = session.regions.first(where: { $0.id == id }) else { return }
        if liveBusy { livePending = true; return }
        liveBusy = true
        let mask = session.mask(of: region)
        let gen = generation
        let started = Date()
        Task.detached(priority: .userInitiated) {
            let sum = source.sum(mask: mask)
            await MainActor.run { [weak self] in self?.landLiveSum(sum, region: id, generation: gen, started: started) }
        }
    }

    private func landLiveSum(_ sum: [UInt64], region id: Int, generation gen: Int, started: Date) {
        liveBusy = false
        liveSums += 1; liveSumSeconds += Date().timeIntervalSince(started)
        // A newer full recompute (the drag ended, an element changed) has bumped `generation`: its answer replaces this one.
        if gen == generation, let source, let session, session.selectedRegionID == id,
           let region = session.regions.first(where: { $0.id == id }) {
            let m = model
            let total = sum.reduce(UInt64(0), &+)
            // The fit's curves belong to the old shape: they return with the final recompute.
            var s = SpectrumSeries(energyStart: source.energyAxis.offset, energyStep: source.energyAxis.scale,
                                   data: sum.map { Double($0) }, background: [], model: [], overlay: nil)
            s.overlay = overlay(for: total, whole: cache.spectrum(0))
            m.series = s
            m.spectrumPixels = region.pixelCount
            m.spectrumTitle = "Spectrum · \(region.name)"
            m.spectrumSubtitle = "\(Self.counts(total)) counts · \(ResultFormat.counts(Double(region.pixelCount))) px · live"
            updateSpectrumStems(regionName: region.name)
        }
        if livePending { livePending = false; scheduleLiveSum() }
    }

    /// The comparison overlay: the whole map's spectrum scaled so its total equals the region's (a shape comparison).
    private func overlay(for total: UInt64, whole: [UInt64]?) -> [Double]? {
        guard model.compare == .wholeMap, let whole, model.selectedRegion != 0 else { return nil }
        let w = whole.reduce(UInt64(0), &+)
        guard w > 0, total > 0 else { return nil }
        let k = Double(total) / Double(w)
        return whole.map { Double($0) * k }
    }

    func removeRegion(id: Int) {
        guard let session else { return }
        session.removeRegion(id: id)
        cache.forget(region: id)
        regionCounts[id] = nil
        if liveRegionID == id { liveRegionID = nil }
        syncRegionsFromSession()
        refresh()
    }

    // MARK: Pins

    /// Pin: freezes a copy of the live region (its spectrum, scaled in the overlay to the live region's counts), up to three.
    /// The live rectangle moves on; a pin stays until it is unpinned.
    func pinRegion() {
        let m = model
        guard m.pins.count < SpectroscopyRoomModel.maximumPins, let session,
              let region = session.regions.first(where: { $0.id == session.selectedRegionID }),
              let spectrum = cache.spectrum(region.id) else { return }
        let used = Set(m.pins.map(\.id))
        let id = (0..<SpectroscopyRoomModel.maximumPins).first { !used.contains($0) } ?? 0
        m.pins.append(PinnedRegion(id: id, label: "Pin \(id + 1)", tint: PinnedRegion.tints[id % PinnedRegion.tints.count],
                                   shape: region.shape, pixels: region.pixelCount, spectrum: spectrum.map { Double($0) }))
    }

    func unpin(_ id: Int) { model.pins.removeAll { $0.id == id } }

    /// The listed elements, then the ones a person switched Off (role `.off`, manual): the method records them, so the
    /// replay step says which elements the unlisted-line check was told to leave out.
    private func mirrorElementsToSession() {
        guard let session else { return }
        let listed = model.elements.activeZ.map { z in
            let role = model.elements.role(z)
            return SpectroscopyElement(symbol: PeriodicLayout.symbol(z),
                                       role: role == .quantify ? .quantify : .fitOnly,
                                       isManual: model.elements.manual.contains(z))
        }
        let off = model.elements.manual.filter { model.elements.role($0) == .off }.sorted()
            .map { SpectroscopyElement(symbol: PeriodicLayout.symbol($0), role: .off, isManual: true) }
        session.elements = listed + off
    }

    // MARK: Unlisted lines (WP3b F1)

    @ObservationIgnored private(set) var checkTask: Task<Void, Never>?

    /// The named elements become Fit only (the periodic table's own role change, so a person's pick is recorded as theirs).
    func addUnlistedAsFitOnly() {
        for z in model.unlisted?.candidates ?? [] { model.elements.set(z, .fitOnly) }
        elementsChanged()
    }

    /// The named elements are switched Off by the person: the check leaves them out from now on (until listed again).
    func dismissUnlisted() {
        for z in model.unlisted?.candidates ?? [] { model.elements.set(z, .off) }
        elementsChanged()
    }

    /// Runs the check for a fit that just landed: the proposer (5-20 s at 4096 channels, cached per `unlistedKey`) and one
    /// refit, detached and cancellable. The table says "checking…" meanwhile; the verb has already returned.
    /// WP3c: the same task then runs the range-sensitivity refit (`FitRangeSensitivityCheck`, one fit to the axis end, only
    /// when the axis runs past the default range) and the two land together, so a fit gets one task, one generation guard,
    /// one proposer run, and the footer changes once.
    /// DEVIATION (simplicity): Auto ID's run is not reused. It proposes on the file's axis with the default continuum and
    /// width, the check on the fit's refined axis and the inspector's continuum, so their inputs are rarely identical.
    private func startUnlistedCheck(_ fit: PooledQuantification, input: PooledQuantificationInput, region: Int) {
        checkTask?.cancel()
        model.unlisted = .checkingNote
        let gen = generation
        let cache = cache
        let key = SpectrumComputeCache.unlistedKey(region: region, fit)
        checkTask = Task.detached(priority: .utility) {
            var check: UnlistedLineCheck
            do {
                let proposal: ProposalResult
                if let p = cache.proposal(key) { proposal = p } else {
                    proposal = try UnlistedLineChecker.propose(counts: input.counts.map { Double($0) }, quantification: fit)
                    cache.setProposal(proposal, key)
                }
                if Task.isCancelled { return }
                check = UnlistedLineChecker.check(proposal: proposal, input: input, quantification: fit)
            } catch ProposerError.cancelled { return   // superseded by a newer fit: a silent discard
            } catch { check = .failed((error as? LocalizedError)?.errorDescription ?? "\(error)") }
            if Task.isCancelled { return }
            var shown = UnlistedLineChecker.withholding(fit, check)
            if let s = FitRangeSensitivityCheck.run(input: input, quantification: fit) {
                if Task.isCancelled { return }
                shown = FitRangeSensitivityCheck.attaching(shown, s)
            }
            let finalShown = shown   // immutable copy for the main-actor closure (no mutable capture)
            await MainActor.run { [weak self] in self?.landCheck(finalShown, region: region, generation: gen) }
        }
    }

    /// A finished check lands only on the fit it was run for: any newer refresh (a new fit, a setting, an element) has
    /// bumped `generation`, and its answer is about the old fit.
    func landCheck(_ shown: PooledQuantification, region: Int, generation gen: Int) {
        guard gen == generation, quantifyActive, let check = shown.unlistedCheck else { return }
        present(shown, region: region)
        model.unlisted = QuantifyPresentation.unlistedNote(check)
    }

    private func syncRegionsFromSession() {
        guard let session else { return }
        model.regions = session.regions.map { r in
            RegionSummary(id: r.id, name: r.name, pixels: r.pixelCount,
                          counts: Double(regionCounts[r.id] ?? 0) / 1e6, tint: .gray, isDrawn: r.kind == .drawn)
        }
        model.selectedRegion = session.selectedRegionID
        model.regionOutline = session.regions.first { $0.id == session.selectedRegionID }?.shape
    }

    // MARK: Compute

    struct Request: Sendable {
        let source: any SpectrumImageSource
        let region: Int
        let mask: PixelMask?
        let picks: [ElementWindows.Pick]
        let integrated: Bool
        let beam: Double?
        /// Set once the Quantify verb has run: the pooled fit of this region with this method.
        let quantify: QuantifyRequest?
    }

    struct QuantifyRequest: Sendable {
        let method: QuantificationMethod
        let metadata: SpectrumImageMetadata
        let regionName: String
        let pixelCount: Int
    }

    struct Output: Sendable {
        let region: Int
        let spectrum: [UInt64]
        /// The whole map's spectrum (the comparison overlay), nil until it has been summed once.
        let whole: [UInt64]?
        let windows: [LineWindow]
        let counts: [LineNetCount?]
        let maps: [[Double]?]
        let fit: PooledQuantification?
        let fitInput: PooledQuantificationInput?
        let fitFailure: String?
        /// The same method on the whole map (for a region's comparison line); nil for the whole map or without a fit.
        let wholeLine: String?
    }

    /// Recomputes everything the current selection shows. Cheap when nothing it needs is new; the pooled fit (after the
    /// Quantify verb) is the one pass that always runs, its axis refinement cached per region, elements and background.
    @discardableResult
    func refresh() -> Task<Void, Never>? {
        guard let source, let session, let region = session.regions.first(where: { $0.id == session.selectedRegionID }) else { return nil }
        if model.autoID.running {   // the elements or the region changed under it: its answer is about the old ones
            cancelAutoID()
            autoIDRestart = true   // the open's run is not lost to a click made while it ran: it starts again below
        }
        checkTask?.cancel(); checkTask = nil         // about the previous fit; the next fit starts its own
        generation += 1
        let gen = generation
        let picks = Self.picks(for: model.elements)
        var quantify: QuantifyRequest?
        if quantifyActive {
            quantify = QuantifyRequest(method: session.method, metadata: source.metadata, regionName: region.name, pixelCount: region.pixelCount)
            model.isFitting = true
        }
        let request = Request(source: source, region: region.id, mask: session.mask(of: region), picks: picks,
                              integrated: model.mapMode == .integrated,
                              beam: source.metadata.beamEnergyKeV, quantify: quantify)
        let cache = cache
        // The previous recompute is about a selection that no longer stands (its answer would be dropped by the generation check):
        // cancel it so its remaining stages do not run. A cancelled task returns early and lands nothing.
        lastRefresh?.cancel()
        let task = Task.detached(priority: .userInitiated) {
            guard let out = Self.compute(request, cache: cache), !Task.isCancelled else { return }
            await MainActor.run { [weak self] in self?.apply(out, generation: gen) }
        }
        lastRefresh = task
        return task
    }
    /// The newest recompute, so a caller (the verb, a test) can wait for it.
    @ObservationIgnored private(set) var lastRefresh: Task<Void, Never>?

    /// Only windows whose map is not cached are computed.
    private nonisolated static func mapsFor(_ ws: [LineWindow], source: any SpectrumImageSource, integrated: Bool, cache: SpectrumComputeCache) -> [[Double]?] {
        let missing = ws.filter { w in w.window.map { cache.map(SpectrumComputeCache.key($0, integrated: integrated)) == nil } ?? false }
        if !missing.isEmpty {
            let fresh = integrated ? ElementWindows.integratedMaps(image: source, windows: missing)
                                   : ElementWindows.maps(image: source, windows: missing)
            for (w, m) in zip(missing, fresh) { if let w = w.window, let m { cache.setMap(m, SpectrumComputeCache.key(w, integrated: integrated)) } }
        }
        return ws.map { w in w.window.flatMap { cache.map(SpectrumComputeCache.key($0, integrated: integrated)) } }
    }

    /// The staged work of one recompute. `cancelled` is polled between the stages (sum, maps, the fit, the comparison fit); a
    /// cancelled recompute returns nil and lands nothing. A stage that finished has cached its whole result, a stage that did
    /// not has cached nothing, so the next recompute reuses exactly what is complete.
    nonisolated static func compute(_ r: Request, cache: SpectrumComputeCache, cancelled: @Sendable () -> Bool = { Task.isCancelled }) -> Output? {
        if cancelled() { return nil }
        let spectrum: [UInt64]
        if let s = cache.spectrum(r.region) { spectrum = s } else {
            spectrum = r.source.sum(mask: r.mask)
            cache.setSpectrum(spectrum, r.region)
        }
        // The comparison overlay's spectrum: the whole map, summed once (region 0 is the whole map, `SpectroscopySession.open`).
        var whole: [UInt64]?
        if r.region == 0 { whole = spectrum } else if let w = cache.spectrum(0) { whole = w } else {
            let w = r.source.sum(mask: nil)
            cache.setSpectrum(w, 0)
            whole = w
        }
        if cancelled() { return nil }
        let windows = ElementWindows.build(picks: r.picks, axis: r.source.energyAxis, beamEnergyKeV: r.beam)
        let counts = ElementWindows.netCounts(spectrum: spectrum, windows: windows)
        func mapsFor(_ ws: [LineWindow]) -> [[Double]?] { Self.mapsFor(ws, source: r.source, integrated: r.integrated, cache: cache) }
        let maps = mapsFor(windows)
        if cancelled() { return nil }
        var fit: PooledQuantification?
        var fitInput: PooledQuantificationInput?
        var failure: String?
        var wholeLine: String?
        if let q = r.quantify {
            // The refinement does not depend on the estimator, k or absorption: it is keyed by what it does depend on.
            func refinementKey(_ region: Int) -> String {
                let on = q.method.elements.filter { $0.role != .off }.map(\.symbol).sorted().joined(separator: ",")
                return "\(region)|\(on)|\(q.method.background.rawValue)|\(q.method.polynomialOrder ?? 6)|\(q.method.beamEnergyKeV ?? r.beam ?? 0)|\(q.method.fitToKeV.map { "\($0)" } ?? "default")"
            }
            let key = refinementKey(r.region)
            let input = PooledQuantificationInput(counts: spectrum, axis: r.source.energyAxis, method: q.method, metadata: q.metadata,
                                                  regionName: q.regionName, pixelCount: q.pixelCount, refinement: cache.refinement(key))
            do {
                let res = try PooledQuantifier.run(input, tables: Self.tables)
                if let rr = res.refinement, input.refinement == nil { cache.setRefinement(rr, key) }
                fit = res
                fitInput = input
                // The comparison line: the same method on the whole map (a failure there only drops the line).
                if r.region != 0, let w = whole, !cancelled() {
                    let wkey = refinementKey(0)
                    let wInput = PooledQuantificationInput(counts: w, axis: r.source.energyAxis, method: q.method, metadata: q.metadata,
                                                           regionName: "Whole map", pixelCount: r.source.nx * r.source.ny, refinement: cache.refinement(wkey))
                    if let wres = try? PooledQuantifier.run(wInput, tables: Self.tables) {
                        if let rr = wres.refinement, wInput.refinement == nil { cache.setRefinement(rr, wkey) }
                        wholeLine = QuantifyPresentation.wholeMapLine(wres)
                    }
                }
            } catch { failure = (error as? LocalizedError)?.errorDescription ?? "\(error)" }
        }
        if cancelled() { return nil }
        return Output(region: r.region, spectrum: spectrum, whole: whole, windows: windows, counts: counts, maps: maps,
                      fit: fit, fitInput: fitInput, fitFailure: failure, wholeLine: wholeLine)
    }

    private func apply(_ out: Output, generation gen: Int) {
        guard gen == generation, let source, let session else { return }
        defer { if autoIDRestart && !quantifying { autoIDRestart = false; runAutoID() } }   // not while the verb runs: a new operation would cancel its own
        let m = model
        let axis = source.energyAxis
        let total = out.spectrum.reduce(UInt64(0), &+)
        regionCounts[out.region] = total
        syncRegionsFromSession()

        // Spectrum of the selected region.
        m.series = SpectrumSeries(energyStart: axis.offset, energyStep: axis.scale,
                                  data: out.spectrum.map { Double($0) }, background: [], model: [], overlay: nil)
        if let fit = out.fit { m.series = QuantifyPresentation.series(data: out.spectrum, axis: axis, fit) }
        m.series.overlay = overlay(for: total, whole: out.whole)
        let region = session.regions.first { $0.id == out.region }
        let name = region?.name ?? "Whole map"
        let pixels = region?.pixelCount ?? source.nx * source.ny
        m.spectrumPixels = pixels
        m.windowBands = Self.windowBands(for: out.windows, axis: axis)
        m.spectrumTitle = "Spectrum · \(name)"
        m.spectrumSubtitle = "\(Self.counts(total)) counts · \(ResultFormat.counts(Double(pixels))) px"
        m.resultsTitle = "Results · \(name)"

        // Markers: the chosen family's lines of every active element.
        m.markers = Self.markers(for: out.windows, axis: axis, beam: source.metadata.beamEnergyKeV,
                                 quantified: Set(m.elements.quantified.map { PeriodicLayout.symbol($0) }),
                                 picked: Set(m.elements.activeZ.flatMap { m.elements.lines[$0] ?? [] }))

        // Rows, tiles: the quantified elements only (fit-only ones shape the windows, not the table). An element with two
        // checked lines has two windows: its row is the first one that has counts (named in its sigma terms), its tile the SUM of
        // its lines' maps, each net of its own background.
        var rows: [ResultRow] = [], tiles: [MapTile] = []
        let quantified = Set(m.elements.quantified.map { PeriodicLayout.symbol($0) })
        var done = Set<String>()
        for w in out.windows where quantified.contains(w.element) && done.insert(w.element).inserted {
            guard let z = PeriodicLayout.z(of: w.element) else { continue }
            let group = out.windows.indices.filter { out.windows[$0].element == w.element }
            let i = group.first { out.counts[$0] != nil } ?? group[0]
            if let c = out.counts[i] {
                let bg = c.background.map { ", B = \(Self.counts($0)), s = \(String(format: "%.3f", c.scale ?? 0))" } ?? " (no background window)"
                rows.append(ResultRow(
                    z: z, netCounts: c.net, netSigma: c.sigma, kFreeRatio: 0, kFreeSigma: nil, atPercent: 0, atSigma: 0,
                    wtPercent: 0, wtSigma: 0,
                    sigmaTerms: "σ² = G + s²B with G = \(Self.counts(c.signal))\(bg) · \(ElementWindows.label(ofLineID: c.id))",
                    conflictNote: ElementWindows.conflictNote(w.conflicts), failure: c.notAMeasurementText))
            } else {
                rows.append(ResultRow(z: z, netCounts: 0, netSigma: 0, kFreeRatio: 0, kFreeSigma: nil, atPercent: 0, atSigma: 0,
                                      wtPercent: 0, wtSigma: 0, sigmaTerms: "", failure: w.failure))
            }
            if let map = Self.summed(group.compactMap { out.maps[$0] }) {
                // Row 1a: the kernel is applied to the SIGNED map and the clamp comes after; the tile keeps the raw counts.
                let shown = Self.display(of: map, width: source.nx, height: source.ny, smoothing: m.smoothing)
                tiles.append(MapTile(z: z, width: source.nx, height: source.ny, values: shown.values, counts: map,
                                     notMeasuredWhy: group.compactMap { out.counts[$0]?.notAMeasurementText }.first, scale: shown.scale))
                // R10: a picked element goes into the mix (a picture); its not-a-measurement note stays on the tile and the row. The user may untick.
                if seenTiles.insert(z).inserted { m.mixed.insert(z) }
            }
        }
        let lines = Self.mapLines(windows: out.windows, quantified: quantified)
        mapLineSummaries = lines
        tileLineLabels = lines.filter { m.elements.hasChosenLines($0.key) }
        for i in tiles.indices { tiles[i].lineLabel = tileLineLabels[tiles[i].z] }   // "Al Kα+Kβ" on the tile only when the person chose lines
        m.results = rows
        applyFit(out, source: source)
        m.tiles = tiles
        m.tileRevision += 1
        // A tile that is gone loses its tick and its "seen" mark, so it is ticked again when it comes back.
        let present = Set(tiles.map(\.z))
        seenTiles.formIntersection(present)
        m.mixed.formIntersection(present)
        if !m.viewportIsManual {
            let r = SpectrumAutoZoom.range(markers: m.markers, domain: m.series.domain, minimumSpan: m.viewport.minimumSpan, countsEnergy: Self.countsEnergy(m.series), fitEnd: fitEnd(for: source))
            m.viewport.lo = r.lowerBound; m.viewport.hi = r.upperBound
        }
        updateSpectrumStems(regionName: name)   // after `applyFit`, which rebuilds `export`
    }

    /// The Export section's "Spectrum CSV…" (spec 2 D-14) is there from the first spectrum: this names it (file and region) and the
    /// files' default stems, which `ExportSettings()` resets. The CSV text is built when it is exported, not here: this runs on
    /// every live-drag tick, so it assigns only what changed (an unchanged value would still notify the views).
    private func updateSpectrumStems(regionName: String) {
        guard let source else { return }
        let label = SpectrumLabel(imageName: source.metadata.fileName, regionName: regionName)
        if model.export.spectrumOf != label { model.export.spectrumOf = label }
        let stem = SpectroscopyExport.fileStem(imageName: source.metadata.fileName, regionName: regionName)
        if model.export.fileStem != stem { model.export.fileStem = stem }
        let maps = MapsExport.stem(imageName: source.metadata.fileName)
        if model.export.mapsStem != maps { model.export.mapsStem = maps }
    }

    /// The pooled fit's numbers into the model: the table's rows, the footers, the warnings, the plot, the readouts.
    private func applyFit(_ out: Output, source: any SpectrumImageSource) {
        let m = model
        m.isFitting = false
        guard quantifyActive else { return }
        m.fitFailure = out.fitFailure
        guard let fit = out.fit else {
            // No fit (no element, no beam energy, an empty region): the window sums stay, the reason is shown.
            m.wholeMapLine = nil; heldWholeLine = nil
            m.export = ExportSettings(); m.hasFit = false; m.validation = nil; m.ratioLine = nil; m.fitWarnings = []; m.abundanceNote = nil; m.abundanceWithoutAbsorption = false
            m.unlisted = nil
            lastFit = nil
            return
        }
        lastFit = fit
        heldWholeLine = out.wholeLine   // shown by `present` under the ratio line's gate
        if let input = out.fitInput {
            present(UnlistedLineChecker.holding(fit), region: out.region)
            startUnlistedCheck(fit, input: input, region: out.region)
        } else {
            present(fit, region: out.region)
        }
    }

    /// A fit's numbers into the model (the reported fit, then again with the unlisted-line check attached).
    private func present(_ fit: PooledQuantification, region: Int) {
        guard let source else { return }
        let m = model
        m.hasFit = true
        m.results = QuantifyPresentation.rows(fit)
        m.ratioLine = QuantifyPresentation.ratioLine(fit)
        // The whole-map at% is a number like the region's own: not shown while the check runs, not after it withholds.
        m.wholeMapLine = heldWholeLine
        m.validation = fit.hasAbundance ? PooledQuantification.abundanceValidation : nil
        m.fitWarnings = QuantifyPresentation.warnings(fit.warnings)
        if case .applied = fit.absorption { m.abundanceWithoutAbsorption = false } else { m.abundanceWithoutAbsorption = fit.hasAbundance }
        // While the check runs its own line says "checking…"; a second note would repeat it.
        m.abundanceNote = fit.abundanceRefusal.map { "at% not computed: \($0)" } ?? fit.abundanceCaveat.map { "at% caveat: \($0)" }   // A2: at% is never blanked by the check; the caveat rides with it
        m.resultsFooter = fit.footerLines.joined(separator: "\n")
        m.fitFooter = QuantifyPresentation.plotFooter(fit)
        let regionName = session?.regions.first { $0.id == region }?.name ?? "Whole map"
        m.export = ExportSettings(csv: SpectroscopyExport.csv(fit, regionName: regionName), methodJSON: SpectroscopyExport.methodJSON(fit.method),
                                  elements: SpectroscopyExport.elementsLine(fit),
                                  fileStem: SpectroscopyExport.fileStem(imageName: source.metadata.fileName, regionName: regionName))
        updateSpectrumStems(regionName: regionName)
        m.quantify.quality = fit.qualityText
        switch fit.absorption {
        case .off: m.quantify.absorptionNote = nil
        case .applied(let s): m.quantify.absorptionNote = s
        case .refused(let why): m.quantify.absorptionNote = "not applied: \(why)"
        }
        m.image.energyAxisRefined = QuantifyPresentation.axisRefinement(fit)
    }

    // MARK: Pure helpers

    private static func counts(_ v: UInt64) -> String {
        v >= 1_000_000 ? String(format: "%.2f M", Double(v) / 1e6) : ResultFormat.counts(Double(v))
    }

    /// Greys for the scan image: 0...1 between its own min and max; empty when absent or flat.
    private static func normalised(_ v: [Float]?, count: Int) -> [Float] {
        guard let v, v.count == count, let lo = v.min(), let hi = v.max(), hi > lo else { return [] }
        return v.map { ($0 - lo) / (hi - lo) }
    }

    /// What a 1.0 stands for in `normalised(_:)`'s picture: the map's maximum, in the map's own unit (net or integrated counts).
    /// 0 for a map with no positive pixel, which `normalised` draws as all zeros. The histogram shows real values with it.
    static func scale(of map: [Double]) -> Float { Float(max(map.max() ?? 0, 0)) }

    /// A net-count map as 0...1 (negative net counts are drawn as 0): presentation scaling, not a result.
    private static func normalised(_ map: [Double]) -> [Float] {
        let hi = map.max() ?? 0
        guard hi > 0 else { return [Float](repeating: 0, count: map.count) }
        return map.map { Float(max($0, 0) / hi) }
    }

    /// A tile's picture and its scale from the raw signed map: the display kernel first, then the clamp of negatives to 0 and the
    /// stretch to the map's own maximum (`normalised`). Filtering the clamped values instead would inflate a sparse map, since
    /// a negative pixel beside a positive one would no longer cancel. Display only: the raw map is what the tile keeps.
    static func display(of map: [Double], width: Int, height: Int, smoothing: MapSmoothing) -> (values: [Float], scale: Float) {
        let shown = smoothing.apply(map, width: width, height: height)
        return (normalised(shown), scale(of: shown))
    }

    /// The windows' picks: every listed element (quantified or fit only) with its family and the lines the person checked.
    static func picks(for e: ElementSelection) -> [ElementWindows.Pick] {
        e.activeZ.map { z in
            ElementWindows.Pick(symbol: PeriodicLayout.symbol(z), family: e.families[z].map { XRayFamily(rawValue: $0.rawValue)! },
                                lines: (e.lines[z] ?? []).sorted())
        }
    }

    /// The lines of each quantified element's map, "Al Kα+Kβ", keyed by Z: what the windows really are (a checked line off the
    /// axis is not there), in energy order.
    static func mapLines(windows: [LineWindow], quantified: Set<String>) -> [Int: String] {
        var out: [Int: String] = [:]
        for symbol in Set(windows.map(\.element)) where quantified.contains(symbol) {
            guard let z = PeriodicLayout.z(of: symbol),
                  let text = ElementWindows.summary(ofLineIDs: windows.filter { $0.element == symbol && $0.window != nil }.map(\.id)) else { continue }
            out[z] = text
        }
        return out
    }

    /// The lineage key of a Quantify step: which lines the maps used ("Al Kα+Kβ, Cu Kα"), additive beside the method's own keys.
    /// Empty before any map exists.
    var mapLinesParameters: [String: String] {
        mapLineSummaries.isEmpty ? [:] : ["map_lines": mapLineSummaries.sorted { $0.key < $1.key }.map(\.value).joined(separator: ", ")]
    }

    /// The sum of the maps of one element's lines (pixel by pixel); nil for none. One map is returned as it is.
    static func summed(_ maps: [[Double]]) -> [Double]? {
        guard var total = maps.first else { return nil }
        for m in maps.dropFirst() { for p in total.indices { total[p] += m[p] } }
        return total
    }

    /// The line and background windows the net maps use, as energy bands: one signal band per line window and its two background
    /// bands, from the windows' channel ranges through the axis. A channel is as wide as the axis step and centred on its energy,
    /// so channels `a..<b` cover `energy(a) - step/2` to `energy(b) - step/2`. A line with no window (no line on the axis) has none.
    static func windowBands(for windows: [LineWindow], axis: EnergyAxis) -> [WindowBand] {
        func band(_ r: Range<Int>) -> ClosedRange<Double> {
            let lo = axis.energy(ofChannel: r.lowerBound) - axis.scale / 2
            return lo...max(lo, axis.energy(ofChannel: r.upperBound) - axis.scale / 2)
        }
        var out: [WindowBand] = []
        for w in windows {
            guard let r = w.window else { continue }
            let z = PeriodicLayout.z(of: w.element), label = ElementWindows.label(ofLineID: w.id)
            out.append(WindowBand(id: w.id + ".signal", elementZ: z, label: label, range: band(r.signal), kind: .signal))
            if let b = r.background {
                out.append(WindowBand(id: w.id + ".left", elementZ: z, label: label, range: band(b.left), kind: .background))
                out.append(WindowBand(id: w.id + ".right", elementZ: z, label: label, range: band(b.right), kind: .background))
            }
        }
        return out
    }

    /// `priority` decides which name survives a collision: the window's own line (Kα) over its satellites, a quantified element over a fit-only one.
    /// `picked` are the lines the person checked: an element with any of them marks exactly those, one marker each; every other
    /// element marks its window's family, as before.
    /// How many lines of one family are marked for an element without a line pick: the alpha and the two strongest others.
    static let familyMarkerCap = 3

    static func markers(for windows: [LineWindow], axis: EnergyAxis, beam: Double?, quantified: Set<String> = [],
                        picked: Set<String> = []) -> [LineMarker] {
        var out: [LineMarker] = []
        let elementsWithPicks = Set(windows.filter { picked.contains($0.id) }.map(\.element))
        for w in windows {
            guard let chosen = XRayLines.line(w.id), let z = PeriodicLayout.z(of: w.element) else { continue }
            let bonus = quantified.contains(w.element) ? 1 : 0
            func marker(_ l: XRayLine, own: Bool) -> LineMarker {
                LineMarker(label: ElementWindows.label(ofLineID: l.id), energy: l.energy, elementZ: z,
                           fwhm: XRayLines.fwhm(resolutionMnKaEV: ElementWindows.defaultResolutionMnKaEV, atEnergy: l.energy),
                           priority: (own ? 2 : 0) + bonus)
            }
            if elementsWithPicks.contains(w.element) {
                if picked.contains(w.id) { out.append(marker(chosen, own: true)) }
                continue
            }
            // The family's strongest lines only (at least 5 % of the alpha, at most `familyMarkerCap`): an L family has nine lines
            // above 5 % (Hf) and labelling them all crowds the plot (drive 6, 2026-10-07); the person checks more under Lines.
            let family = XRayLines.lines(of: w.element).filter { $0.family == chosen.family && $0.weight >= 0.05 }
                .sorted { ($0.id == w.id ? 2 : 1, $0.weight) > ($1.id == w.id ? 2 : 1, $1.weight) }
                .prefix(Self.familyMarkerCap)
            for l in family {
                guard XRayLines.linesInRange([l.id], axis: axis, beamEnergy: beam).isEmpty == false else { continue }
                out.append(marker(l, own: l.id == w.id))
            }
        }
        return out
    }

    /// The Spectrum image step's registration warning: set when the image sits beside a 4D cube it was not registered to.
    static func imageSettings(_ meta: SpectrumImageMetadata, hasFourDCube: Bool) -> SpectrumImageSettings {
        var s = SpectrumImageSettings()
        if !meta.sameScanAs4DCube && hasFourDCube {
            s.sourceWarning = true
            s.sourceNote = meta.registrationNote ?? "Not registered to the 4D scan: the registration record comes with WP3."
        }
        return s
    }
}

/// The shown spectrum as CSV text (spec 2 D-14): `energy_kev,counts` and, where a fit is shown, `model,background`. The header
/// names the region and the file, as the results CSV does. Pure; the export button only hands it to a save panel.
nonisolated enum SpectrumCSV {
    static func text(_ s: SpectrumSeries, imageName: String, regionName: String) -> String {
        let withModel = s.hasModel, withBackground = s.hasBackground
        var out = ["# mac4DSTEM Spectroscopy spectrum, region: \(regionName)", "# file: \(imageName)"]
        if withModel || withBackground {
            out.append("# model and background are the pooled fit's (Quantify); channels outside its fit range have none")
        }
        var columns = ["energy_kev", "counts"]
        if withModel { columns.append("model") }
        if withBackground { columns.append("background") }
        out.append(columns.joined(separator: ","))
        let fitted = s.fitChannels
        for i in 0..<s.data.count {
            var f = [num(s.energy(i)), count(s.data[i])]
            let inFit = fitted?.contains(i) ?? true
            if withModel { f.append(inFit ? num(s.model[i]) : "") }
            if withBackground { f.append(inFit ? num(s.background[i]) : "") }
            out.append(f.joined(separator: ","))
        }
        return out.joined(separator: "\n") + "\n"
    }

    /// Six significant digits with a period, whatever the locale (the results CSV's rule).
    private static func num(_ v: Double) -> String { v.isFinite ? String(format: "%.6g", v) : "" }
    /// A summed count is whole: written as an integer (6 digits would round a large one).
    private static func count(_ v: Double) -> String { v.rounded() == v && abs(v) < 1e15 ? String(format: "%.0f", v) : num(v) }
}

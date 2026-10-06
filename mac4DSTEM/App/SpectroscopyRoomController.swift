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
    private var pixelTotals: [UInt64]?
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
    func totals() -> [UInt64]? { lock.withLock { pixelTotals } }
    func setTotals(_ t: [UInt64]) { lock.withLock { pixelTotals = t } }

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
    /// The Quantify verb has run: the pooled fit is live from here on (every setting re-fits, no Apply).
    @ObservationIgnored private(set) var quantifyActive = false
    /// The computed-k and absorption data files, read once (Resources/Spectroscopy); nil when the bundle lacks them.
    private nonisolated static let tables: QuantificationTables? = QuantificationTables.bundled()
    @ObservationIgnored private(set) var lastFit: PooledQuantification?
    /// The whole-map comparison line, shown with the region's fit (A2: the check blanks no at%, so it gates nothing; `present`).
    @ObservationIgnored private var heldWholeLine: String?
    @ObservationIgnored private var pendingWaiters: [CheckedContinuation<Void, Never>] = []

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
        m.mixed = []; m.tiles = []; m.results = []; m.markers = []
        m.active = .colorMix; m.elementColors = [:]; m.mapDisplays = [:]; m.haadfColormap = .gray
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
        m.image = Self.imageSettings(meta, axis: axis, hasFourDCube: hasFourDCube)
        m.regionSettings = RegionSettings()
        autoIDTask?.cancel(); autoIDTask = nil
        m.resetAutoID()
        m.onAutoID = { [weak self] in self?.runAutoID() }
        m.onCancelAutoID = { [weak self] in self?.cancelAutoID() }
        m.onRegionEdit = { [weak self] shape, final in self?.editRegion(shape, final: final) }
        m.onRemoveRegion = { [weak self] id in self?.removeRegion(id: id) }
        m.onPin = { [weak self] in self?.pinRegion() }
        m.onUnpin = { [weak self] id in self?.unpin(id) }
        syncRegionsFromSession()
        let first = refresh()
        // ADR 056 item 6: Auto ID runs on open, after the first sums have landed; its proposals are mapped, marked proposed
        // and left unquantified. It needs the beam energy, so a file without one says so (the Auto ID row).
        autoIDOnOpen?.cancel()
        autoIDOnOpen = m.autoIDEnabled ? Task { [weak self] in
            await first?.value
            guard !Task.isCancelled else { return }
            self?.runAutoID()
        } : nil
    }
    @ObservationIgnored private var autoIDOnOpen: Task<Void, Never>?
    @ObservationIgnored private var autoIDRestart = false

    func unbind() {
        generation += 1
        autoIDOnOpen?.cancel(); autoIDOnOpen = nil
        cancelAutoID()
        checkTask?.cancel(); checkTask = nil
        proposalTask?.cancel(); proposalToken += 1
        source = nil
        session = nil
        model.isLive = false
    }

    /// The window gained or lost its 4D cube after the image was opened: the Source row follows.
    func setFourDCube(_ present: Bool) {
        guard present != hasFourDCube, let source else { hasFourDCube = present; return }
        hasFourDCube = present
        let readouts = Self.imageSettings(source.metadata, axis: source.energyAxis, hasFourDCube: present)
        model.image.source = readouts.source
        model.image.sourceWarning = readouts.sourceWarning
        model.image.sourceNote = readouts.sourceNote
    }

    // MARK: Edits

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
    /// overtaken by an edit (`refresh` cancels it). Suggestions and suspect markers; nothing is applied (ADR 054 §6).
    func runAutoID() {
        guard let source, let session, let region = session.regions.first(where: { $0.id == session.selectedRegionID }),
              !model.autoID.running else { return }
        let token = model.beginAutoID()
        guard let beam = session.method.beamEnergyKeV ?? source.metadata.beamEnergyKeV, beam > 0 else {
            model.failAutoID(token: token, message: "Auto ID needs the beam energy: the file does not state it. Type it in Quantify.")
            return
        }
        let current = model.elements.activeZ.map { PeriodicLayout.symbol($0) }
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
                outcome = AutoIDPresentation.outcome(result, region: name, beside: AutoIDPresentation.besideCheck(settings: settings, axis: source.energyAxis))
            } catch ProposerError.cancelled { return   // cancelled or overtaken: a silent discard, no note
            } catch { failure = "Auto ID could not fit this spectrum: \((error as? LocalizedError)?.errorDescription ?? "\(error)")" }
            if Task.isCancelled { return }
            await MainActor.run { [weak self] in
                if let outcome {
                    // R4c: the proposals' maps only (`proposalsChanged`): no listed pick moved, so the fit and its in-flight
                    // unlisted-line check are left alone.
                    if self?.model.finishAutoID(token: token, outcome: outcome) == true { self?.proposalsChanged() }
                } else { self?.model.failAutoID(token: token, message: failure ?? "Auto ID failed.") }
            }
        }
    }

    @ObservationIgnored private var proposalToken = 0
    @ObservationIgnored private(set) var proposalTask: Task<Void, Never>?

    /// Auto ID has landed: the proposals' dimmed tiles are (re)computed under their own token. No `generation` bump and no
    /// `checkTask` reset (the listed picks did not change, so the fit and its unlisted-line check are still the right ones);
    /// a `refresh` supersedes it by bumping the token, its own output carrying the proposals.
    func proposalsChanged() {
        guard let source else { return }
        lastElements = model.elements   // the suggestions are part of the selection; the view's change callback must not refresh for them
        proposalToken += 1
        let token = proposalToken
        let listed = Set(model.elements.activeZ)
        let picks: [(symbol: String, family: XRayFamily?)] = model.elements.activeZ.map { z in
            (PeriodicLayout.symbol(z), model.elements.families[z].map { XRayFamily(rawValue: $0.rawValue)! })
        }
        let proposed: [(symbol: String, family: XRayFamily?)] = model.elements.suggestions.filter { !listed.contains($0.z) }
            .prefix(ProposedTileCap.maximum)   // UX #1: a display count; the suggestions arrive strongest first
            .map { (PeriodicLayout.symbol($0.z), nil) }
        let integrated = model.mapMode == .integrated, beam = source.metadata.beamEnergyKeV
        let cache = cache
        proposalTask?.cancel()
        proposalTask = Task.detached(priority: .userInitiated) {
            let (windows, maps) = Self.proposalMaps(source: source, picks: picks, proposed: proposed, integrated: integrated, beam: beam, cache: cache)
            await MainActor.run { [weak self] in self?.landProposals(windows, maps, token: token) }
        }
    }

    private func landProposals(_ windows: [LineWindow], _ maps: [[Double]?], token: Int) {
        guard token == proposalToken, let source else { return }
        let m = model
        var tiles = m.tiles.filter { !$0.proposed }
        for (i, w) in windows.enumerated() {
            guard let z = PeriodicLayout.z(of: w.element), let map = maps[i] else { continue }
            tiles.append(MapTile(z: z, width: source.nx, height: source.ny, values: Self.normalised(map), proposed: true))
        }
        m.tiles = tiles
        m.tileRevision += 1
        if case .element(let z) = m.active, !tiles.contains(where: { $0.z == z }) { m.active = .colorMix }
        // R10: the proposals' muted markers land with their tiles (this path does not run `apply`).
        m.markers = m.markers.filter { $0.kind != .proposed } + Self.proposedMarkers(for: windows, axis: source.energyAxis, beam: source.metadata.beamEnergyKeV)
        if !m.viewportIsManual {
            let r = SpectrumAutoZoom.range(markers: m.markers, domain: m.series.domain, minimumSpan: m.viewport.minimumSpan, countsEnergy: Self.countsEnergy(m.series), fitEnd: fitEnd(for: source))
            m.viewport.lo = r.lowerBound; m.viewport.hi = r.upperBound
        }
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
        guard applySettingsToSession(), quantifyActive else { return }
        refresh()
    }

    /// The Quantify verb: fits the selected region's pooled spectrum with the session's method and, from now on, keeps it
    /// live. Returns true when a fit landed; the caller records the replay step (`recordQuantification`) then. The
    /// session's method takes the run's own (a computed k's source string filled in), so the record names it.
    func quantify() async -> Bool {
        guard canQuantify, let session else { return false }
        quantifyActive = true
        model.quantify.syncTypedElements(model.elements.quantified.map { PeriodicLayout.symbol($0) })
        applySettingsToSession()
        guard var task = refresh() else { return false }
        // Wait for the NEWEST recompute: Auto ID landing (or an edit) while the fit runs starts another that replaces this one's
        // answer, and the verb must report the fit that stands, not the one that was overtaken.
        while true {
            await task.value
            guard let latest = lastRefresh, latest != task else { break }
            task = latest
        }
        guard !model.isFitting, model.fitFailure == nil, let fit = lastFit else { return false }
        session.method = fit.method
        lastApplied = nil   // the filled method differs from the controls' by the k source only; the next edit re-applies
        return true
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
            m.spectrumTitle = "Spectrum · \(region.name)"
            m.spectrumSubtitle = "\(Self.counts(total)) counts · \(region.pixelCount) px · live"
            m.regionSettings.pixels = "\(region.pixelCount)"
            m.regionSettings.counts = Self.counts(total)
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
            await MainActor.run { [weak self] in self?.landCheck(shown, region: region, generation: gen) }
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

    private struct Request: Sendable {
        let source: any SpectrumImageSource
        let region: Int
        let mask: PixelMask?
        let picks: [(symbol: String, family: XRayFamily?)]
        /// Auto ID's proposals that are not listed: their maps only (never a row, never a marker).
        let proposed: [(symbol: String, family: XRayFamily?)]
        let integrated: Bool
        let beam: Double?
        let firstPass: Bool
        /// Set once the Quantify verb has run: the pooled fit of this region with this method.
        let quantify: QuantifyRequest?
    }

    private struct QuantifyRequest: Sendable {
        let method: QuantificationMethod
        let metadata: SpectrumImageMetadata
        let regionName: String
        let pixelCount: Int
    }

    private struct Output: Sendable {
        let region: Int
        let spectrum: [UInt64]
        /// The whole map's spectrum (the comparison overlay), nil until it has been summed once.
        let whole: [UInt64]?
        let windows: [LineWindow]
        let counts: [LineNetCount?]
        let maps: [[Double]?]
        /// The proposals' windows and maps, in `Request.proposed` order.
        let proposedWindows: [LineWindow]
        let proposedMaps: [[Double]?]
        let pixelTotals: [UInt64]?
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
            autoIDRestart = model.autoIDEnabled   // the open's run is not lost to a click made while it ran: it starts again below
        }
        checkTask?.cancel(); checkTask = nil         // about the previous fit; the next fit starts its own
        generation += 1
        proposalToken += 1                           // this refresh's output carries the proposals
        let gen = generation
        let picks: [(symbol: String, family: XRayFamily?)] = model.elements.activeZ.map { z in
            (PeriodicLayout.symbol(z), model.elements.families[z].map { XRayFamily(rawValue: $0.rawValue)! })
        }
        let listed = Set(model.elements.activeZ)
        let proposed: [(symbol: String, family: XRayFamily?)] = model.elements.suggestions.filter { !listed.contains($0.z) }
            .prefix(ProposedTileCap.maximum)   // UX #1: a display count; the suggestions arrive strongest first
            .map { (PeriodicLayout.symbol($0.z), nil) }
        var quantify: QuantifyRequest?
        if quantifyActive {
            quantify = QuantifyRequest(method: session.method, metadata: source.metadata, regionName: region.name, pixelCount: region.pixelCount)
            model.isFitting = true
        }
        let request = Request(source: source, region: region.id, mask: session.mask(of: region), picks: picks,
                              proposed: proposed, integrated: model.mapMode == .integrated,
                              beam: source.metadata.beamEnergyKeV, firstPass: cache.totals() == nil, quantify: quantify)
        let cache = cache
        let task = Task.detached(priority: .userInitiated) {
            let out = Self.compute(request, cache: cache)
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

    /// The proposals' windows and maps, in `proposed` order (windowed together with the listed picks, for their maps only).
    private nonisolated static func proposalMaps(source: any SpectrumImageSource, picks: [(symbol: String, family: XRayFamily?)],
                                                 proposed: [(symbol: String, family: XRayFamily?)], integrated: Bool, beam: Double?,
                                                 cache: SpectrumComputeCache) -> ([LineWindow], [[Double]?]) {
        let all = ElementWindows.build(elements: picks + proposed, axis: source.energyAxis, beamEnergyKeV: beam)
        let ws = Array(all.suffix(proposed.count))
        return (ws, mapsFor(ws, source: source, integrated: integrated, cache: cache))
    }

    private nonisolated static func compute(_ r: Request, cache: SpectrumComputeCache) -> Output {
        let spectrum: [UInt64]
        if let s = cache.spectrum(r.region) { spectrum = s } else {
            spectrum = r.source.sum(mask: r.mask)
            cache.setSpectrum(spectrum, r.region)
        }
        var totals: [UInt64]?
        if r.firstPass {
            let t = r.source.windowSums([0..<r.source.channels])[0]
            cache.setTotals(t)
            totals = t
        }
        // The comparison overlay's spectrum: the whole map, summed once (region 0 is the whole map, `SpectroscopySession.open`).
        var whole: [UInt64]?
        if r.region == 0 { whole = spectrum } else if let w = cache.spectrum(0) { whole = w } else {
            let w = r.source.sum(mask: nil)
            cache.setSpectrum(w, 0)
            whole = w
        }
        let windows = ElementWindows.build(elements: r.picks, axis: r.source.energyAxis, beamEnergyKeV: r.beam)
        let counts = ElementWindows.netCounts(spectrum: spectrum, windows: windows)
        func mapsFor(_ ws: [LineWindow]) -> [[Double]?] { Self.mapsFor(ws, source: r.source, integrated: r.integrated, cache: cache) }
        let maps = mapsFor(windows)
        // The proposals are windowed together with the listed elements (neighbouring lines merge their background windows,
        // eXSpy's rule) but ONLY for their own maps: the listed elements' windows, rows and net counts above are built
        // without them, so a proposal never moves a listed number.
        var proposedWindows: [LineWindow] = [], proposedMaps: [[Double]?] = []
        if !r.proposed.isEmpty {
            (proposedWindows, proposedMaps) = Self.proposalMaps(source: r.source, picks: r.picks, proposed: r.proposed, integrated: r.integrated, beam: r.beam, cache: cache)
        }
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
                if r.region != 0, let w = whole {
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
        return Output(region: r.region, spectrum: spectrum, whole: whole, windows: windows, counts: counts, maps: maps,
                      proposedWindows: proposedWindows, proposedMaps: proposedMaps, pixelTotals: totals,
                      fit: fit, fitInput: fitInput, fitFailure: failure, wholeLine: wholeLine)
    }

    private func apply(_ out: Output, generation gen: Int) {
        guard gen == generation, let source, let session else { return }
        defer { if autoIDRestart { autoIDRestart = false; runAutoID() } }
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
        m.spectrumTitle = "Spectrum · \(name)"
        m.spectrumSubtitle = "\(Self.counts(total)) counts · \(pixels) px"
        m.resultsTitle = "Results · \(name)"
        m.regionSettings.source = region?.kind == .drawn ? "Drawn" : "Whole map"
        m.regionSettings.pixels = "\(pixels)"
        m.regionSettings.counts = Self.counts(total)

        if let t = out.pixelTotals { Self.applyPixelStats(t, to: m) }

        // Markers: the chosen family's lines of every active element.
        m.markers = Self.markers(for: out.windows, axis: axis, beam: source.metadata.beamEnergyKeV,
                                 quantified: Set(m.elements.quantified.map { PeriodicLayout.symbol($0) }))
            + Self.proposedMarkers(for: out.proposedWindows, axis: axis, beam: source.metadata.beamEnergyKeV)
            + (m.autoID.outcome?.suspectMarkers ?? [])

        // Rows, tiles: the quantified elements only (fit-only ones shape the windows, not the table).
        var rows: [ResultRow] = [], tiles: [MapTile] = []
        let quantified = Set(m.elements.quantified.map { PeriodicLayout.symbol($0) })
        for (i, w) in out.windows.enumerated() where quantified.contains(w.element) {
            guard let z = PeriodicLayout.z(of: w.element) else { continue }
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
            if let map = out.maps[i] {
                tiles.append(MapTile(z: z, width: source.nx, height: source.ny, values: Self.normalised(map),
                                     notMeasuredWhy: out.counts[i]?.notAMeasurementText))
                // R10: a picked element goes into the mix (a picture); its not-a-measurement note stays on the tile and the row. The user may untick.
                if seenTiles.insert(z).inserted { m.mixed.insert(z) }
            }
        }
        m.results = rows
        applyFit(out, source: source)
        // Auto ID's proposals: a dimmed tile each (the evidence), never ticked into the ColorMix, never a row.
        for (i, w) in out.proposedWindows.enumerated() {
            guard let z = PeriodicLayout.z(of: w.element), let map = out.proposedMaps[i] else { continue }
            tiles.append(MapTile(z: z, width: source.nx, height: source.ny, values: Self.normalised(map), proposed: true))
        }
        m.tiles = tiles
        m.tileRevision += 1
        // A tile that is gone loses its tick and its "seen" mark, so it is ticked again when it comes back.
        let present = Set(tiles.filter { !$0.proposed }.map(\.z))
        seenTiles.formIntersection(present)
        m.mixed.formIntersection(present)
        // The active map is one that exists: a tile that went away hands the outline back to the ColorMix.
        if case .element(let z) = m.active, !tiles.contains(where: { $0.z == z }) { m.active = .colorMix }
        if !m.viewportIsManual {
            let r = SpectrumAutoZoom.range(markers: m.markers, domain: m.series.domain, minimumSpan: m.viewport.minimumSpan, countsEnergy: Self.countsEnergy(m.series), fitEnd: fitEnd(for: source))
            m.viewport.lo = r.lowerBound; m.viewport.hi = r.upperBound
        }
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
                                  elements: SpectroscopyExport.elementsLine(fit), methodHash: SpectroscopyExport.shortHash(fit.method),
                                  fileStem: SpectroscopyExport.fileStem(imageName: source.metadata.fileName, regionName: regionName))
        m.quantify.quality = fit.qualityText
        switch fit.absorption {
        case .off: m.quantify.absorptionNote = nil
        case .applied(let s): m.quantify.absorptionNote = s
        case .refused(let why): m.quantify.absorptionNote = "not applied: \(why)"
        }
        let axisText = QuantifyPresentation.axisReadouts(fit)
        m.image.energyAxisReadout = axisText.file
        m.image.energyAxisRefined = axisText.refined
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

    /// A net-count map as 0...1 (negative net counts are drawn as 0): presentation scaling, not a result.
    private static func normalised(_ map: [Double]) -> [Float] {
        let hi = map.max() ?? 0
        guard hi > 0 else { return [Float](repeating: 0, count: map.count) }
        return map.map { Float(max($0, 0) / hi) }
    }

    /// `priority` decides which name survives a collision: the window's own line (K\u{03B1}) over its satellites, a quantified element over a fit-only one.
    static func markers(for windows: [LineWindow], axis: EnergyAxis, beam: Double?, quantified: Set<String> = []) -> [LineMarker] {
        var out: [LineMarker] = []
        for w in windows {
            guard let chosen = XRayLines.line(w.id), let z = PeriodicLayout.z(of: w.element) else { continue }
            for l in XRayLines.lines(of: w.element) where l.family == chosen.family && l.weight >= 0.05 {
                guard XRayLines.linesInRange([l.id], axis: axis, beamEnergy: beam).isEmpty == false else { continue }
                out.append(LineMarker(label: ElementWindows.label(ofLineID: l.id), energy: l.energy, elementZ: z,
                                      fwhm: XRayLines.fwhm(resolutionMnKaEV: ElementWindows.defaultResolutionMnKaEV, atEnergy: l.energy),
                                      priority: (l.id == w.id ? 2 : 0) + (quantified.contains(w.element) ? 1 : 0)))
            }
        }
        return out
    }

    /// Auto ID's proposals on the first spectrum (R10): each proposed element's own line, muted and dashed, named like a picked
    /// one ("Al Kα", no "?": that is a suspect's). Accepting turns it into a coloured marker through `markers`.
    static func proposedMarkers(for windows: [LineWindow], axis: EnergyAxis, beam: Double?) -> [LineMarker] {
        var out: [LineMarker] = []
        for w in windows {
            guard let l = XRayLines.line(w.id), let z = PeriodicLayout.z(of: w.element),
                  XRayLines.linesInRange([l.id], axis: axis, beamEnergy: beam).isEmpty == false else { continue }
            out.append(LineMarker(label: ElementWindows.label(ofLineID: l.id), energy: l.energy, elementZ: z, kind: .proposed,
                                  fwhm: XRayLines.fwhm(resolutionMnKaEV: ElementWindows.defaultResolutionMnKaEV, atEnergy: l.energy)))
        }
        return out
    }

    private static func applyPixelStats(_ totals: [UInt64], to m: SpectroscopyRoomModel) {
        guard !totals.isEmpty else { return }
        let sorted = totals.sorted()
        let median = sorted[sorted.count / 2]
        m.image.countsMedian = "median \(median)"
        let hi = Double(sorted.last ?? 1)
        var bins = [Double](repeating: 0, count: 10)
        for t in totals { bins[min(9, Int(Double(t) / max(hi, 1) * 10))] += 1 }
        m.image.countsHistogram = bins
    }

    /// The Spectrum image step's readouts, from what the file says (nothing is invented: a missing value hides its row).
    static func imageSettings(_ meta: SpectrumImageMetadata, axis: EnergyAxis, hasFourDCube: Bool) -> SpectrumImageSettings {
        var s = SpectrumImageSettings()
        if meta.sameScanAs4DCube {
            s.source = "same scan as the 4D cube (one GMS run)"
        } else if hasFourDCube {
            s.source = "not registered to the 4D scan"
            s.sourceWarning = true
            s.sourceNote = meta.registrationNote ?? "Not registered to the 4D scan: the registration record comes with WP3."
        }
        if let f = meta.frames {
            s.framesReadout = "\(f) summed" + (meta.partialFramePixels > 0 ? " + a partial frame (\(meta.partialFramePixels) px)" : "")
        }
        s.energyAxisReadout = "\(String(format: "%.3f", axis.lowValue))–\(String(format: "%.3f", axis.highValue)) keV · \(String(format: "%.2f", axis.scale * 1000)) eV/ch · from the file"
        // Live and real time are shown as the file stored them: their meaning differs by file and is not interpreted.
        if let d = meta.detectors.first(where: { $0.liveTime != nil || $0.realTime != nil }) {
            if (d.liveTime ?? 0) <= 0 && (d.realTime ?? 0) <= 0 {
                s.liveDead = "not read: the stream metadata records 0 s"   // the stream stores 0; the SpectrumImage record holds the times (open item: reader)
            } else {
                let live = d.liveTime.map { "live \(String(format: "%g", $0)) s" }
                let real = d.realTime.map { "real \(String(format: "%g", $0)) s" }
                s.liveDead = ([live, real].compactMap { $0 }.joined(separator: " · ")) + " (as stored, semantics unverified)"
            }
        }
        var g: [String] = []
        if !meta.detectors.isEmpty { g.append(meta.detectors.count == 1 ? "1 detector" : "\(meta.detectors.count) detectors") }
        let els = meta.detectors.compactMap(\.elevationDegrees)
        if let lo = els.min(), let hi = els.max() {
            g.append(lo == hi ? String(format: "elev. %.0f°", lo) : String(format: "elev. %.0f–%.0f°", lo, hi))
        }
        if let a = meta.alphaTiltDegrees { g.append(String(format: "α %.1f°", a)) }
        if let b = meta.betaTiltDegrees { g.append(String(format: "β %.1f°", b)) }
        if !g.isEmpty { s.geometry = g.joined(separator: " · ") }
        return s
    }
}

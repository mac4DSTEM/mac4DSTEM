//
//  AppState+EDS.swift
//  Role: the window's side of the EDS room (MacEMUI's shared room): the session's status and failure hooks, what the room's views
//        ask of the window (`edxActions`) and the export folder a UI journey names. The 4D links (pools, precipitate joins, replay, Results rows) follow in this file.
//

import Foundation
import DSTEMCore
import DSTEMSession
import SpectroCore
import SpectroEDX
import ShellEDXModel
import ShellSpectroscopy

extension AppState {
    /// The session reports to the window's status line and error presentation; set once (`wireSpectroscopyOperations`).
    func wireEDS() {
        edx.onEvent = { [weak self] in self?.statusText = $0 }
        edx.onFailure = { [weak self] in self?.present($0) }
    }

    /// What the shared EDS room's views ask of this window: the status line, the error sheet, a UI journey's export folder, and the
    /// 4D scan's composition by class.
    var edxActions: EDXRoomActions {
        EDXRoomActions(report: { [weak self] in self?.statusText = $0 }, present: { [weak self] in self?.present($0) },
                       exportDirectory: { [weak self] in self?.exportDirectory },
                       exportCompositionByClass: { [weak self] in await self?.exportCompositionByClass() })
    }

    /// Where an export journey writes without a save panel (`--export-dir <path>`): an absolute path as given, a relative one inside
    /// the app's temporary folder (macTEM's launch option). nil for a normal launch.
    var exportDirectory: URL? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let i = arguments.firstIndex(of: "--export-dir"), arguments.indices.contains(i + 1) else { return nil }
        let name = arguments[i + 1]
        return name.hasPrefix("/") ? URL(fileURLWithPath: name, isDirectory: true)
            : FileManager.default.temporaryDirectory.appendingPathComponent(name, isDirectory: true)
    }
}

// MARK: Quantify and its replay step

extension AppState {
    /// The Quantify verb in the EDS room: the session fits (and stays live from then on), and a fit that landed is recorded as the
    /// lineage's "quantification" step with the old room's keys (`SpectroscopySession.recordQuantification`, unchanged), so steps,
    /// Results rows and restores read as before. The method recorded is the EDS session's.
    func quantifyEDS() async {
        guard let task = edx.quantify() else { return }
        await task.value
        await edx.pendingCheck?.value   // the at% is held until the unlisted-line check lands
        guard let fit = edx.fit else { return }
        spectroscopy.method = edx.method
        let (kind, name) = Self.replayRegion(edx.region, pinName: edx.selectedPin?.name)
        // A pool is the 4D scan's: the step records the registration it went through (E1); a drawn region or the whole map has none.
        let registration: RegistrationRecordM2? = { if case .pool = edx.region { return spectroscopy.registration } else { return nil } }()
        spectroscopy.recordQuantification(in: replay, registration: registration, regionKind: kind, regionName: name,
                                          extra: Self.edsResultParameters(fit))
    }

    /// The step's `region_kind` and `region_name`, as the old room's region kinds: "wholeMap", "drawn", or the pool's kind.
    nonisolated static func replayRegion(_ region: EDXRegion, pinName: String?) -> (kind: String, name: String) {
        switch region {
        case .wholeMap: ("wholeMap", "Whole map")
        case .pool(let p): (p.kind, p.name)
        default: ("drawn", pinName ?? region.name)
        }
    }

    /// The fit's numbers as step keys, as the old room wrote them: `result_at` / `result_wt` ("Al 97.6 ± 0.5 · Si 1.5 ± 0.3", elements
    /// with a number only), `result_unit` and `validation` ("none": the fit is unvalidated).
    nonisolated static func edsResultParameters(_ fit: PooledQuantification) -> [String: String] {
        func line(_ value: (PooledQuantification.Row) -> (Double?, Double?)) -> String {
            fit.rows.compactMap { r -> String? in
                guard r.failure == nil, case let (v?, s) = value(r) else { return nil }
                return "\(r.element) \(String(format: "%.1f", v))" + (s.map { " \u{00B1} " + String(format: "%.1f", $0) } ?? "")
            }.joined(separator: " \u{00B7} ")
        }
        return ["result_at": line { ($0.atomicPercent, $0.atomicSigma) }, "result_wt": line { ($0.weightPercent, $0.weightSigma) },
                "result_unit": "at%", "validation": "none"]
    }
}

// MARK: The 4D scan's pools

extension AppState {
    /// The catalogue's pools as EDS regions: the replay kind ("phase", "group", "notIndexed"), the name, the mask on the spectrum
    /// image's grid and a key that changes when the pool's content can (its id and the product generation it was built from).
    nonisolated static func edsPools(_ catalogue: PoolCatalogue) -> [EDXPoolRegion] {
        catalogue.pools.map { EDXPoolRegion(kind: $0.kind.rawValue, name: $0.name, mask: $0.mask,
                                            key: "\($0.id)@\($0.sourceGeneration)", validation: $0.validation) }
    }
}

// MARK: Composition by class

extension AppState {
    /// Every phase pool of the 4D scan summed once and fitted with the EDS room's method (detached), then written as one CSV through the
    /// room's save (the old room's "Composition by Class…"). A pool that cannot be fitted says why in its row.
    func exportCompositionByClass() async {
        guard let source = edx.source else { return }
        let pools = edx.pools.filter { $0.kind == "phase" }
        guard !pools.isEmpty else { statusText = "No phase pools: run phase mapping in Crystal Maps on this scan."; return }
        let method = edx.method, metadata = source.metadata, axis = source.energyAxis, imageName = metadata.fileName
        statusText = "Fitting \(pools.count) phase pools…"
        let csv = await Task.detached(priority: .userInitiated) { () -> String? in
            let sums = pools.map { CompositionByClass.Pool(name: $0.name, pixels: $0.mask.reduce(0) { $0 + ($1 ? 1 : 0) },
                                                           spectrum: source.sum(mask: $0.mask)) }
            guard let results = try? CompositionByClass.run(pools: sums, axis: axis, metadata: metadata, method: method,
                                                           tables: QuantificationTables.bundled()) else { return nil }
            return CompositionByClass.csv(results, imageName: imageName, method: method)
        }.value
        edxRoom.save(csv.map { Data($0.utf8) }, kind: .compositionByClass,
                     stem: SpectroscopyExport.fileStem(imageName: imageName, regionName: "composition-by-class"),
                     directory: exportDirectory) { statusText = $0 }
    }
}

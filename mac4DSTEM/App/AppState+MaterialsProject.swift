//
//  AppState+MaterialsProject.swift
//  Role: session S5's fetch glue — the one place that actually talks to
//        api.materialsproject.org, and the one writer that turns a fetched
//        `CrystalModel` into session state. `MaterialsProjectImport`
//        (Core/Crystal) does the request-building, decoding and phase check;
//        this file owns the network call itself and where the result lands.
//
//  Nothing here runs automatically. `fetchMaterialsProject` is called from
//  exactly one place — `MaterialsProjectImportSheet`'s Fetch button — the
//  same "explicit primary action" rule every whole-dataset analysis in this
//  app already follows (`docs/architecture.md`, "Workflow").
//
//  `MaterialsProjectTransport` exists so a test can hand `fetchMaterialsProject`
//  a canned response instead of touching the network — the same seam
//  `FourDDataSource` gives readers, at the one call this app makes outward.
//

import Foundation
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif

/// The one HTTP call this app makes outward, abstracted so tests can stub it.
package protocol MaterialsProjectTransport {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

/// Production transport: a thin `URLSession.shared` wrapper. `nonisolated`
/// (like `KeychainAPIKeyStore`) so `= URLSessionTransport()` is usable as a
/// default parameter value — a default argument expression is always
/// checked as nonisolated, whatever the isolation of the function it defaults.
package nonisolated struct URLSessionTransport: MaterialsProjectTransport {
    package init() {}

    package func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await URLSession.shared.data(for: request)
    }
}

/// What one Fetch attempt produced. Never `Equatable`: `MaterialsProjectDocument`
/// and `CrystalModel` are not, and adding that conformance to two heavily
/// shared Core types just for this one enum is not this session's call to
/// make — tests pattern-match with `switch`/`guard case` instead.
package enum MaterialsProjectFetchOutcome {
    /// No key is stored — `fetchMaterialsProject` never builds a request or
    /// touches `transport` in this case (`MaterialsProjectSessionTests`).
    case noAPIKey
    /// Named per `MaterialsProjectImport.Failure.errorDescription` where the
    /// failure is Core's; HTTP-status text is composed here (see
    /// `fetchMaterialsProject` below) since Core has no HTTP layer to word it
    /// from.
    case failure(String)
    case fetched(
        document: MaterialsProjectDocument, model: CrystalModel,
        verdict: PhaseExpectationVerdict, fetchedAt: Date
    )
}

extension AppState {
    /// Fetch one material by id and grade it against `expectation`.
    ///
    /// HTTP status handling (owner's brief, session S5): 401/403 → the key
    /// was rejected; 404 → no such id; 429 → rate limited. A 200 whose body's
    /// `errors` array is non-empty, and everything Core itself throws
    /// (`MaterialsProjectImport.Failure` — malformed JSON, empty `data`, and
    /// whatever the concurrent S5b `standardise` work adds), falls through to
    /// the generic `LocalizedError` description rather than a case-by-case
    /// switch: a new `Failure` case must not silently stop being reported
    /// just because this call site never learned its name.
    func fetchMaterialsProject(
        materialID: String,
        expectation: PhaseExpectation,
        transport: MaterialsProjectTransport = URLSessionTransport()
    ) async -> MaterialsProjectFetchOutcome {
        guard let apiKey = materialsProject.currentKey() else {
            return .noAPIKey
        }

        let request: URLRequest
        do {
            request = try MaterialsProjectImport.request(materialID: materialID, apiKey: apiKey)
        } catch {
            return .failure(describe(error))
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await transport.data(for: request)
        } catch {
            return .failure(describe(error))
        }

        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            // The body may still be the documented envelope even on a
            // non-200 status (the API does this for some 4xx cases) — use
            // its own error message when it decodes, rather than a bare code.
            let bodyMessage = (try? MaterialsProjectImport.decode(data))?.errors.first?.message
            switch http.statusCode {
            case 401, 403:
                return .failure("API key rejected" + (bodyMessage.map { " — \($0)" } ?? "."))
            case 404:
                return .failure("No material with that id.")
            case 429:
                return .failure("Rate limited — try again.")
            default:
                return .failure(bodyMessage ?? "Materials Project returned HTTP \(http.statusCode).")
            }
        }

        do {
            let decoded = try MaterialsProjectImport.decode(data)
            let doc = try MaterialsProjectImport.firstDocument(in: decoded)
            let fetchedAt = Date()
            let model = try MaterialsProjectImport.crystalModel(from: doc, fetchedAt: fetchedAt)
            let verdict = MaterialsProjectImport.check(doc, against: expectation)
            return .fetched(document: doc, model: model, verdict: verdict, fetchedAt: fetchedAt)
        } catch MaterialsProjectImport.Failure.emptyResult {
            // A 200 with an empty `data` array is indistinguishable from "not
            // found" — same wording as the literal HTTP 404 case above.
            return .failure("No material with that id.")
        } catch {
            return .failure(describe(error))
        }
    }

    private func describe(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? String(describing: error)
    }

    /// Stores a fetched model exactly where a CIF import goes — mirrors
    /// `importCrystalModel(from:)` (`App/AppState+Open.swift`) — and, when
    /// the sheet was opened from the Phase workspace, also adds it as a phase
    /// slot the way `PhaseMappingSections.add(_:)` (`UI/PhaseMappingSettings.swift`)
    /// does. One entry point either way: a phase fetched from the ACOM room
    /// still becomes selectable from the phase list later, once it is in
    /// `importedCrystalModels`.
    func importFetchedCrystalModel(_ model: CrystalModel, addAsPhaseSlot: Bool = false) {
        if let index = acomSession.importedCrystalModels.firstIndex(where: { $0.id == model.id }) {
            acomSession.importedCrystalModels[index] = model
        } else {
            acomSession.importedCrystalModels.append(model)
        }
        acomSession.modelSelection = .imported(model.id)
        statusText = "Imported phase model \"\(model.displayName)\" from Materials Project"
        if addAsPhaseSlot {
            addPhaseMappingSlot(model)
        }
    }

    /// The duplicate/matrix rule for adding a phase slot: skip a phase
    /// already in the list; the first phase added to an empty list becomes
    /// the matrix, since a list with phases and no matrix cannot run.
    /// `PhaseMappingSections.add(_:)` (`UI/PhaseMappingSettings.swift`)
    /// delegates here too, so the Materials Project sheet and the CIF/library
    /// "Add Phase" menu share the one rule.
    func addPhaseMappingSlot(_ model: CrystalModel) {
        guard !phaseMapping.phases.contains(where: { $0.model.id == model.id }) else { return }
        let isFirst = phaseMapping.phases.isEmpty
        phaseMapping.phases.append(
            PhaseMappingSlot(model: model, isMatrix: isFirst, u: 0, v: 0, w: 1))
    }
}

/// The Import button's enabled state, pulled out as a pure function so a test
/// can drive it without a network fetch. False before any fetch and on
/// failure or a phase mismatch — false is the default a caller falls back to
/// on `nil`, matching "no fetch yet" the same way `.failure` and `.noAPIKey`
/// read.
package func canImport(outcome: MaterialsProjectFetchOutcome?) -> Bool {
    guard case .fetched(_, _, let verdict, _) = outcome else { return false }
    switch verdict {
    case .matches, .unchecked: return true
    case .mismatch: return false
    }
}

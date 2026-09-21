//
//  MaterialsProjectSettings.swift
//  Role: session S5's Settings-scene owner — whether a Materials Project API
//        key is stored, and the save/remove actions the Settings view drives.
//        A thin `@Observable` wrapper over the injected `APIKeyStore` (S4a,
//        `Session/MaterialsProjectKeyStore.swift`): it never re-implements
//        Keychain access, it only turns "is a key there" into an observable
//        fact and offers `currentKey()` for the one caller that needs the
//        value itself (`AppState.fetchMaterialsProject`,
//        `App/AppState+MaterialsProject.swift`).
//
//  `hasKey` is cached at `load()`, not derived live on every read — the same
//  shape as `DatasetResidency.isResident` — so a SwiftUI `Form` observes one
//  `Bool` instead of re-touching the Keychain on every body evaluation.
//  `currentKey()` deliberately bypasses that cache and asks the store
//  directly: a fetch must never send a key that was just removed because the
//  cached flag had not yet been told.
//

import Foundation
import Observation

@Observable
@MainActor
package final class MaterialsProjectSettings {
    package private(set) var hasKey: Bool = false

    private let store: APIKeyStore

    package init(store: APIKeyStore = KeychainAPIKeyStore()) {
        self.store = store
        load()
    }

    /// Re-reads the store. Called at `init`, and after every `save`/`remove`
    /// so `hasKey` can never disagree with what is actually stored.
    package func load() {
        let key = try? store.load()
        hasKey = !(key?.isEmpty ?? true)
    }

    package func save(_ key: String) throws {
        try store.save(key)
        load()
    }

    package func remove() throws {
        try store.delete()
        load()
    }

    /// The stored key, read fresh from `store` — for the one call site that
    /// must send it (a fetch). `nil` for "no key" and for "the store could
    /// not be read"; those are the same actionable outcome for a caller about
    /// to build a request (`MaterialsProjectFetchOutcome.noAPIKey`).
    package func currentKey() -> String? {
        (try? store.load()).flatMap { $0.isEmpty ? nil : $0 }
    }
}

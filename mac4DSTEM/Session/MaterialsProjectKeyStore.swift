//
//  MaterialsProjectKeyStore.swift
//  Role: Session S4a's second half — where the Materials Project API key
//        lives between launches. Keychain, not `UserDefaults`
//        (docs/v3-features.md#materials-project: "API key storage —
//        Keychain, not UserDefaults"). A protocol in front of it so the
//        eventual search UI and its tests can swap in an in-memory store
//        without touching the Keychain at all.
//
//  Deliberately no `kSecUseDataProtectionKeychain`: this app is not signed
//  into the data-protection keychain elsewhere, and adding it here would make
//  this one item behave differently from nothing else in the app.
//
//  Every member is `nonisolated`: Keychain calls are synchronous, blocking,
//  thread-agnostic C API — the same shape as the file I/O `Core/` already
//  does off the main actor, and there is no UI or `AppState` dependency here
//  to require otherwise.
//

import Foundation
import Security

/// Where the Materials Project API key is loaded from and saved to. `nil`
/// from `load()` means "no key set" — never a thrown error; a key that
/// exists but cannot be read (a real Keychain failure) throws instead, so
/// the two cases stay distinguishable to the caller.
package nonisolated protocol APIKeyStore {
    func load() throws -> String?
    func save(_ key: String) throws
    func delete() throws
}

/// A process-lifetime store with no persistence — the default in tests, and
/// available to production code as the fallback when the Keychain is
/// unavailable (e.g. `errSecNotAvailable` in a restricted CI environment).
package nonisolated final class InMemoryAPIKeyStore: APIKeyStore, @unchecked Sendable {
    private let lock = NSLock()
    private var storedKey: String?

    package init(initial: String? = nil) {
        self.storedKey = initial
    }

    package func load() throws -> String? {
        lock.lock()
        defer { lock.unlock() }
        return storedKey
    }

    package func save(_ key: String) throws {
        lock.lock()
        defer { lock.unlock() }
        storedKey = key
    }

    package func delete() throws {
        lock.lock()
        defer { lock.unlock() }
        storedKey = nil
    }
}

/// Stores the key as a Keychain generic-password item. `service`/`account`
/// are injectable so tests can round-trip against a throwaway item rather
/// than the app's own real one.
package nonisolated final class KeychainAPIKeyStore: APIKeyStore, @unchecked Sendable {

    /// Every Keychain failure carries the raw `OSStatus` it came from —
    /// named per `CLAUDE.md`'s "no claim a reader cannot reproduce": a
    /// caller (or a test) can look the number up itself rather than trust a
    /// paraphrase of it.
    package enum KeychainFailure: Error, Equatable {
        case unhandled(OSStatus)
    }

    package static let defaultService = "com.mac4dstem.materials-project"
    package static let defaultAccount = "api-key"

    private let service: String
    private let account: String

    package init(service: String = KeychainAPIKeyStore.defaultService,
                 account: String = KeychainAPIKeyStore.defaultAccount) {
        self.service = service
        self.account = account
    }

    private func query() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    package func load() throws -> String? {
        var lookup = query()
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(lookup as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainFailure.unhandled(status) }
        guard let data = result as? Data, let key = String(data: data, encoding: .utf8) else {
            return nil
        }
        return key
    }

    package func save(_ key: String) throws {
        let data = Data(key.utf8)
        let existing = query()
        let probe = SecItemCopyMatching(existing as CFDictionary, nil)

        switch probe {
        case errSecSuccess:
            let status = SecItemUpdate(existing as CFDictionary, [kSecValueData as String: data] as CFDictionary)
            guard status == errSecSuccess else { throw KeychainFailure.unhandled(status) }
        case errSecItemNotFound:
            var attributes = existing
            attributes[kSecValueData as String] = data
            let status = SecItemAdd(attributes as CFDictionary, nil)
            guard status == errSecSuccess else { throw KeychainFailure.unhandled(status) }
        default:
            throw KeychainFailure.unhandled(probe)
        }
    }

    package func delete() throws {
        let status = SecItemDelete(query() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainFailure.unhandled(status)
        }
    }
}

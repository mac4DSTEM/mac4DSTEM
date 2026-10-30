//
//  InMemoryAPIKeyStore.swift
//  The tests' Materials Project key store (moved out of the app: nothing in production uses it).
//

import Foundation
import DSTEMSession
@testable import mac4DSTEM

/// A process-lifetime store with no persistence: the tests' `APIKeyStore`, so no test reads or writes the real Keychain item.
nonisolated final class InMemoryAPIKeyStore: APIKeyStore, @unchecked Sendable {
    private let lock = NSLock()
    private var storedKey: String?

    init(initial: String? = nil) {
        self.storedKey = initial
    }

    func load() throws -> String? {
        lock.lock()
        defer { lock.unlock() }
        return storedKey
    }

    func save(_ key: String) throws {
        lock.lock()
        defer { lock.unlock() }
        storedKey = key
    }

    func delete() throws {
        lock.lock()
        defer { lock.unlock() }
        storedKey = nil
    }
}

//
//  PromotionRun.swift
//  Role: Own the one pending configured open until commit or discard consumes
//        it. The PendingLoad owns its preview/configuration; this owner makes
//        selection and transfer atomic without forwarding state on AppState.
//

import Foundation

@Observable
@MainActor
package final class PromotionRun<Pending: AnyObject> {
    package nonisolated init() {}

    package private(set) var pendingLoad: Pending?

    /// Install the newly configured open and return the displaced one so its
    /// file access and in-flight pattern fetch can be released by the caller.
    @discardableResult
    package func replace(with pendingLoad: Pending) -> Pending? {
        let displaced = self.pendingLoad
        self.pendingLoad = pendingLoad
        return displaced
    }

    /// Transfer ownership exactly once. Cleanup or commit remains the caller's
    /// job because it depends on which path consumed the load.
    package func take() -> Pending? {
        let pending = pendingLoad
        pendingLoad = nil
        return pending
    }
}

//
//  ReplaceUndo.swift
//  Role: Edit > Undo for the three actions that replace or remove work a person made by hand: Import Labels,
//        the Al-Mg-Si preset and the phase minus button (UI audit 2026-10-14, safety). One registration
//        helper, so each action says only what puts it back.
//
//  The window's `UndoManager` comes from SwiftUI (`@Environment(\.undoManager)`), is handed to the action by
//  the view, and is `Foundation`'s: no AppKit here. A nil manager registers nothing (a test, a harness). The
//  target is the window's `AppState`, which lives as long as the window and its manager.
//
//  A registered undo whose state no longer fits (labels of another dataset after a new one was opened in the
//  window) answers false from its closure: nothing is changed and no redo is offered. Undo then redo then undo
//  ... swaps the two closures; the action name stays, so the menu reads "Undo Import Labels" and "Redo Import
//  Labels" in turn.
//

import Foundation

@MainActor
package enum ReplaceUndo {

    /// Registers the inverse of an action that has just happened. `undo` puts the work back and says whether it
    /// did; `redo` does the action again the same way. Both run on the main actor, as `UndoManager` is driven
    /// from the Edit menu.
    package static func register(
        in manager: UndoManager?, target: AnyObject, actionName: String,
        undo: @escaping @MainActor () -> Bool,
        redo: @escaping @MainActor () -> Bool
    ) {
        guard let manager else { return }
        manager.registerUndo(withTarget: target) { [weak manager] _ in
            // AppKit/Foundation call this on the main thread from the Edit menu; the closure type is not
            // actor-isolated, so say so once, here.
            MainActor.assumeIsolated {
                guard undo() else { return }
                // Registered while the manager is undoing, it becomes the redo (and, while redoing, the undo).
                register(in: manager, target: target, actionName: actionName, undo: redo, redo: undo)
            }
        }
        manager.setActionName(actionName)
    }

    /// The common case: two states of one thing. `restore` puts a snapshot back and says whether it could.
    package static func register<Snapshot>(
        in manager: UndoManager?, target: AnyObject, actionName: String,
        before: Snapshot, after: Snapshot,
        restore: @escaping @MainActor (Snapshot) -> Bool
    ) {
        register(in: manager, target: target, actionName: actionName,
                 undo: { restore(before) }, redo: { restore(after) })
    }
}

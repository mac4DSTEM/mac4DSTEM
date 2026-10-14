//
//  DividerNudge.swift
//  Role: the arithmetic of moving a divider without a mouse: one arrow-key press, or one VoiceOver
//        increment/decrement, on the science panes' divider (`PaneSplit`) and on the status strip that is the
//        process area's divider (`StatusBar`). UI audit 2026-10-14, G4: both were drag-only. Pure, so a test holds
//        the clamps; the views only call it.
//

import SwiftUI

enum DividerNudge {

    /// One key press or one VoiceOver step, in points: about a tenth of a narrow pane, enough to see, fine
    /// enough to place a divider in a few presses (the mouse remains the fast way).
    static let step: CGFloat = 24

    /// The science split's new fraction after moving its divider `points` to the right (negative: left),
    /// clamped to the same floor the drag keeps (`smallest`, see `PaneSplit.body`).
    static func paneFraction(from fraction: CGFloat, by points: CGFloat, usable: CGFloat, smallest: CGFloat) -> CGFloat {
        guard usable > 0 else { return fraction }
        let start = min(max(fraction, smallest), 1 - smallest)
        return min(max(start + points / usable, smallest), 1 - smallest)
    }

    /// The process area's new fraction after moving the strip up (`taller`) or down. A shut area opens to where it
    /// was last open on "taller", as the infobar's toggle does, and stays shut on "shorter"; an open one follows the
    /// drag's own rule (`ProcessAreaLayout.fraction(afterDrag:)`: it is capped at the column and held at its
    /// floor) with one difference: a mouse closes it by dragging far below the floor, which a 24-pt step never does,
    /// so "shorter" at the floor closes it.
    static func processFraction(from fraction: Double, taller: Bool, last: Double, available: CGFloat) -> Double {
        if fraction <= 0 {
            return taller ? ProcessAreaLayout.toggled(from: 0, last: last) : 0
        }
        // Half a point of slack: the floor round-trips through a fraction (140 / 800), and a double need not give 140 back exactly.
        if !taller, ProcessAreaLayout.height(fraction: fraction, available: available) <= LayoutPolicy.processAreaMinimumHeight + 0.5 {
            return 0
        }
        return ProcessAreaLayout.fraction(afterDrag: taller ? -step : step, available: available, from: fraction)
    }
}

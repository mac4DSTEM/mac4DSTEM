import SwiftUI

/// The spectrum plot's interaction and styling decisions, pure so a test can hold them (lane L7, the owner's drive findings of
/// 2026-10-07: "zooming in on the spectrum doesn't work yet … it has to feel natural", "the lines are too thin … give them colour").
/// `SpectrumStripView` only applies them.
nonisolated enum SpectrumInteraction {
    // MARK: zoom in the x-axis gutter

    /// Points of rightward drag in the x-axis gutter that double the zoom (the mirror of the y gutter's `yScalePointsPerDoubling`).
    static let pointsPerDoubling = 80.0
    /// One drag's whole zoom factor stays inside this (a drag from the window's edge to its other edge is about 2^7).
    static let factorRange: ClosedRange<Double> = (1.0 / 64)...64

    /// The zoom factor for a drag of `dx` points in the x-axis gutter, cumulative from the drag's start: right (positive) is in
    /// (factor above 1), left is out; 0 is 1. Clamped to `factorRange`; a non-finite `dx` is no drag.
    static func zoomFactor(dx: Double) -> Double {
        guard dx.isFinite else { return 1 }
        let f = pow(2, dx / pointsPerDoubling)
        return min(max(f, factorRange.lowerBound), factorRange.upperBound)
    }

    // MARK: what a drag does

    /// Where a drag begins and which modifier is held decide it. The counts gutter (left of the frame) stretches the counts axis
    /// whatever else is held; the x-axis row (below the frame, at or under `gutterTop`) zooms the energy about the start; in the
    /// frame ⌘ draws a zoom box, ⌥ marks a range (⌘ wins when both are held) and a plain drag pans.
    static func dragMode(optionHeld: Bool, commandHeld: Bool, startX: CGFloat, startY: CGFloat, plotLeft: CGFloat, gutterTop: CGFloat) -> SpectrumDragMode {
        if startX < plotLeft { return .stretchY }
        if startY >= gutterTop { return .zoomX }
        if commandHeld { return .band }
        return optionHeld ? .range : .pan
    }

    // MARK: rubber-band and "Zoom to range"

    /// The smallest window a box or a range can zoom to, in channels.
    static let minimumBandChannels = 10

    /// The energy window a zoom box (or the range marker's "Zoom to") shows: the two energies' span, widened about its centre to
    /// `minimumBandChannels` channels, then shifted to lie inside `domain` (never wider than it). nil when the two energies
    /// are the same (nothing was drawn) or not finite.
    static func bandWindow(from a: Double, to b: Double, domain: ClosedRange<Double>, channel: Double) -> ClosedRange<Double>? {
        guard a.isFinite, b.isFinite, channel > 0, a != b else { return nil }
        let width = domain.upperBound - domain.lowerBound
        let span = min(max(abs(b - a), Double(minimumBandChannels) * channel), width)
        let centre = (a + b) / 2
        var lo = centre - span / 2
        lo = min(max(lo, domain.lowerBound), domain.upperBound - span)
        return lo...(lo + span)
    }

    /// The first row of the right-click menu after an ⌥-drag: "Zoom to 1,20–1,86 keV" (two decimals, the readout's own).
    static func zoomToRangeTitle(from a: Double, to b: Double, locale: Locale = .current) -> String {
        "Zoom to "
            + SpectrumReadout.energy(min(a, b), decimals: 2, locale: locale) + "\u{2013}"
            + SpectrumReadout.energy(max(a, b), decimals: 2, locale: locale) + " keV"
    }

    // MARK: colour

    /// Which spectrum the strip shows: the whole map's, or a region's (a live image with a region other than the whole map selected;
    /// region 0 is the whole map).
    enum CurveRole: Equatable, Sendable { case wholeMap, region }

    static func curveRole(isLive: Bool, selectedRegion: Int?) -> CurveRole {
        guard isLive, let id = selectedRegion, id != 0 else { return .wholeMap }
        return .region
    }

    /// The shown spectrum's curve: a region's in the live region's colour (the map outline's), the whole map's in the label colour.
    /// The whole-map overlay (secondary) and the pins (their tints) are drawn apart.
    static func curveColor(_ role: CurveRole) -> Color {
        switch role {
        case .region: return SpectroscopyRoomModel.liveRegionColor
        case .wholeMap: return Color.primary.opacity(0.85)
        }
    }

    /// The hover readout's energy text: the region curve's colour while a region is shown, else the label colour.
    static func readoutEnergyColor(_ role: CurveRole) -> Color {
        role == .region ? SpectroscopyRoomModel.liveRegionColor : Color.primary
    }

    // MARK: weights, points

    enum Width {
        /// The shown spectrum, the fit's model.
        static let spectrum: CGFloat = 1.6, model: CGFloat = 1.6
        /// A pin's curve, the fit's background.
        static let pin: CGFloat = 1.4, background: CGFloat = 1.4
        /// A line marker; the highlighted element's.
        static let marker: CGFloat = 1.2, markerHighlighted: CGFloat = 2.2
        /// A marker's name.
        static let markerLabel: CGFloat = 11
    }
}

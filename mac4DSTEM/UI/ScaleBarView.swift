//
//  ScaleBarView.swift
//  Role: Calibrated scale bar overlay for the image panes. Picks a "nice"
//        1-2-5 length near a target on-screen size, so it re-quantizes as the
//        user zooms. Falls back to pixel units when no calibration exists —
//        an uncalibrated bar labelled "px" is still honest and useful.
//

import SwiftUI
import DSTEMCore
import DSTEMSession

/// The bottom overlay row of an image pane: the scale bar at the leading edge,
/// the colour legend at the trailing edge.
///
/// Both used to be independent `bottomLeading` / `bottomTrailing` overlays in
/// the same ZStack, each unaware of the other. On a tall, narrow pane there is
/// not enough width for both — a 200x50 scan with a display rotation applied
/// put the `-0.04145 0 0.04145` colorbar straight through the `20 [pix]` scale
/// bar (found on a Track B drive; fixed in v2 S18). The legend is 146pt wide
/// before its label, and the bar is quantized to ~70pt of *drawn* length plus
/// its own caption, so the collision is a property of the width of the **drawn
/// image box** — `fitted(in:aspect:)`, which this overlay sits inside — and NOT
/// of the pane. For a square pattern in a pane taller than it is wide the two
/// coincide; for a rotated tall-narrow scan the box stays narrow at any divider
/// position, so that pane is stacked always and correctly. (An earlier version
/// of this comment said "a property of the pane's width, not of any one
/// dataset". Both halves were wrong, and Track B row F1.32 inherited the error
/// from here — Gate A, 2026-08-27.)
///
/// `ViewThatFits` picks side-by-side while both ideal widths fit the pane and
/// stacks them otherwise, which keeps the wide case pixel-identical to what
/// shipped and makes the narrow case legible instead of overlapping.
struct PaneBottomOverlay<Leading: View, Trailing: View>: View {
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .bottom, spacing: 8) {
                leading
                Spacer(minLength: 8)
                trailing
            }
            // Legend above bar: the legend is the taller, fixed-width block, so
            // stacking it on top keeps the bar against the pane's bottom-left
            // corner where it sits in the wide case.
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 0) { Spacer(minLength: 0); trailing }
                leading
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }
}

struct ScaleBarView: View {
    /// Physical units per screen POINT at the current zoom
    /// (= pixelSize * imagePixels / (fittedWidthPoints * zoom)).
    let unitsPerPoint: Double
    /// Unit label ("nm", "1/nm", "px", …).
    let unitLabel: String

    private static let targetPoints = 70.0

    var body: some View {
        if unitsPerPoint > 0, unitsPerPoint.isFinite {
            let nice = Self.nice125(unitsPerPoint * Self.targetPoints)
            let lengthPt = CGFloat(nice / unitsPerPoint)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(Self.format(nice)) \(unitLabel)")
                Rectangle()
                    .frame(width: lengthPt, height: 2)
            }
            .font(.caption2.monospaced())
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 4))
            .allowsHitTesting(false)
        }
    }

    /// Round to the nearest 1 / 2 / 5 × 10ⁿ.
    static func nice125(_ value: Double) -> Double {
        guard value > 0, value.isFinite else { return 1 }
        let exponent = floor(log10(value))
        let base = pow(10, exponent)
        let mantissa = value / base
        let nice: Double = mantissa < 1.5 ? 1 : (mantissa < 3.5 ? 2 : (mantissa < 7.5 ? 5 : 10))
        return nice * base
    }

    static func format(_ value: Double) -> String {
        if value >= 10 { return String(format: "%.0f", value) }
        if value >= 1 { return String(format: "%g", value) }
        return String(format: "%.3g", value)
    }
}

/// Numeric scalar legend for the exact colormap and contrast window displayed
/// by a pane. Pre-colored scientific images use their own directional keys.
struct ScalarColorbarView: View {
    let colormap: ColormapKind
    let low: Double
    let high: Double
    let unitLabel: String
    var gamma: Float = 1
    var marksZero = false
    /// True when the displayed image contains masked (no-data) pixels, which
    /// render as neutral gray; adds a swatch so the gray is self-explanatory.
    var showsMasked = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Canvas { context, size in
                let lut = Colormaps.lutRGBA(colormap, count: 128)
                let stripWidth = size.width / 128
                for index in 0..<128 {
                    let fraction = Float(index) / 127
                    let mapped = pow(fraction, 1 / max(gamma, 0.05))
                    let lutIndex = min(127, Int((mapped * 127).rounded()))
                    let offset = lutIndex * 4
                    let color = Color(
                        red: Double(lut[offset]) / 255,
                        green: Double(lut[offset + 1]) / 255,
                        blue: Double(lut[offset + 2]) / 255
                    )
                    context.fill(Path(CGRect(x: CGFloat(index) * stripWidth, y: 0,
                                             width: stripWidth + 0.5, height: size.height)),
                                 with: .color(color))
                }
                if marksZero, low < 0, high > 0 {
                    let fraction = CGFloat(-low / (high - low))
                    let x = fraction * size.width
                    context.stroke(Path { path in
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: size.height))
                    }, with: .color(.white), lineWidth: 1)
                }
            }
            .frame(width: 132, height: 9)
            .overlay(RoundedRectangle(cornerRadius: 1)
                .stroke(Color.white.opacity(0.45), lineWidth: 0.5))

            HStack(spacing: 4) {
                Text(Self.format(low))
                Spacer()
                if marksZero, low < 0, high > 0 { Text("0") }
                Spacer()
                Text(Self.format(high))
            }
            .frame(width: 132)
            if !unitLabel.isEmpty {
                Text(unitLabel)
                    .foregroundStyle(.white.opacity(0.75))
            }
            if showsMasked {
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color(red: 0.32, green: 0.32, blue: 0.34))
                        .frame(width: 10, height: 7)
                        .overlay(RoundedRectangle(cornerRadius: 1)
                            .stroke(Color.white.opacity(0.45), lineWidth: 0.5))
                    Text("masked · no fit")
                        .foregroundStyle(.white.opacity(0.75))
                }
            }
        }
        .font(.caption2.monospacedDigit())
        .foregroundStyle(.white)
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(Color.black.opacity(0.48), in: RoundedRectangle(cornerRadius: 4))
        // R23 (2026-09-02, diagnosed live): this view is the LABEL of
        // `ColormapChipMenu`'s button. `.allowsHitTesting(false)` here made the
        // button's whole area transparent to real clicks — AXPress opened the
        // popover, a click inside the button's own 146×51 pt frame did not.
        // Plain (non-button) uses opt out at their call site instead.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Color scale from \(Self.format(low)) to \(Self.format(high)) \(unitLabel)"
                            + (showsMasked ? ", gray marks masked pixels with no fit" : ""))
    }

    private static func format(_ value: Double) -> String {
        guard value.isFinite else { return "—" }
        if value == 0 { return "0" }
        let magnitude = abs(value)
        if magnitude >= 10_000 || magnitude < 0.001 {
            return String(format: "%.2e", value)
        }
        return String(format: "%.4g", value)
    }
}

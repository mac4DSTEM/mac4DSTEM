import Foundation
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
import DSTEMSession
#endif

/// A virtual-detector value typed into the Imaging inspector (UI audit 2026-10-14, "Aperture is drag-only"): the drag's own rules
/// applied to a typed number, so a typed aperture and a dragged one can never disagree.
///
/// The edit goes through `Aperture.snappedEdit`, the chokepoint every handle drag uses (whole-pixel radii; a centre snapped and
/// clamped only when it was actually changed, so a typed radius never re-rounds a fractional fitted centre and never discards
/// the fitted origin), then `AppState.updateAperture` and `commitApertureChange`, the same two calls a drag makes per tick and at
/// its end.
enum ApertureEntry {
    enum Field: Hashable {
        case centerX, centerY, inner, outer
    }

    /// The fields the shape has, in row order. A point detector is one pixel at its centre; a circle's `outer` is its radius, a
    /// rectangle's `outer` is its half-extent (the mask kernel's rule, `ApertureOverlay`).
    static func fields(for shape: VirtualShapeMode) -> [Field] {
        switch shape {
        case .point: [.centerX, .centerY]
        case .circle, .rectangle: [.centerX, .centerY, .outer]
        case .annulus: [.centerX, .centerY, .inner, .outer]
        }
    }

    /// The aperture a typed value gives, or nil when nothing changes (a non-number, or the value the aperture already has).
    /// Radii keep the drag's order (`inner` within 0...`outer`; `outer` at least 1 and at least `inner`) and the accessible
    /// slider's upper bound, the larger detector side.
    static func edited(
        _ aperture: Aperture, field: Field, to typed: Double,
        patternWidth: Int, patternHeight: Int
    ) -> Aperture? {
        guard typed.isFinite, patternWidth > 0, patternHeight > 0 else { return nil }
        var raw = aperture
        let value = Float(typed)
        switch field {
        case .centerX: raw.centerX = value
        case .centerY: raw.centerY = value
        case .inner: raw.inner = max(0, min(value, aperture.outer))
        case .outer: raw.outer = min(max(value, max(1, aperture.inner)), Float(max(patternWidth, patternHeight)))
        }
        let snapped = raw.snappedEdit(from: aperture, patternWidth: patternWidth, patternHeight: patternHeight)
        return snapped == aperture ? nil : snapped
    }

    /// Commit a typed value as a drag would: store it (live image update, a changed centre sets the fitted origin aside,
    /// recoverably) and run the final pass. False when the value changed nothing.
    @MainActor
    @discardableResult
    static func apply(
        _ typed: Double, to field: Field, in state: AppState, patternWidth: Int, patternHeight: Int
    ) -> Bool {
        guard let next = edited(state.aperture, field: field, to: typed,
                                patternWidth: patternWidth, patternHeight: patternHeight) else { return false }
        state.updateAperture(next)
        state.commitApertureChange()
        return true
    }

    /// The stepper's range for a field: the pixels of the detector for a centre, and the drag's order for the radii.
    static func range(of field: Field, in aperture: Aperture, patternWidth: Int, patternHeight: Int) -> ClosedRange<Double> {
        switch field {
        case .centerX: 0...Double(max(0, patternWidth - 1))
        case .centerY: 0...Double(max(0, patternHeight - 1))
        case .inner: 0...Double(max(0, aperture.outer))
        case .outer: max(1, Double(aperture.inner))...Double(max(1, max(patternWidth, patternHeight)))
        }
    }

    static func value(of field: Field, in aperture: Aperture) -> Double {
        switch field {
        case .centerX: Double(aperture.centerX)
        case .centerY: Double(aperture.centerY)
        case .inner: Double(aperture.inner)
        case .outer: Double(aperture.outer)
        }
    }

    /// The row's label, and the spoken name of its field.
    static func label(for field: Field, shape: VirtualShapeMode) -> String {
        switch field {
        case .centerX: "Center x"
        case .centerY: "Center y"
        case .inner: "Inner radius"
        case .outer: shape == .rectangle ? "Half-width" : (shape == .circle ? "Radius" : "Outer radius")
        }
    }

    static func spokenName(for field: Field, shape: VirtualShapeMode) -> String {
        "Aperture " + label(for: field, shape: shape).lowercased() + " in pixels"
    }
}

import SwiftUI

/// Zoom and pan for a scientific image pane — pure SwiftUI.
///
/// UI deliberately drops the AppKit scroll-wheel monitor the old panes
/// installed (`NSEvent.addLocalMonitorForEvents`, application-wide, which
/// swallowed scrolls for the whole app whenever a pane's hover never
/// reported `.ended`). `MagnifyGesture` covers trackpads, and macOS
/// synthesises magnification from a mouse wheel with the modifier, so the
/// monitor bought one input at the cost of a global event trap.
///
/// The clamp is the science-relevant part and is kept verbatim in behaviour:
/// the display shader samples a `1/zoom`-wide UV window centred at
/// `0.5 + offset/viewSize`, so the window stays inside the image exactly
/// while `|offset| <= size * (1 - 1/zoom) / 2` per axis. Panning can
/// therefore never push the image out of its own pane.
struct ZoomPan: Equatable {
    var zoom: CGFloat = 1
    var offset: CGSize = .zero

    /// In-flight gesture accumulators, committed on `.onEnded`.
    var liveZoom: CGFloat = 1
    var liveOffset: CGSize = .zero

    static let minimumZoom: CGFloat = 0.25
    static let maximumZoom: CGFloat = 64

    var effectiveZoom: CGFloat { zoom * liveZoom }
    var effectiveOffset: CGSize {
        CGSize(width: offset.width + liveOffset.width,
               height: offset.height + liveOffset.height)
    }

    /// The zoom actually handed to a `scaleEffect`, floored so a pane can
    /// never collapse to nothing.
    var drawZoom: CGFloat { max(Self.minimumZoom, effectiveZoom) }

    mutating func reset() { self = ZoomPan() }

    static func clampZoom(_ zoom: CGFloat) -> CGFloat {
        min(maximumZoom, max(minimumZoom, zoom))
    }

    /// One step of the VoiceOver / keyboard-free zoom actions: a factor of 2
    /// per step, through the same clamp as a pinch (`clampZoom`, then the pan
    /// is pulled back inside the pane as `.onEnded` does).
    static let accessibilityStepFactor: CGFloat = 2

    mutating func step(by factor: CGFloat, in box: CGSize) {
        zoom = Self.clampZoom(zoom * factor)
        offset = Self.clampedOffset(offset, zoom: zoom, in: box)
    }

    /// Pure, so the rule itself is unit-testable without a view.
    static func clampedOffset(
        _ proposed: CGSize, zoom: CGFloat, in size: CGSize
    ) -> CGSize {
        guard zoom > 1, size.width > 0, size.height > 0 else { return .zero }
        let fraction = (1 - 1 / zoom) / 2
        let maxX = size.width * fraction
        let maxY = size.height * fraction
        return CGSize(width: min(max(proposed.width, -maxX), maxX),
                      height: min(max(proposed.height, -maxY), maxY))
    }
}

private struct ZoomPanModifier: ViewModifier {
    @Binding var state: ZoomPan
    /// The drawn image's box — the clamp is expressed against the pixels,
    /// not against whatever the container happens to be.
    let box: CGSize

    func body(content: Content) -> some View {
        content
            .gesture(
                SimultaneousGesture(
                    MagnifyGesture()
                        .onChanged { value in
                            // Skip a write that changes nothing: each one
                            // re-evaluates the pane.
                            if state.liveZoom != value.magnification {
                                state.liveZoom = value.magnification
                            }
                        }
                        .onEnded { value in
                            state.zoom = ZoomPan.clampZoom(state.zoom * value.magnification)
                            state.liveZoom = 1
                            // Zooming out while panned pulls the image back
                            // inside the pane.
                            state.offset = ZoomPan.clampedOffset(
                                state.offset, zoom: state.zoom, in: box
                            )
                        },
                    DragGesture()
                        .onChanged { value in
                            let proposed = CGSize(
                                width: state.offset.width + value.translation.width,
                                height: state.offset.height + value.translation.height
                            )
                            // Live clamp, so the drag stops at the edge
                            // rather than rubber-banding past it.
                            let allowed = ZoomPan.clampedOffset(
                                proposed, zoom: state.effectiveZoom, in: box
                            )
                            let live = CGSize(
                                width: allowed.width - state.offset.width,
                                height: allowed.height - state.offset.height
                            )
                            // Pinned at an edge the drag keeps reporting the
                            // same clamped value; do not re-publish it.
                            if state.liveOffset != live { state.liveOffset = live }
                        }
                        .onEnded { value in
                            let proposed = CGSize(
                                width: state.offset.width + value.translation.width,
                                height: state.offset.height + value.translation.height
                            )
                            state.offset = ZoomPan.clampedOffset(
                                proposed, zoom: state.zoom, in: box
                            )
                            state.liveOffset = .zero
                        }
                )
            )
            .onTapGesture(count: 2) {
                resetZoom(state: &state, reduceMotion: reduceMotion)
            }
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
}

/// Reset, animated only when the reader has not asked for Reduce Motion.
@MainActor
private func resetZoom(state: inout ZoomPan, reduceMotion: Bool) {
    if reduceMotion {
        state.reset()
    } else {
        withAnimation(.snappy) { state.reset() }
    }
}

/// The zoom gestures' accessible twins: pinch, drag-to-pan-only and
/// double-click gave VoiceOver and Switch Control users no way to zoom or to
/// reset. Applied to the pane's accessibility container, where the actions are
/// listed (review 2026-10-07, F5). Nothing is drawn.
private struct ZoomPanAccessibilityActions: ViewModifier {
    @Binding var state: ZoomPan
    let box: CGSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .accessibilityAction(named: "Zoom in") {
                state.step(by: ZoomPan.accessibilityStepFactor, in: box)
            }
            .accessibilityAction(named: "Zoom out") {
                state.step(by: 1 / ZoomPan.accessibilityStepFactor, in: box)
            }
            .accessibilityAction(named: "Reset zoom") {
                resetZoom(state: &state, reduceMotion: reduceMotion)
            }
    }
}

extension View {
    /// "Zoom in", "Zoom out" and "Reset zoom" as accessibility actions, for the
    /// same `state` and `box` the pane's `.zoomPan` uses.
    func zoomPanAccessibilityActions(_ state: Binding<ZoomPan>, box: CGSize) -> some View {
        modifier(ZoomPanAccessibilityActions(state: state, box: box))
    }

    /// Pinch to zoom, drag to pan, double-click to reset. `box` is the
    /// drawn image's size, which is what the pan clamp is measured against.
    func zoomPan(_ state: Binding<ZoomPan>, box: CGSize) -> some View {
        modifier(ZoomPanModifier(state: state, box: box))
    }
}

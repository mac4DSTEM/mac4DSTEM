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

    var isZoomedIn: Bool { effectiveZoom > 1.01 }

    mutating func reset() { self = ZoomPan() }

    static func clampZoom(_ zoom: CGFloat) -> CGFloat {
        min(maximumZoom, max(minimumZoom, zoom))
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
                        .onChanged { state.liveZoom = $0.magnification }
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
                            state.liveOffset = CGSize(
                                width: allowed.width - state.offset.width,
                                height: allowed.height - state.offset.height
                            )
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
                withAnimation(.snappy) { state.reset() }
            }
    }
}

extension View {
    /// Pinch to zoom, drag to pan, double-click to reset. `box` is the
    /// drawn image's size, which is what the pan clamp is measured against.
    func zoomPan(_ state: Binding<ZoomPan>, box: CGSize) -> some View {
        modifier(ZoomPanModifier(state: state, box: box))
    }
}

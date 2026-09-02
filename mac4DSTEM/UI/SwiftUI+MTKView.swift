//
//  SwiftUI+MTKView.swift
//  Role: Shared SwiftUI helpers for the Metal-backed viewers. The actual
//        NSViewRepresentable lives in MetalImageView.swift; this file holds the
//        reusable zoom/pan gesture plumbing so DiffractionView and StemImageView
//        don't each reinvent it.
//

import AppKit
import DSTEMCore
import SwiftUI

/// Bundles the live zoom/pan state for an image viewer.
struct ZoomPanState: Equatable {
    var zoom: CGFloat = 1
    var offset: CGSize = .zero

    // In-progress gesture accumulators (committed on .onEnded).
    var liveZoom: CGFloat = 1
    var liveOffset: CGSize = .zero

    var effectiveZoom: CGFloat { zoom * liveZoom }
    var effectiveOffset: CGSize {
        CGSize(width: offset.width + liveOffset.width,
               height: offset.height + liveOffset.height)
    }

    mutating func reset() { self = ZoomPanState() }

    /// R16 (owner, 2026-09-01): panning must never push the image out of the
    /// pane. The display shader samples a 1/zoom-wide UV window centred at
    /// 0.5 + offset/viewSize (`Colormaps.metal:33`), so the window stays
    /// inside the image exactly while |offset| ≤ size·(1 − 1/zoom)/2 per
    /// axis — 0 at 1× and below (the image fits; a plain click scrubs there
    /// anyway, backlog #35), edge-to-edge but not beyond when zoomed in.
    /// Pure, so the rule itself is unit-pinned.
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

/// Attaches magnify-to-zoom, drag-to-pan, scroll-to-zoom/pan and
/// double-click-to-reset gestures that drive a `ZoomPanState`.
///
/// **Pointer conventions** (added 2026-08-05 — a mouse could not zoom at all,
/// because `MagnificationGesture` is a trackpad pinch and nothing handled the
/// scroll wheel):
///
/// | Input | Action |
/// |---|---|
/// | Pinch (trackpad) | zoom |
/// | Drag | pan |
/// | Scroll wheel (mouse, coarse deltas) | zoom |
/// | Two-finger scroll (trackpad, precise deltas) | pan |
/// | Double-click | reset this pane |
///
/// Splitting on `hasPreciseScrollingDeltas` is what lets one handler serve
/// both devices: a wheel has no way to pan, and a trackpad already has pinch
/// for zoom, so each device gets the gesture it lacks.
///
/// **Scoping the monitor (#38, fixed v2 S18).** `addLocalMonitorForEvents` is
/// APPLICATION-wide: while installed it sees every scroll in every window and,
/// by returning nil, swallows it. Hover was the only thing deciding whether it
/// was installed, and hover is not a reliable exit signal — another window
/// coming forward, a sheet opening over the pane, Mission Control, or a fast
/// exit can all leave `.onContinuousHover` never reporting `.ended`. A pane
/// left in that state ate the scroll wheel for the whole app: the sidebar and
/// every inspector list stopped scrolling until the pane was hovered and left
/// again.
///
/// The authority is now geometry, asked at EVENT time rather than remembered
/// from a hover callback: the monitor consumes a scroll only when it landed
/// inside this pane's own visible rectangle in this pane's own window, and
/// returns everything else untouched. Hover still gates installation, but a
/// monitor that outlives its hover is now inert instead of destructive.
struct ZoomPanModifier: ViewModifier {
    @Binding var state: ZoomPanState
    @State private var scrollMonitor: Any?
    @State private var pane = PaneViewBox()

    private static let minimumZoom: CGFloat = 0.25
    private static let maximumZoom: CGFloat = 64

    func body(content: Content) -> some View {
        content
            .background(PaneGeometryProbe(box: pane))
            .gesture(
                SimultaneousGesture(
                    MagnificationGesture()
                        .onChanged { state.liveZoom = $0 }
                        .onEnded {
                            state.zoom = clamp(state.zoom * $0)
                            state.liveZoom = 1
                            // Zooming OUT while panned must pull the image
                            // back inside the pane (R16).
                            state.offset = clampPan(state.offset, zoom: state.zoom)
                        },
                    DragGesture()
                        .onChanged {
                            // Live clamp, so the drag stops at the edge
                            // instead of rubber-banding past it (R16).
                            let proposed = CGSize(
                                width: state.offset.width + $0.translation.width,
                                height: state.offset.height + $0.translation.height
                            )
                            let allowed = clampPan(proposed, zoom: state.effectiveZoom)
                            state.liveOffset = CGSize(
                                width: allowed.width - state.offset.width,
                                height: allowed.height - state.offset.height
                            )
                        }
                        .onEnded {
                            let proposed = CGSize(
                                width: state.offset.width + $0.translation.width,
                                height: state.offset.height + $0.translation.height
                            )
                            state.offset = clampPan(proposed, zoom: state.zoom)
                            state.liveOffset = .zero
                        }
                )
            )
            // Double-click resets the view.
            .onTapGesture(count: 2) { state.reset() }
            // Hover gates INSTALLATION; `scrollLanded(on:)` decides what the
            // installed monitor is allowed to claim. Two viewers therefore
            // never fight over one wheel even if both monitors are live.
            .onContinuousHover { phase in
                switch phase {
                case .active: installScrollMonitor()
                case .ended: removeScrollMonitor()
                }
            }
            .onDisappear { removeScrollMonitor() }
    }

    private func clamp(_ zoom: CGFloat) -> CGFloat {
        min(Self.maximumZoom, max(Self.minimumZoom, zoom))
    }

    /// R16: the pane's own bounds are the drawn image's frame (the MTKView is
    /// aspect-fitted before this modifier attaches), so the pure rule applies
    /// directly. Before geometry exists, leave the offset alone.
    private func clampPan(_ proposed: CGSize, zoom: CGFloat) -> CGSize {
        guard let size = pane.view?.bounds.size else { return proposed }
        return ZoomPanState.clampedOffset(proposed, zoom: zoom, in: size)
    }

    private func installScrollMonitor() {
        guard scrollMonitor == nil else { return }
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            guard scrollLanded(on: event) else { return event }
            if event.hasPreciseScrollingDeltas {
                state.offset = clampPan(
                    CGSize(width: state.offset.width + event.scrollingDeltaX,
                           height: state.offset.height + event.scrollingDeltaY),
                    zoom: state.zoom
                )
            } else {
                // A wheel notch is ~1 line; keep it gentle and multiplicative
                // so zooming feels the same at every magnification.
                state.zoom = clamp(state.zoom * (1 + event.scrollingDeltaY * 0.05))
                state.offset = clampPan(state.offset, zoom: state.zoom)
            }
            return nil   // consumed — don't let it scroll the sidebar behind
        }
    }

    /// Whether `event` actually landed on this pane.
    ///
    /// `visibleRect`, not `bounds`: a pane scrolled half out of an enclosing
    /// scroll view must not claim scrolls over the part of itself that is
    /// clipped away — otherwise it fights the very scroll view that is hiding
    /// it. A sheet or popover is its own window, so the window comparison
    /// covers those without a special case.
    private func scrollLanded(on event: NSEvent) -> Bool {
        guard let view = pane.view, let window = view.window,
              event.window === window else { return false }
        return view.visibleRect.contains(view.convert(event.locationInWindow, from: nil))
    }

    private func removeScrollMonitor() {
        if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor) }
        scrollMonitor = nil
    }
}

/// Holds the AppKit view backing one pane, so the scroll monitor can ask where
/// an event landed instead of trusting a remembered hover state.
@MainActor final class PaneViewBox {
    weak var view: NSView?
}

/// A zero-cost backing view whose only job is to have a frame and a window.
///
/// `hitTest` returns nil unconditionally: this sits behind the pane's real
/// content and must never take a click, a drag or a cursor away from it. Scroll
/// wheel events are read through the local monitor, not the responder chain, so
/// opting out of hit testing costs nothing here.
private struct PaneGeometryProbe: NSViewRepresentable {
    let box: PaneViewBox

    final class PassthroughView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }

    func makeNSView(context: Context) -> PassthroughView {
        let view = PassthroughView(frame: .zero)
        box.view = view
        return view
    }

    func updateNSView(_ nsView: PassthroughView, context: Context) {
        box.view = nsView
    }
}

extension View {
    func zoomPan(_ state: Binding<ZoomPanState>) -> some View {
        modifier(ZoomPanModifier(state: state))
    }
}

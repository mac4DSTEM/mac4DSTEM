//
//  SwiftUI+MTKView.swift
//  Role: Shared SwiftUI helpers for the Metal-backed viewers. The actual
//        NSViewRepresentable lives in MetalImageView.swift; this file holds the
//        reusable zoom/pan gesture plumbing so DiffractionView and StemImageView
//        don't each reinvent it.
//

import AppKit
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
                        },
                    DragGesture()
                        .onChanged { state.liveOffset = $0.translation }
                        .onEnded {
                            state.offset.width += $0.translation.width
                            state.offset.height += $0.translation.height
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

    private func installScrollMonitor() {
        guard scrollMonitor == nil else { return }
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            guard scrollLanded(on: event) else { return event }
            if event.hasPreciseScrollingDeltas {
                state.offset.width += event.scrollingDeltaX
                state.offset.height += event.scrollingDeltaY
            } else {
                // A wheel notch is ~1 line; keep it gentle and multiplicative
                // so zooming feels the same at every magnification.
                state.zoom = clamp(state.zoom * (1 + event.scrollingDeltaY * 0.05))
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

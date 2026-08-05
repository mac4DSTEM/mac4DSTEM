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
struct ZoomPanModifier: ViewModifier {
    @Binding var state: ZoomPanState
    @State private var scrollMonitor: Any?

    private static let minimumZoom: CGFloat = 0.25
    private static let maximumZoom: CGFloat = 64

    func body(content: Content) -> some View {
        content
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
            // Scroll events are only claimed while the pointer is actually over
            // this pane, so the two viewers never fight over one wheel.
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

    private func removeScrollMonitor() {
        if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor) }
        scrollMonitor = nil
    }
}

extension View {
    func zoomPan(_ state: Binding<ZoomPanState>) -> some View {
        modifier(ZoomPanModifier(state: state))
    }
}

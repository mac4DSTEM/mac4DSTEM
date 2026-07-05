//
//  SwiftUI+MTKView.swift
//  Role: Shared SwiftUI helpers for the Metal-backed viewers. The actual
//        NSViewRepresentable lives in MetalImageView.swift; this file holds the
//        reusable zoom/pan gesture plumbing so DiffractionView and StemImageView
//        don't each reinvent it.
//

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

/// Attaches magnify-to-zoom and drag-to-pan gestures that drive a ZoomPanState.
struct ZoomPanModifier: ViewModifier {
    @Binding var state: ZoomPanState

    func body(content: Content) -> some View {
        content
            .gesture(
                SimultaneousGesture(
                    MagnificationGesture()
                        .onChanged { state.liveZoom = $0 }
                        .onEnded {
                            state.zoom = max(0.1, state.zoom * $0)
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
    }
}

extension View {
    func zoomPan(_ state: Binding<ZoomPanState>) -> some View {
        modifier(ZoomPanModifier(state: state))
    }
}

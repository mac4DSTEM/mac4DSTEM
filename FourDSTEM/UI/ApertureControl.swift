//
//  ApertureControl.swift
//  Role: The interactive annular aperture drawn on top of the CBED viewer.
//        The user drags the center to reposition the detector, and two ring
//        handles to set the inner and outer radii. All values are in detector
//        pixels and reported back through callbacks.
//
//  COORDINATE MAPPING: the overlay is laid out over the square image area.
//  Detector pixel (px, py) maps to view point (px·scaleX, py·scaleY), where
//  scaleX = viewW / Qx and scaleY = viewH / Qy. For radii we use the average
//  scale (CBED patterns are essentially square, so scaleX ≈ scaleY).
//

import SwiftUI

struct ApertureControl: View {

    let aperture: Aperture
    let patternWidth: Int      // Qx
    let patternHeight: Int     // Qy
    var onEdited: (Aperture) -> Void
    var onCommit: () -> Void

    var body: some View {
        GeometryReader { geo in
            let sx = geo.size.width  / CGFloat(max(patternWidth, 1))
            let sy = geo.size.height / CGFloat(max(patternHeight, 1))
            let s  = (sx + sy) / 2                                  // avg scale
            let center = CGPoint(x: CGFloat(aperture.centerX) * sx,
                                 y: CGFloat(aperture.centerY) * sy)
            let innerR = CGFloat(aperture.inner) * s
            let outerR = CGFloat(aperture.outer) * s

            ZStack {
                // Outer ring
                Circle()
                    .stroke(Color.yellow.opacity(0.9), lineWidth: 1.5)
                    .frame(width: outerR * 2, height: outerR * 2)
                    .position(center)

                // Inner ring (only meaningful when inner > 0)
                Circle()
                    .stroke(Color.cyan.opacity(0.9),
                            style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    .frame(width: innerR * 2, height: innerR * 2)
                    .position(center)
                    .opacity(aperture.inner > 0 ? 1 : 0.35)

                // Center handle — drag to move the whole aperture.
                handle(color: .white)
                    .position(center)
                    .gesture(
                        DragGesture(coordinateSpace: .local)
                            .onChanged { v in
                                var a = aperture
                                a.centerX = Float(min(max(0, v.location.x / sx),
                                                      CGFloat(patternWidth)))
                                a.centerY = Float(min(max(0, v.location.y / sy),
                                                      CGFloat(patternHeight)))
                                onEdited(a)
                            }
                            .onEnded { _ in onCommit() }
                    )

                // Outer-radius handle (sits at 3 o'clock on the outer ring).
                handle(color: .yellow)
                    .position(x: center.x + outerR, y: center.y)
                    .gesture(radiusDrag(center: center, scale: s, isInner: false))

                // Inner-radius handle (3 o'clock on the inner ring).
                handle(color: .cyan)
                    .position(x: center.x + innerR, y: center.y)
                    .gesture(radiusDrag(center: center, scale: s, isInner: true))
            }
            .contentShape(Rectangle())
        }
    }

    // MARK: Handles

    private func handle(color: Color) -> some View {
        Circle()
            .fill(color)
            .frame(width: 12, height: 12)
            .overlay(Circle().stroke(Color.black.opacity(0.6), lineWidth: 1))
            .shadow(radius: 1)
    }

    private func radiusDrag(center: CGPoint, scale: CGFloat, isInner: Bool) -> some Gesture {
        DragGesture(coordinateSpace: .local)
            .onChanged { v in
                let dx = v.location.x - center.x
                let dy = v.location.y - center.y
                let rPx = Float(hypot(dx, dy) / scale)
                var a = aperture
                if isInner {
                    a.inner = max(0, min(rPx, a.outer))         // inner ≤ outer
                } else {
                    a.outer = max(a.inner, rPx)                 // outer ≥ inner
                }
                onEdited(a)
            }
            .onEnded { _ in onCommit() }
    }
}

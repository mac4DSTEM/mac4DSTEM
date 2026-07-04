import SwiftUI

struct ApertureControl: View {
    let aperture: Aperture
    let patternWidth: Int
    let patternHeight: Int
    var onEdited: (Aperture) -> Void
    var onCommit: () -> Void

    var body: some View {
        GeometryReader { geometry in
            let scaleX = geometry.size.width / CGFloat(max(patternWidth, 1))
            let scaleY = geometry.size.height / CGFloat(max(patternHeight, 1))
            let radiusScale = (scaleX + scaleY) / 2
            let center = CGPoint(
                x: CGFloat(aperture.centerX) * scaleX,
                y: CGFloat(aperture.centerY) * scaleY
            )
            let innerRadius = CGFloat(aperture.inner) * radiusScale
            let outerRadius = CGFloat(aperture.outer) * radiusScale

            ZStack {
                Circle()
                    .stroke(Color.yellow.opacity(0.9), lineWidth: 1.5)
                    .frame(width: outerRadius * 2, height: outerRadius * 2)
                    .position(center)

                Circle()
                    .stroke(Color.cyan.opacity(0.9), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    .frame(width: innerRadius * 2, height: innerRadius * 2)
                    .position(center)
                    .opacity(aperture.inner > 0 ? 1 : 0.35)

                handle(color: .white)
                    .position(center)
                    .gesture(
                        DragGesture(coordinateSpace: .local)
                            .onChanged { value in
                                var updated = aperture
                                updated.centerX = Float(min(max(0, value.location.x / scaleX), CGFloat(patternWidth)))
                                updated.centerY = Float(min(max(0, value.location.y / scaleY), CGFloat(patternHeight)))
                                onEdited(updated)
                            }
                            .onEnded { _ in onCommit() }
                    )

                handle(color: .yellow)
                    .position(x: center.x + outerRadius, y: center.y)
                    .gesture(radiusDrag(center: center, scale: radiusScale, isInner: false))

                handle(color: .cyan)
                    .position(x: center.x + innerRadius, y: center.y)
                    .gesture(radiusDrag(center: center, scale: radiusScale, isInner: true))
            }
            .contentShape(Rectangle())
        }
    }

    private func handle(color: Color) -> some View {
        Circle()
            .fill(color)
            .frame(width: 12, height: 12)
            .overlay(Circle().stroke(Color.black.opacity(0.6), lineWidth: 1))
            .shadow(radius: 1)
    }

    private func radiusDrag(center: CGPoint, scale: CGFloat, isInner: Bool) -> some Gesture {
        DragGesture(coordinateSpace: .local)
            .onChanged { value in
                let dx = value.location.x - center.x
                let dy = value.location.y - center.y
                let radius = Float(hypot(dx, dy) / scale)
                var updated = aperture

                if isInner {
                    updated.inner = max(0, min(radius, updated.outer))
                } else {
                    updated.outer = max(updated.inner, radius)
                }

                onEdited(updated)
            }
            .onEnded { _ in onCommit() }
    }
}

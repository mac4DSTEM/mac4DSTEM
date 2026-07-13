import SwiftUI

/// Interactive detector overlay on the CBED view. Renders and lets you drag the
/// active virtual-detector geometry: an annulus (inner/outer radius), a square
/// (half-extent = outer), or a single point. The shape matches the selected
/// `VirtualShapeMode` so what you see is what the kernel integrates.
struct ApertureControl: View {
    let aperture: Aperture
    let shape: VirtualShapeMode
    let patternWidth: Int
    let patternHeight: Int
    var onEdited: (Aperture) -> Void
    var onCommit: () -> Void

    var body: some View {
        GeometryReader { geometry in
            let scaleX = geometry.size.width / CGFloat(max(patternWidth, 1))
            let scaleY = geometry.size.height / CGFloat(max(patternHeight, 1))
            let radiusScale = (scaleX + scaleY) / 2
            let center = CGPoint(x: CGFloat(aperture.centerX) * scaleX,
                                 y: CGFloat(aperture.centerY) * scaleY)

            ZStack {
                switch shape {
                case .circle:    circle(center: center, scaleX: scaleX, scaleY: scaleY, radiusScale: radiusScale)
                case .annulus:   annulus(center: center, scaleX: scaleX, scaleY: scaleY, radiusScale: radiusScale)
                case .rectangle: rectangle(center: center, scaleX: scaleX, scaleY: scaleY, radiusScale: radiusScale)
                case .point:     point(center: center, scaleX: scaleX, scaleY: scaleY)
                }
            }
            .contentShape(Rectangle())
        }
    }

    // MARK: Shapes

    @ViewBuilder
    private func circle(center: CGPoint, scaleX: CGFloat, scaleY: CGFloat, radiusScale: CGFloat) -> some View {
        let outer = CGFloat(aperture.outer) * radiusScale
        Circle()
            .stroke(Color.yellow.opacity(0.9), lineWidth: 1.5)
            .frame(width: outer * 2, height: outer * 2)
            .position(center)
        centerHandle(center: center, scaleX: scaleX, scaleY: scaleY)
        handle(color: .yellow)
            .position(x: center.x + outer, y: center.y)
            .gesture(circleRadiusDrag(center: center, scale: radiusScale))
    }

    @ViewBuilder
    private func annulus(center: CGPoint, scaleX: CGFloat, scaleY: CGFloat, radiusScale: CGFloat) -> some View {
        let inner = CGFloat(aperture.inner) * radiusScale
        let outer = CGFloat(aperture.outer) * radiusScale
        Circle()
            .stroke(Color.yellow.opacity(0.9), lineWidth: 1.5)
            .frame(width: outer * 2, height: outer * 2)
            .position(center)
        Circle()
            .stroke(Color.cyan.opacity(0.9), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            .frame(width: inner * 2, height: inner * 2)
            .position(center)
            .opacity(aperture.inner > 0 ? 1 : 0.35)
        centerHandle(center: center, scaleX: scaleX, scaleY: scaleY)
        handle(color: .yellow)
            .position(x: center.x + outer, y: center.y)
            .gesture(radiusDrag(center: center, scale: radiusScale, isInner: false))
        handle(color: .cyan)
            .position(x: center.x + inner, y: center.y)
            .gesture(radiusDrag(center: center, scale: radiusScale, isInner: true))
    }

    @ViewBuilder
    private func rectangle(center: CGPoint, scaleX: CGFloat, scaleY: CGFloat, radiusScale: CGFloat) -> some View {
        // The mask kernel uses `outer` as the half-extent of a square detector.
        let half = CGFloat(aperture.outer) * radiusScale
        Rectangle()
            .stroke(Color.yellow.opacity(0.9), lineWidth: 1.5)
            .frame(width: half * 2, height: half * 2)
            .position(center)
        centerHandle(center: center, scaleX: scaleX, scaleY: scaleY)
        handle(color: .yellow)
            .position(x: center.x + half, y: center.y + half)
            .gesture(
                DragGesture(coordinateSpace: .local)
                    .onChanged { value in
                        let dx = abs(value.location.x - center.x)
                        let dy = abs(value.location.y - center.y)
                        var updated = aperture
                        updated.outer = max(1, Float(max(dx, dy) / radiusScale))
                        emit(updated)
                    }
                    .onEnded { _ in onCommit() }
            )
    }

    @ViewBuilder
    private func point(center: CGPoint, scaleX: CGFloat, scaleY: CGFloat) -> some View {
        // Crosshair marking the single detector pixel.
        Path { p in
            p.move(to: CGPoint(x: center.x - 8, y: center.y)); p.addLine(to: CGPoint(x: center.x + 8, y: center.y))
            p.move(to: CGPoint(x: center.x, y: center.y - 8)); p.addLine(to: CGPoint(x: center.x, y: center.y + 8))
        }
        .stroke(Color.yellow.opacity(0.9), lineWidth: 1.5)
        centerHandle(center: center, scaleX: scaleX, scaleY: scaleY)
    }

    // MARK: Handles

    private func centerHandle(center: CGPoint, scaleX: CGFloat, scaleY: CGFloat) -> some View {
        handle(color: .white)
            .position(center)
            .gesture(
                DragGesture(coordinateSpace: .local)
                    .onChanged { value in
                        var updated = aperture
                        updated.centerX = Float(min(max(0, value.location.x / scaleX), CGFloat(patternWidth)))
                        updated.centerY = Float(min(max(0, value.location.y / scaleY), CGFloat(patternHeight)))
                        emit(updated)
                    }
                    .onEnded { _ in onCommit() }
            )
    }

    /// Snap the geometry to whole detector pixels before publishing — a
    /// virtual detector sums whole pixels, so fractional edges are meaningless.
    private func emit(_ a: Aperture) {
        var s = a
        s.centerX = s.centerX.rounded()
        s.centerY = s.centerY.rounded()
        s.inner = s.inner.rounded()
        s.outer = s.outer.rounded()
        onEdited(s)
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

    private func circleRadiusDrag(center: CGPoint, scale: CGFloat) -> some Gesture {
        DragGesture(coordinateSpace: .local)
            .onChanged { value in
                let dx = value.location.x - center.x
                let dy = value.location.y - center.y
                var updated = aperture
                updated.outer = max(1, Float(hypot(dx, dy) / scale))
                onEdited(updated)
            }
            .onEnded { _ in onCommit() }
    }
}

import XCTest
import DSTEMCore
@testable import mac4DSTEM

/// Planted rings for the known-crystal Q calibration tests: Bragg vectors whose peak radii are known, on the demo state's detector
/// (the beam at the detector centre, four peaks per ring, every scan position identical).
@MainActor
enum PlantedQCalibration {
    static let al = 4.0495
    /// Al's shell lengths 1/d in Å⁻¹ for the family index (hkl as the squared sum): 111 3, 200 4, 220 8, 311 11, 222 12, 400 16.
    static func g(_ sumOfSquares: Double) -> Double { sumOfSquares.squareRoot() / al }

    /// Replace the state's Bragg vectors by rings at these radii (pixels). Rings alternate between the axes and the diagonals so
    /// neighbouring rings never share a peak position; every peak stays on the detector when the radii are below its half width.
    static func setRings(radiiPixels: [Double], on state: AppState, onDiagonals: Bool = false) {
        let scan = state.descriptor.map { max($0.rx, $0.ry) } ?? 12
        let centre = Float(state.descriptor.map { $0.qx } ?? 64) / 2
        var peaks: [BraggPeak] = []
        for (ring, r) in radiiPixels.enumerated() {
            let angles: [Double] = (onDiagonals || ring % 2 == 1) ? [45, 135, 225, 315] : [0, 90, 180, 270]
            for angle in angles {
                let t = angle * .pi / 180
                peaks.append(BraggPeak(x: centre + Float(r * cos(t)), y: centre + Float(r * sin(t)), intensity: 1000 - Float(ring)))
            }
        }
        state.resultPresentation.setBraggVectors(BraggVectors(
            scanWidth: scan, scanHeight: scan, peaks: [[BraggPeak]](repeating: peaks, count: scan * scan)))
    }
}

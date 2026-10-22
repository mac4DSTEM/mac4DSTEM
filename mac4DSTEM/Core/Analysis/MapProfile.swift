import Foundation
import ImagoCore

/// The profile of a map along a line: ImagoCore's `LineProfile.sample` (scikit-image's `profile_line`, linear order, reflect mode) on the
/// map as a float image. The app makes no number here; it hands the map to the kit and the line in the kit's pixel-centre coordinates.
public nonisolated enum MapProfile {
    public struct Result: Sendable, Equatable {
        public var samples: [Double]
        /// Distance of each sample from the line's start, in `unit`.
        public var positions: [Double]
        /// The scan's unit when it has a pixel size, else "px".
        public var unit: String
    }

    /// `from` and `to` are in scan pixels as the Spectroscopy room draws them: continuous, pixel (i, j) covering [i, i+1) × [j, j+1), so the
    /// kit's pixel-centre coordinates are these minus a half. A map the kit refuses (a size that does not match, a non-finite end) gives nil.
    public static func along(values: [Float], width: Int, height: Int, from: (x: Double, y: Double), to: (x: Double, y: Double),
                             pixelSize: Double?, unit: String?, lineWidth: Int = 1) -> Result? {
        guard width > 0, height > 0, values.count == width * height else { return nil }
        let axis = pixelSize.flatMap { size in unit.map { AxisCalibration(scale: size, unit: $0) } }
        guard let image = try? Micrograph(width: width, height: height, pixels: values, x: axis, y: axis),
              let profile = try? LineProfile.sample(image, from: PixelPoint(x: from.x - 0.5, y: from.y - 0.5),
                                                    to: PixelPoint(x: to.x - 0.5, y: to.y - 0.5), linewidth: lineWidth,
                                                    order: .linear, mode: .reflect, arithmetic: .float64) else { return nil }
        return Result(samples: profile.samples, positions: profile.positions, unit: profile.unit)
    }
}

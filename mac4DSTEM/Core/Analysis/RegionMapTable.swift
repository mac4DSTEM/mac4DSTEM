import Foundation
import ImagoCore

/// The mean of each element map under each region: ImagoCore's labelled statistics (`ObjectStatistics.measure`, SciPy's `ndimage.mean` and
/// `standard_deviation`) over a one-object label image per region. The app makes no number here; it hands each region's mask to the kit.
public nonisolated enum RegionMapTable {
    /// A map's mean under a region and the population spread of its pixels there.
    public struct Cell: Sendable, Equatable {
        public var mean: Double
        public var spread: Double
    }

    public struct Row: Sendable, Equatable {
        public var name: String
        public var pixels: Int
        /// One cell per map, in the maps' order; nil where the region holds no pixel or the kit refused the map.
        public var cells: [Cell?]
    }

    /// `maps` are row-major `width * height` arrays; a region's `mask` is the same size (`nil`: every pixel).
    public static func rows(maps: [[Float]], width: Int, height: Int, regions: [(name: String, mask: [Bool]?)]) -> [Row] {
        regions.map { region in
            let labels = (0..<(width * height)).map { i -> Int32 in region.mask.map { $0[i] ? 1 : 0 } ?? 1 }
            let pixels = labels.reduce(0) { $0 + Int($1) }
            guard pixels > 0, region.mask.map({ $0.count == width * height }) ?? true else {
                return Row(name: region.name, pixels: 0, cells: maps.map { _ in nil })
            }
            let image = Segmentation.LabelImage(width: width, height: height, labels: labels, count: 1)
            let cells: [Cell?] = maps.map { map in
                guard let r = try? ObjectStatistics.measure(image: map, labels: image).first else { return nil }
                return Cell(mean: r.mean, spread: r.standardDeviation)
            }
            return Row(name: region.name, pixels: pixels, cells: cells)
        }
    }
}

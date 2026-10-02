import Foundation
@main
struct Harness {
    static func main() throws {
        let out = URL(fileURLWithPath: CommandLine.arguments[1])
        let map = ScalarResultMap(
            width: 3, height: 2, pixels: [-1.25e-7, 3.5, 1e30, .nan, 0.1, 7],
            kind: "virtual_image", displayName: "Virtual image", valueUnits: "counts",
            pixelSizeRow: 0.25, pixelSizeColumn: 0.5, pixelUnits: "nm",
            provenance: ["detector": "annular", "display_domain": "scan"])
        try BraggVectorEMDWriter.writeScientificBundle(maps: [map], calibration: PixelCalibration(), to: out)
    }
}

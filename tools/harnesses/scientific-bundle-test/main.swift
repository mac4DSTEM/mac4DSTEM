import Foundation

func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw NSError(domain: "scientific-bundle-test", code: 1,
                                    userInfo: [NSLocalizedDescriptionKey: message]) }
}

@main
struct Harness {
    static func main() throws {
        guard CommandLine.arguments.count == 3 else { throw NSError(domain: "arguments", code: 1) }
        let output = URL(fileURLWithPath: CommandLine.arguments[1])
        let cancelledOutput = URL(fileURLWithPath: CommandLine.arguments[2])
        let kinds = ["strain_exx", "strain_eyy", "strain_exy", "strain_theta",
                     "strain_validity", "strain_fit_residual",
                     "orientation_phi1", "orientation_Phi", "orientation_phi2",
                     "orientation_reliability", "orientation_score", "orientation_validity"]
        let maps = kinds.enumerated().map { index, kind in
            let units: String
            if kind.contains("phi") || kind.contains("Phi") || kind == "strain_theta" {
                units = "rad"
            } else if kind.contains("validity") {
                units = "boolean"
            } else if kind.hasPrefix("orientation_") {
                units = "dimensionless"
            } else if kind == "strain_fit_residual" {
                units = "detector_px"
            } else {
                units = "strain"
            }
            return ScalarResultMap(
                width: 3, height: 2,
                pixels: [Float(index), 1, .nan, 3, 4, 5],
                kind: kind, displayName: kind, valueUnits: units,
                pixelSizeRow: 0.5, pixelSizeColumn: 0.5, pixelUnits: "nm",
                provenance: [
                    "bundle": kind.hasPrefix("orientation_") ? "orientation" : "strain",
                    "display_domain": "scan",
                    "symmetry": kind.hasPrefix("orientation_") ? "cubic" : "not_applicable",
                ]
            )
        }
        let cancellation = AnalysisCancellationToken()
        cancellation.cancel()
        do {
            try BraggVectorEMDWriter.writeScientificBundle(
                maps: maps, calibration: PixelCalibration(), to: cancelledOutput,
                cancellation: cancellation
            )
            try require(false, "cancelled bundle was published")
        } catch BraggVectorEMDWriter.WriterError.cancelled {}
        try require(!FileManager.default.fileExists(atPath: cancelledOutput.path),
                    "cancelled bundle left a destination")
        var calibration = PixelCalibration(rSize: 0.5, rUnits: "nm")
        calibration.qSize = 0.02
        calibration.qUnits = "A^-1"
        try BraggVectorEMDWriter.writeScientificBundle(
            maps: maps, calibration: calibration, to: output
        )
        let bytes = try Data(contentsOf: output)
        try require(!bytes.isEmpty, "bundle is empty")
        print("PASS: atomic coherent bundle and cancellation recovery")
    }
}

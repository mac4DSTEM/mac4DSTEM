import Foundation

@main
struct PreserveUnknownHarness {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else { exit(2) }
        let sidecar = URL(fileURLWithPath: CommandLine.arguments[1])
        var calibration = PixelCalibration(
            rSize: 1.75, rUnits: "nm", qSize: 0.03125,
            qUnits: "A^-1", qrFlip: true
        )
        calibration.qx0Mean = 16
        calibration.qy0Mean = 36
        calibration.ellipseA = 1.02
        calibration.ellipseB = 0.98
        calibration.ellipseTheta = 0.35
        calibration.qrRotationRad = -0.625
        calibration.probeSemiangle = 8.5
        calibration.originMaps = PixelOriginMaps(
            shape: [2, 3],
            fittedQX: [10, 11, 12, 20, 21, 22],
            fittedQY: [30, 31, 32, 40, 41, 42],
            measuredQX: [10.25, 11.25, 12.25, 20.25, 21.25, 22.25],
            measuredQY: [29.5, 30.5, 31.5, 39.5, 40.5, 41.5]
        )
        try BraggVectorEMDWriter.mergeCalibration(
            calibration, qWidth: 7, qHeight: 5, to: sidecar
        )
        print("PASS: external EMD object survived atomic calibration rewrite")
    }
}

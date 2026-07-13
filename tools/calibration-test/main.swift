// Regression harness for H5Reader.pixelCalibration().
// Usage: harness <fixture.h5>  — expects the calibration written by make_fixture.c.
import Foundation

// Usage: harness <fixture.h5> [dataset-path] [origin-maps]
let fixturePath = CommandLine.arguments[1]
let dsPath = CommandLine.arguments.count > 2
    ? CommandLine.arguments[2] : "/test_root/datacube/data"
let expectsOriginMaps = CommandLine.arguments.dropFirst(3).first == "origin-maps"

func check(_ cond: Bool, _ msg: @autoclosure () -> String) {
    if !cond { print("FAIL(\(fixturePath)): \(msg())"); exit(1) }
}

let sem = DispatchSemaphore(value: 0)
Task {
    do {
        let reader = try H5Reader(path: fixturePath)
        let desc = try await reader.describe(path: dsPath)
        let expectedShape = expectsOriginMaps ? [2, 3, 4, 5] : [2, 2, 4, 4]
        check(desc.shape == expectedShape, "shape \(desc.shape)")
        let tileRange = 0..<min(2, desc.ry)
        let tile = try await reader.readScanTile(desc, yRange: tileRange)
        var rowPixels: [Float] = []
        for row in tileRange {
            rowPixels += try await reader.readScanRow(desc, ry: row)
        }
        check(tile.yRange == tileRange, "tile range \(tile.yRange)")
        check(tile.pixels == rowPixels, "multi-row tile differs from row reads")
        guard let cal = await reader.pixelCalibration() else {
            print("FAIL(\(fixturePath)): pixelCalibration() returned nil"); exit(1)
        }
        check(cal.qSize == 0.0125, "qSize \(String(describing: cal.qSize))")
        check(cal.qUnits == "A^-1", "qUnits \(String(describing: cal.qUnits))")
        check(cal.rSize == 2.5, "rSize \(String(describing: cal.rSize))")
        check(cal.rUnits == "A", "rUnits \(String(describing: cal.rUnits))")
        check(cal.qrFlip == true, "qrFlip \(String(describing: cal.qrFlip))")
        check(cal.qx0Mean == (expectsOriginMaps ? 16.0 : 31.5),
              "qx0Mean \(String(describing: cal.qx0Mean))")
        check(cal.qy0Mean == (expectsOriginMaps ? 36.0 : 32.25),
              "qy0Mean \(String(describing: cal.qy0Mean))")
        check(cal.ellipseA == 1.02, "ellipseA \(String(describing: cal.ellipseA))")
        check(cal.ellipseB == 0.98, "ellipseB \(String(describing: cal.ellipseB))")
        check(cal.ellipseTheta == 0.35, "ellipseTheta \(String(describing: cal.ellipseTheta))")
        var appCalibration = Calibration()
        appCalibration.ellipseA = cal.ellipseA
        appCalibration.ellipseB = cal.ellipseB
        appCalibration.ellipseTheta = cal.ellipseTheta
        let corrected = appCalibration.ellipseCorrectedOffset(dx: 4, dy: 2)
        check(abs(corrected.x - 3.9562928113) < 1e-6,
              "ellipse corrected app x \(corrected.x)")
        check(abs(corrected.y - 1.8802636250) < 1e-6,
              "ellipse corrected app y \(corrected.y)")
        check(cal.qrRotationRad == (expectsOriginMaps ? 0.375 : nil),
              "qrRotationRad \(String(describing: cal.qrRotationRad))")
        check(cal.probeSemiangle == (expectsOriginMaps ? 7.25 : nil),
              "probeSemiangle \(String(describing: cal.probeSemiangle))")
        if expectsOriginMaps {
            guard let maps = cal.originMaps else {
                print("FAIL(\(fixturePath)): originMaps returned nil"); exit(1)
            }
            check(maps.shape == [2, 3], "origin map shape \(maps.shape)")
            check(maps.fittedQX == [10, 11, 12, 20, 21, 22],
                  "fittedQX \(maps.fittedQX)")
            check(maps.fittedQY == [30, 31, 32, 40, 41, 42],
                  "fittedQY \(maps.fittedQY)")
            check(maps.measuredQX == [10.25, 11.25, 12.25, 20.25, 21.25, 22.25],
                  "measuredQX \(String(describing: maps.measuredQX))")
            check(maps.measuredQY == [29.5, 30.5, 31.5, 39.5, 40.5, 41.5],
                  "measuredQY \(String(describing: maps.measuredQY))")

            guard let appMaps = maps.appOriginMaps(width: 3, height: 2) else {
                print("FAIL(\(fixturePath)): appOriginMaps returned nil"); exit(1)
            }
            check(appMaps.fittedX == [30, 31, 32, 40, 41, 42],
                  "app fittedX \(appMaps.fittedX)")
            check(appMaps.fittedY == [10, 11, 12, 20, 21, 22],
                  "app fittedY \(appMaps.fittedY)")
            check(appMaps.measuredX == [29.5, 30.5, 31.5, 39.5, 40.5, 41.5],
                  "app measuredX \(String(describing: appMaps.measuredX))")
            check(appMaps.measuredY == [10.25, 11.25, 12.25, 20.25, 21.25, 22.25],
                  "app measuredY \(String(describing: appMaps.measuredY))")
        } else {
            check(cal.originMaps == nil, "mean-only fixture unexpectedly returned origin maps")
        }
        print("PASS: \(fixturePath)")
    } catch {
        print("FAIL(\(fixturePath)): \(error)"); exit(1)
    }
    sem.signal()
}
sem.wait()

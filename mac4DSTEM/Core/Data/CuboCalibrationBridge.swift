//
//  CuboCalibrationBridge.swift
//  Role: the app's calibration value (`DSTEMCore.Calibration`) as CuboKit's (`CuboCore.Calibration`, py4DSTEM's `Calibration`) for the
//        fields the two share: Q and R pixel sizes and units, the origin per scan position or the mean, the ellipse, the Q-R rotation and
//        flip, the probe radius. The first step of adopting the kit's model (ROADMAP task 5): the kit's grids and its
//        binning/thinning/padding/resampling pixel-size rules can now be asked of an app calibration, and the tests pin where the two
//        agree and where the app's own rule is stricter (`CuboCalibrationBridgeTests`). The app's provenance, validity masks and
//        aperture centre have no kit counterpart and do not cross. One-way: nothing in the app reads the kit's value back yet.
//

import Foundation
import CuboCore

extension DSTEMCore.Calibration {
    /// The kit's calibration for a `scanRows` x `scanColumns` scan. Frame: the app's origin x is a detector COLUMN and y a ROW; the kit's
    /// `originColumn` / `originRow` are those, one per position when the app holds a map and the mean otherwise.
    package nonisolated func cuboCalibration() -> CuboCore.Calibration {
        var c = CuboCore.Calibration()
        if let size = qPixelSize, size.isFinite, size > 0 {
            c.detectorPixelSize = size
            switch qPixelUnits?.lowercased().replacingOccurrences(of: "⁻¹", with: "^-1").replacingOccurrences(of: " ", with: "") {
            case "å^-1", "a^-1", "1/å", "1/a", "angstrom^-1": c.detectorUnits = .inverseAngstroms
            case "mrad": c.detectorUnits = .milliradians
            default: c.detectorUnits = .pixels
            }
        }
        if let size = rPixelSize, size.isFinite, size > 0 {
            c.scanPixelSize = size
            c.scanUnits = rPixelUnits ?? "pixels"
        }
        if let origin, origin.width > 0, origin.height > 0, origin.fittedX.count == origin.width * origin.height,
           origin.fittedY.count == origin.fittedX.count,
           let column = try? ScanField(scanRows: origin.height, scanColumns: origin.width, values: origin.fittedX.map(Double.init)),
           let row = try? ScanField(scanRows: origin.height, scanColumns: origin.width, values: origin.fittedY.map(Double.init)) {
            try? c.setOrigin(row: row, column: column)
        } else if let mean = meanOrigin {
            c.setOrigin(row: Double(mean.y), column: Double(mean.x))
        }
        if let a = ellipseA, let b = ellipseB, let theta = ellipseTheta {
            c.ellipse = EllipseCalibration(a: a, b: b, theta: theta)
        }
        if let rotation = rotationRad { c.setQRRotation(radians: Double(rotation)) }
        c.qrFlip = transposeQR ?? false
        if let radius = probeRadius { c.probeSemiangle = Double(radius) }
        return c
    }
}

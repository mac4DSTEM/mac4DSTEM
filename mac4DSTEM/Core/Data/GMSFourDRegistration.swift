//
//  GMSFourDRegistration.swift
//  Role: The 4D layer's half of the GMS joint open (SpectroKit S1, plan E5): the library reads a DM4's EDS object purely
//        (`SpectrumImageOpener.openGMSEDS(path:)`); this file reads the objects (`DM4Experiment.list`) and
//        decides whether that EDS object belongs to the 4D cube beside it and what the beam energy is then. Lives in Core/Data,
//        outside the spectroscopy moving set, because it is the 4D vocabulary; headless, no AppState, no UI.
//

import Foundation
import FormatoDM
import SpectroCore

/// The 4D cube a GMS file's EDS object may be registered to.
package nonisolated struct GMSFourDIdentity: Equatable, Sendable {
    /// `ImageList.N` index of the opened 4D object, when known.
    package var objectIndex: Int?
    package var scanWidth: Int
    package var scanHeight: Int
    /// The cube's accelerating voltage in kV (the session's), the beam energy when the EDS object states none.
    package var voltageKV: Double?
    package init(objectIndex: Int?, scanWidth: Int, scanHeight: Int, voltageKV: Double? = nil) {
        self.objectIndex = objectIndex; self.scanWidth = scanWidth; self.scanHeight = scanHeight; self.voltageKV = voltageKV
    }
}

// `nonisolated`: both types are SpectroKit's (nonisolated by default there); in this MainActor-default module an
// extension of a type from another module does not take the type's isolation, as it did while both were in DSTEMCore.
nonisolated extension BeamEnergySource {
    /// The 4D cube of the same GMS run (same Experiment ID and scan grid), when the EDS object states no voltage.
    package static let fourDCube = BeamEnergySource.supplied(label: "the 4D cube, same run")
}

nonisolated extension SpectrumImageOpener {
    /// The EDS spectrum image of a GMS DM4, or nil when the file has none. With `fourD`, the image is registered to that cube
    /// BY IDENTITY when both objects carry the same Experiment ID and the EDS grid equals the cube's scan grid
    /// (`sameScanAsCube`); otherwise it is still attached, with the reason in `registrationNote`. The beam energy is the EDS
    /// object's own voltage, else the cube's when both are one run (`BeamEnergy.resolve`).
    package static func openGMSEDS(path: String, fourD: GMSFourDIdentity?,
                                   cancelled: @Sendable () -> Bool = SpectroCancellation.task,
                                   progress: (@Sendable (Double) -> Void)? = nil) throws -> LoadedSpectrumImage? {
        guard let loaded = try openGMSEDS(path: path, cancelled: cancelled, progress: progress) else { return nil }
        guard let cube = fourD else { return loaded }
        let objects = try DM4Experiment.list(path: path)
        var meta = loaded.metadata
        let object = cube.objectIndex.flatMap { i in objects.first { $0.index == i } }
            ?? objects.first { $0.role == .diffraction }
        let eds = objects.first { $0.role == .eds }
        if let id = eds?.experimentID, id == object?.experimentID, cube.scanWidth == meta.scanWidth, cube.scanHeight == meta.scanHeight {
            meta.sameScanAsCube = true
        } else if cube.scanWidth != meta.scanWidth || cube.scanHeight != meta.scanHeight {
            meta.registrationNote = "Not registered: the EDS scan is \(meta.scanWidth) × \(meta.scanHeight) px, the 4D scan \(cube.scanWidth) × \(cube.scanHeight)."
        } else {
            meta.registrationNote = "Not registered: the two objects do not share an Experiment ID."
        }
        if let b = BeamEnergy.resolve(rawObjectVoltage: eds?.voltage, suppliedKV: cube.voltageKV, suppliedAs: .fourDCube,
                                      sameRun: meta.sameScanAsCube) {
            meta.beamEnergyKeV = b.keV; meta.beamEnergySource = b.source
        }
        return LoadedSpectrumImage(image: loaded.image, metadata: meta, energyAxis: loaded.energyAxis, scanImage: loaded.scanImage)
    }
}

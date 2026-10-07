//
//  AutoIDBeamEnergyNoteTests.swift
//  Auto ID's "needs the beam energy" note goes when a beam energy is typed under Quantification; no other failure goes with it.
//  Found on screen (drive 3, 2026-10-07): the button became enabled but the note stayed.
//

import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

@MainActor
final class AutoIDBeamEnergyNoteTests: XCTestCase {
    private var keep: [AppState] = []

    /// The synthetic image with the beam energy left out of the file, as the demo fixture states none.
    private func openWithoutBeam() -> SpectroscopyRoomController {
        let full = SpectroscopyRoomLiveRegionTests.image()
        var meta = full.metadata
        meta.beamEnergyKeV = nil
        let image = LoadedSpectrumImage(image: full.image, metadata: meta, energyAxis: full.energyAxis, scanImage: full.scanImage)
        let state = AppState(); keep.append(state)
        state.openSpectrumImage(image)
        state.spectroscopyRoom.autoIDOnOpen?.cancel()
        return state.spectroscopyRoom
    }

    /// The failure the open's run gives, then a typed beam energy: the note is gone, and Auto ID did not start by itself.
    /// Mutation: `clearAutoIDBeamNote` not called from `quantifySettingsChanged` (never clear) - red.
    func testATypedBeamEnergyRetiresTheNeedsBeamNote() {
        let c = openWithoutBeam()
        c.runAutoID()
        XCTAssertEqual(c.model.autoID.failure, SpectroscopyRoomModel.autoIDNeedsBeamNote, "the file states no beam energy")
        c.model.quantify.beamEnergy = 200
        c.quantifySettingsChanged()
        XCTAssertNil(c.model.autoID.failure, "the note asked for what was just typed")
        XCTAssertFalse(c.model.autoID.running, "typing a value does not start a run")
    }

    /// A failure that is not about the beam energy stays when one is typed.
    /// Mutation: `clearAutoIDBeamNote` clearing every failure (the equality guard dropped) - red.
    func testAnotherAutoIDFailureSurvivesATypedBeamEnergy() {
        let c = openWithoutBeam()
        let token = c.model.beginAutoID()
        c.model.failAutoID(token: token, message: "Auto ID failed.")
        c.model.quantify.beamEnergy = 200
        c.quantifySettingsChanged()
        XCTAssertEqual(c.model.autoID.failure, "Auto ID failed.")
    }

    /// A typed value that is no beam energy (0) answers nothing: the note stays.
    /// Mutation: the `beam > 0` test dropped from `quantifySettingsChanged` - red.
    func testAZeroBeamEnergyKeepsTheNote() {
        let c = openWithoutBeam()
        c.runAutoID()
        c.model.quantify.beamEnergy = 0
        c.quantifySettingsChanged()
        XCTAssertEqual(c.model.autoID.failure, SpectroscopyRoomModel.autoIDNeedsBeamNote)
    }
}

//
//  FileRouting.swift
//  Role: Open routes by content (FormatoKit 0.9: `FormatoLoader.sniff`, the extension picks the candidates and the first bytes confirm
//        them) instead of an extension switch; and the single spectrum of an `.msa` file as a one-pixel spectrum image, and back
//        (`MSAWriter`) so the Spectroscopy room can read and write the format. The 4D readers stay the app's (EMPAD, MIB and HDF5
//        4D files have their own options; the kit names them and says `useDedicatedReader`). Pure: no AppState, no UI.
//

import Foundation
import Formato
import FormatoCore
import FormatoMSA
import SpectroCore

/// Where an Open goes.
package nonisolated enum OpenRoute: Equatable, Sendable {
    /// A Gatan DM3/DM4 file: the app's `DM4Reader` (3D to 4D reshape, kept on purpose).
    case digitalMicrograph
    case merlinMIB
    case empad
    /// HDF5 (py4DSTEM, EMD, Velox with a cube): `H5Reader`.
    case hdf5
    /// A single spectrum (`.msa`): the Spectroscopy room as a one-pixel spectrum image.
    case singleSpectrum
    /// Not a 4D dataset: the sentence says what the file is.
    case refused(String)
}

package nonisolated enum FileRouting {
    /// The route for `path`. `.raw` is EMPAD's data file (the kit names only its `.xml`); a file whose extension the kit does not
    /// know but whose first bytes are HDF5 still goes to the HDF5 reader, as every unknown extension did before.
    package static func route(path: String) -> OpenRoute {
        let name = (path as NSString).lastPathComponent
        let ext = (path as NSString).pathExtension.lowercased()
        switch FormatoLoader.sniff(path: path) {
        case .digitalMicrograph: return .digitalMicrograph
        case .merlinMIB: return .merlinMIB
        case .empad: return .empad
        case .hdf5, .veloxEMD: return .hdf5
        case .msa: return .singleSpectrum
        case .tiff: return .refused("\(name) is a TIFF image, not a 4D dataset.")
        case .mrc: return .refused("\(name) is an MRC image or stack, not a 4D dataset.")
        case .unknown:
            if ext == "raw" { return .empad }
            if hasHDF5Signature(path) { return .hdf5 }
            return .refused("\(name) is not a format the app opens (or its extension and its first bytes disagree).")
        }
    }

    private static func hasHDF5Signature(_ path: String) -> Bool {
        guard let handle = FileHandle(forReadingAtPath: path) else { return false }
        defer { try? handle.close() }
        let head = [UInt8]((try? handle.read(upToCount: 8)) ?? Data())
        return head == [0x89, 0x48, 0x44, 0x46, 0x0D, 0x0A, 0x1A, 0x0A]
    }

    // MARK: .msa

    package struct MSAReadError: Error, LocalizedError, Equatable {
        package var text: String
        package var errorDescription: String? { text }
    }

    /// An `.msa` spectrum as a 1 x 1 spectrum image on a keV axis. Counts are rounded to whole counts (a spectrum with negative or
    /// non-finite values is refused); the beam energy is the file's `BEAMKV` when it states one. `validation` stays with the
    /// quantification, as for every file.
    package static func spectrumImage(msaPath path: String) throws -> LoadedSpectrumImage {
        let spectrum = try MSAReader.read(path: path)
        let signal = spectrum.signal
        guard let axis = signal.axes.first else { throw MSAReadError(text: "The spectrum has no energy axis.") }
        let values = signal.data.doubles()
        guard !values.isEmpty, values.allSatisfy({ $0.isFinite && $0 >= 0 }) else {
            throw MSAReadError(text: "The spectrum holds negative or non-finite values: it is not a count spectrum.")
        }
        // MSA axes are eV unless the file says keV.
        let toKeV = axis.units.lowercased() == "kev" ? 1.0 : 0.001
        let energyAxis = EnergyAxis(offset: axis.offset * toKeV, scale: axis.scale * toKeV, size: values.count)
        guard energyAxis.scale > 0 else { throw MSAReadError(text: "The spectrum's channel width is not positive.") }
        var meta = SpectrumImageMetadata(fileName: (path as NSString).lastPathComponent, filePath: path, scanWidth: 1, scanHeight: 1,
                                         channelCount: values.count, energyOffsetEV: axis.offset * toKeV * 1000,
                                         energyDispersionEV: axis.scale * toKeV * 1000)
        if let beam = signal.metadata["Acquisition_instrument.TEM.beam_energy"]?.value.number, beam > 0 { meta.beamEnergyKeV = beam }
        let counts = values.map { UInt32(min($0.rounded(), Double(UInt32.max))) }
        return LoadedSpectrumImage(image: DenseSpectrumImage(ny: 1, nx: 1, channels: values.count, counts: counts),
                                   metadata: meta, energyAxis: energyAxis)
    }

    /// The `.msa` bytes of one shown spectrum (keV axis, counts as Y): FormatoKit's `MSAWriter`.
    package static func msaData(counts: [Double], offsetKeV: Double, scaleKeV: Double, title: String, beamEnergyKeV: Double?) throws -> Data {
        var bytes = Data()
        for v in counts { withUnsafeBytes(of: v.bitPattern.littleEndian) { bytes.append(contentsOf: $0) } }
        let array = try FormatoArray(dataType: .float64, shape: [counts.count], bytes: bytes)
        var metadata = FormatoMetadata()
        if let beamEnergyKeV {
            metadata.set(FormatoMetadataEntry(key: "Acquisition_instrument.TEM.beam_energy", value: .number(beamEnergyKeV), units: "kV",
                                              provenance: FormatoProvenance(file: title, source: "spectrum image", rule: "beam energy of the spectrum image")))
        }
        let axis = FormatoAxis(name: "Energy", size: counts.count, scale: scaleKeV, offset: offsetKeV, units: "keV", navigate: false)
        return try MSAWriter.encode(FormatoSignal(title: title, signalType: "", axes: [axis], metadata: metadata, data: array))
    }
}

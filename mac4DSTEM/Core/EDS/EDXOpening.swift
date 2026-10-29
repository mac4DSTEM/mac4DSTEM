// Opening an EDX spectrum image for the EDS room's own Open button (macTEM 1.0's `EDXOpening`, on mac4DSTEM's `FileRouting`): a Velox
// .emd with a spectrum stream, the EDS object of a GMS .dm4, or a single spectrum (.msa, a Velox file of spectra) as a one-pixel image.
// The window's File > Open keeps its own route (`AppState.openAsSpectrumImageIfApplicable`): a 4D file there goes to the 4D side.
import Foundation
import SpectroCore
import ShellEDXModel

package nonisolated enum EDXOpening {
    /// File extensions the Open panel offers (a Velox EMD, a GMS DM4, an MSA spectrum).
    package static let readableExtensions = ["emd", "dm4", "msa"]

    /// Reads the whole spectrum image: off the main actor, cancellable through the calling task, `progress` 0...1.
    package static func open(url: URL, progress: (@Sendable (Double) -> Void)? = nil) throws -> LoadedSpectrumImage {
        let path = url.path
        if FileRouting.route(path: path) == .singleSpectrum { return try FileRouting.spectrumImage(msaPath: path) }
        let kind = SpectrumImageOpener.kind(ofFileAt: path)
        if kind == .other, url.pathExtension.lowercased() == "emd", let single = FileRouting.veloxSpectrum(path: path) { return single.image }
        return try SpectrumImageOpener.open(path: path, kind: kind, progress: progress)
    }
}

extension EDXRoomHost {
    /// mac4DSTEM in the shared EDS room: its names in the export files, its file routing for the room's Open button.
    package static let mac4DSTEM = EDXRoomHost(appName: "mac4DSTEM", roomSource: "mac4DSTEM EDS room", regionsTitle: "mac4DSTEM EDS regions",
                                               readableExtensions: EDXOpening.readableExtensions) { url, progress in
        try EDXOpening.open(url: url, progress: progress)
    }
}

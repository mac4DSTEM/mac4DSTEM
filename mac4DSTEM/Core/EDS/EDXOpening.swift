// Opening an EDX spectrum image for the EDS room's own Open button (macTEM 1.0's `EDXOpening`, on mac4DSTEM's `FileRouting`): a Velox
// .emd with a spectrum stream, the EDS object of a GMS .dm4, or a single spectrum (.msa, a Velox file of spectra) as a one-pixel image.
// The window's File > Open keeps its own route (`AppState.openAsSpectrumImageIfApplicable`): a 4D file there goes to the 4D side.
import Foundation
import SpectroCore

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

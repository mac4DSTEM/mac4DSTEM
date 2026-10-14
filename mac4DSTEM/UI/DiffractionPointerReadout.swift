import Foundation
import CoreGraphics
#if canImport(DSTEMCore)   // absent when a tools/ harness compiles this file into one module
import DSTEMCore
#endif

/// What the Diffraction pane's header says about the pixel under the pointer: the pixel, the stored value, and the calibrated
/// distance from the beam centre. Pure, so the rules are unit-tested without a window. Registered before it was written:
/// `docs/archive/v5/diffraction-readout-2026-10-14.md` (definitions, sources, predictions).
///
/// Nothing here is a new conversion. The pixel map is the floor `RealSpacePane`'s readout and
/// `RealSpacePointerPolicy.scanPosition` use (and the inverse of `PeakOverlayGeometry.center`); q is the distance
/// `BraggVectors.calibrated(with:referenceOrigin:)` gives a peak: `Calibration.ellipseCorrectedOffset` of the pixel's offset
/// from the origin, times the Q scale.
nonisolated enum DiffractionPointerReadout {

    struct Pixel: Equatable {
        /// The detector column (the app's Qx; py4DSTEM names this axis the other way round).
        var x: Int
        /// The detector row (the app's Qy).
        var y: Int
    }

    /// The Q scale a q is read in: the calibrated unit, or mrad per detector pixel in the pane's mrad mode (the footer scale
    /// bar's own choice, so the two never disagree).
    struct Scale: Equatable {
        var perPixel: Double
        var unit: String
        /// mrad is a scattering angle (θ), not a reciprocal-space distance (q).
        var isAngle: Bool
        var symbol: String { isAngle ? "θ" : "q" }
    }

    struct Reciprocal: Equatable {
        var value: Double
        var scale: Scale
    }

    struct Sample: Equatable {
        var pixel: Pixel
        /// The stored pattern value (not the log or normalised display value); nil for a non-finite pixel.
        var value: Float?
        /// nil unless the Q scale is physical and the origin a measured beam centre.
        var reciprocal: Reciprocal?
    }

    /// Everything the pane reads from the session to turn a pixel into a q.
    struct Basis {
        var calibration: Calibration
        var detectorQX: Int
        var detectorQY: Int
        var scanX: Int
        var scanY: Int
        var scanWidth: Int
        var scanHeight: Int
        /// The pattern is the one at the selected scan position (Current, Point shape): the per-position origin applies.
        /// Mean, max and ROI-sum patterns are centred on the mean origin.
        var singlePosition: Bool
        var apertureCentre: (x: Float, y: Float)?
        var milliradians: Bool
        var mradPerPixel: Float?
    }

    // MARK: Pixel

    /// The detector pixel under a point of the pattern's (unzoomed) box, or nil outside it. Floors, so each pixel owns the
    /// area it covers; a point on the far edge belongs to no pixel.
    static func pixel(at point: CGPoint, patternWidth: Int, patternHeight: Int, box: CGSize) -> Pixel? {
        guard patternWidth > 0, patternHeight > 0, box.width > 0, box.height > 0,
              point.x >= 0, point.y >= 0, point.x < box.width, point.y < box.height else { return nil }
        let x = Int((point.x / box.width * CGFloat(patternWidth)).rounded(.down))
        let y = Int((point.y / box.height * CGFloat(patternHeight)).rounded(.down))
        return Pixel(x: min(x, patternWidth - 1), y: min(y, patternHeight - 1))
    }

    // MARK: q

    /// The scale a q is read in, or nil when the Q calibration is not a physical one (unset, or in pixels): the readiness row's
    /// own `validQ` rule.
    static func scale(calibration: Calibration, milliradians: Bool, mradPerPixel: Float?) -> Scale? {
        if milliradians, let mradPerPixel, mradPerPixel.isFinite, mradPerPixel > 0 {
            return Scale(perPixel: Double(mradPerPixel), unit: "mrad", isAngle: true)
        }
        guard let size = calibration.qPixelSize, size.isFinite, size > 0,
              CalibrationUnitConversion.isPhysicalReciprocalUnit(calibration.qPixelUnits) else { return nil }
        let unit = CalibrationUnitConversion.displayLabel(calibration.qPixelUnits)
        return Scale(perPixel: size, unit: unit, isAngle: unit == "mrad")
    }

    /// The origin a q is measured from, or nil when the calibration does not support a reciprocal measurement
    /// (`originSupportsReciprocalMetrology`: the fit is sane and the origin a measured beam centre, never the aperture centre or
    /// the detector's middle). The per-position fitted origin for the single-position pattern, the mean otherwise.
    static func origin(_ basis: Basis) -> (x: Float, y: Float)? {
        let calibration = basis.calibration
        guard calibration.originSupportsReciprocalMetrology(
            detectorQX: basis.detectorQX, detectorQY: basis.detectorQY, apertureCentre: basis.apertureCentre
        ) else { return nil }
        let reference = calibration.referenceOrigin(
            detectorQX: basis.detectorQX, detectorQY: basis.detectorQY, apertureCentre: basis.apertureCentre).point
        guard basis.singlePosition, basis.scanWidth > 0, basis.scanHeight > 0,
              (0..<basis.scanWidth).contains(basis.scanX), (0..<basis.scanHeight).contains(basis.scanY) else {
            return reference
        }
        return FitOverlays.localOrigin(
            calibration: calibration, referenceOrigin: reference,
            scanIndex: basis.scanY * basis.scanWidth + basis.scanX,
            scanWidth: basis.scanWidth, scanHeight: basis.scanHeight)
    }

    /// q = scale · |E(p − o)|: the pixel's offset from the origin through the detector-ellipse correction, in the scale's unit.
    static func distance(of pixel: Pixel, from origin: (x: Float, y: Float),
                         calibration: Calibration, scale: Scale) -> Double {
        let offset = calibration.ellipseCorrectedOffset(dx: Float(pixel.x) - origin.x, dy: Float(pixel.y) - origin.y)
        return scale.perPixel * (Double(offset.x) * Double(offset.x) + Double(offset.y) * Double(offset.y)).squareRoot()
    }

    // MARK: Sample

    /// The readout for a pixel of `pattern`, or nil when the pixel is not on it.
    static func sample(at pixel: Pixel, in pattern: DiffractionPattern, basis: Basis) -> Sample? {
        guard pixel.x >= 0, pixel.y >= 0, pixel.x < pattern.qx, pixel.y < pattern.qy,
              pattern.pixels.count == pattern.qx * pattern.qy else { return nil }
        let raw = pattern.pixels[pixel.y * pattern.qx + pixel.x]
        var reciprocal: Reciprocal?
        // The cheap test first: with no physical Q scale nothing below runs.
        if let scale = scale(calibration: basis.calibration, milliradians: basis.milliradians,
                             mradPerPixel: basis.mradPerPixel),
           let origin = origin(basis) {
            reciprocal = Reciprocal(
                value: distance(of: pixel, from: origin, calibration: basis.calibration, scale: scale), scale: scale)
        }
        return Sample(pixel: pixel, value: raw.isFinite ? raw : nil, reciprocal: reciprocal)
    }
}

// MARK: - Text

extension DiffractionPointerReadout.Sample {
    private func number(_ value: Double, digits: Int, locale: Locale) -> String {
        CalibrationUnitConversion.displayNumber(value, digits: digits, locale: locale)
    }

    private func valueText(locale: Locale) -> String {
        value.map { number(Double($0), digits: 4, locale: locale) } ?? "\u{2014}"
    }

    private func reciprocalText(locale: Locale) -> String? {
        reciprocal.map { "\($0.scale.symbol) \(number($0.value, digits: 4, locale: locale)) \($0.scale.unit)" }
    }

    /// The readout as the header prints it, longest first; the header shows the first that fits its gap. Every variant keeps the
    /// number's meaning: the field names go before the unit does, and q is the last thing to leave.
    struct Lines: Equatable {
        var full: String
        var short: String
        var minimal: String
    }

    func lines(locale: Locale = .autoupdatingCurrent) -> Lines {
        let q = reciprocalText(locale: locale)
        let value = valueText(locale: locale)
        let minimal = "(\(pixel.x), \(pixel.y)) \u{00B7} \(value)"
        var full = "Qx \(pixel.x) \u{00B7} Qy \(pixel.y) \u{00B7} I \(value)"
        var short = minimal
        if let q { full += " \u{00B7} " + q; short += " \u{00B7} " + q }
        return Lines(full: full, short: short, minimal: minimal)
    }

    /// VoiceOver's value for the pane while the pointer is on it.
    func spoken(locale: Locale = .autoupdatingCurrent) -> String {
        var text = "Detector pixel Qx \(pixel.x), Qy \(pixel.y), intensity \(valueText(locale: locale))"
        if let q = reciprocalText(locale: locale) { text += ", " + q }
        return text
    }
}

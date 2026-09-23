//
//  ResultPresentation.swift
//  Role: the one owner of the retained scientific product, result-view
//        controls, and the presentation caches derived from them.
//
//  `DisplayedProduct` remains an immutable Core value. This type owns the
//  mutable session/window presentation around that value; AppState only
//  coordinates inputs that cross owners (for example the temporary ACOM
//  region-reference canvas).
//


import Foundation
#if canImport(DSTEMCore)
import DSTEMCore
#endif
import Observation

package enum ColormapKind: String, CaseIterable, Identifiable {
    case viridis
    case inferno
    case gray
    case rdbu

    package var id: String { rawValue }

    package var displayName: String {
        switch self {
        case .viridis: return "Viridis"
        case .inferno: return "Inferno"
        case .gray: return "Gray"
        case .rdbu: return "RdBu (diverging)"
        }
    }

    package var isDiverging: Bool { self == .rdbu }
}

@Observable
@MainActor
package final class ResultPresentation {
    package nonisolated init() {}

    // The scientific value retained when navigation temporarily presents a
    // positioning reference. Mutations go through the methods below so the
    // version-bump order stays exact at every call site.
    package private(set) var product: DisplayedProduct?

    package var resultColormap: ColormapKind = .viridis {
        didSet { resultVersion &+= 1 }
    }
    package var displayRangeLo: Float = 0
    package var displayRangeHi: Float = 1
    package var resultGamma: Float = 1
    package var inspectQualityField = false
    package private(set) var resultVersion = 0

    // Shared products: disk detection feeds strain, ACOM and export; virtual
    // detector state feeds both the scan map and the ROI-summed CBED.
    package private(set) var braggPeakCount: Int?
    package private(set) var braggVectors: BraggVectors?
    package var virtualShape: VirtualShapeMode = .annulus
    package private(set) var virtualDiffractionPattern: DiffractionPattern?

    // Coalescing tokens for the result/ROI presentation paths. At most one
    // pass is in flight; the pending bit requests one latest-state rerun.
    @ObservationIgnored package var vdInFlight = false
    @ObservationIgnored package var vdPending = false
    @ObservationIgnored package var patternInFlight = false
    @ObservationIgnored package var patternPending = false
    @ObservationIgnored package var vdiffInFlight = false
    @ObservationIgnored package var vdiffPending = false

    // These are memoized derivations, not semantic state. They are deliberately
    // ignored by Observation and keyed on the same explicit invalidation token
    // as the texture upload. See docs/archive/v4/appstate-seams-plan.md, seam 5 decision b.
    @ObservationIgnored private var resultValueRangeCache:
        (version: Int, regionReference: Bool, symmetric: Bool,
         low: Double, high: Double)?
    @ObservationIgnored private var resultNormCache:
        (version: Int, regionReference: Bool, symmetric: Bool,
         pixels: [Float], hasInvalid: Bool)?
    @ObservationIgnored private var qualityNormCache:
        (version: Int, name: String, pixels: [Float])?

    package var resultImage: FloatImage? {
        if case .scalar(let image)? = product?.payload { return image }
        return nil
    }

    package var resultRGBA: RGBAImage? {
        if case .rgba(let rgba)? = product?.payload { return rgba }
        return nil
    }

    /// Replace the retained product without changing the version. Several
    /// legacy call sites bump before or after this write; this preserves
    /// that ordering exactly. Unifying it is tracked as follow-up debt.
    package func replaceProduct(_ product: DisplayedProduct?) {
        self.product = product
    }

    /// The common publication order: store the new product, then invalidate.
    package func publish(_ product: DisplayedProduct) {
        self.product = product
        resultVersion &+= 1
    }

    package func bumpResultVersion() {
        resultVersion &+= 1
    }

    /// A fresh window's starting colormap (`AppState.init`,
    /// `Session/AppPreferences.swift`'s `mapColormap`) is set before any
    /// product exists, so it must not look like a display change to a
    /// version-gated cache. `resultColormap`'s own `didSet` bumps
    /// `resultVersion` on every assignment (it has to, for a real change
    /// mid-session); this restores whatever version was already current so
    /// the one-time seed is invisible to it. Pinned by
    /// `ResultPresentationSeamTests.testAppStatePublicationUsesTheOwnerAndKeepsTheVersionContract`,
    /// which asserts `resultVersion == 1` after exactly one `publish`.
    package func seedInitialColormap(_ colormap: ColormapKind) {
        let priorVersion = resultVersion
        resultColormap = colormap
        resultVersion = priorVersion
    }

    package func setBraggVectors(_ vectors: BraggVectors?) {
        braggVectors = vectors
    }

    package func setBraggPeakCount(_ count: Int?) {
        braggPeakCount = count
    }

    package func clearBraggVectors() {
        braggVectors = nil
        braggPeakCount = nil
    }

    package func setVirtualDiffractionPattern(_ pattern: DiffractionPattern?) {
        virtualDiffractionPattern = pattern
    }

    package func resetViewControls() {
        displayRangeLo = 0
        displayRangeHi = 1
        resultGamma = 1
    }

    package func resetForDatasetActivation() {
        product = nil
        inspectQualityField = false
        clearBraggVectors()
        virtualDiffractionPattern = nil
    }

    package func qualityField(for displayedProduct: DisplayedProduct?) -> ProductQualityField? {
        guard inspectQualityField else { return nil }
        return displayedProduct?.qualityFields.first
    }

    package func displayedValueRange(
        image: FloatImage?, version: Int, regionReference: Bool,
        colormap: ColormapKind, rangeLo: Float, rangeHi: Float
    ) -> (low: Double, high: Double)? {
        guard let image else { return nil }
        let symmetric = colormap.isDiverging
        let baseLow: Double
        let baseHigh: Double
        if let cache = resultValueRangeCache,
           cache.version == version,
           cache.regionReference == regionReference,
           cache.symmetric == symmetric {
            baseLow = cache.low
            baseHigh = cache.high
        } else {
            let (rawLow, rawHigh) = image.minMax
            guard rawLow.isFinite, rawHigh.isFinite else { return nil }
            if symmetric {
                let magnitude = Double(max(abs(rawLow), abs(rawHigh)))
                baseLow = -magnitude
                baseHigh = magnitude
            } else {
                baseLow = Double(rawLow)
                baseHigh = Double(rawHigh)
            }
            resultValueRangeCache = (
                version, regionReference, symmetric, baseLow, baseHigh
            )
        }
        let span = baseHigh - baseLow
        return (
            baseLow + span * Double(rangeLo),
            baseLow + span * Double(rangeHi)
        )
    }

    package func normalizedResultPixels(
        image: FloatImage?, version: Int, regionReference: Bool,
        colormap: ColormapKind
    ) -> [Float] {
        guard let image else { return [] }
        let symmetric = colormap.isDiverging
        if let cache = resultNormCache,
           cache.version == version,
           cache.regionReference == regionReference,
           cache.symmetric == symmetric {
            return cache.pixels
        }
        let pixels = image.normalized(symmetric: symmetric)
        resultNormCache = (
            version, regionReference, symmetric, pixels,
            pixels.contains { $0 < 0 }
        )
        return pixels
    }

    package func normalizedQualityPixels(
        field: ProductQualityField?, version: Int
    ) -> [Float] {
        guard let field else { return [] }
        if let cache = qualityNormCache,
           cache.version == version,
           cache.name == field.name {
            return cache.pixels
        }
        let pixels = field.image.normalized(symmetric: false)
        qualityNormCache = (version, field.name, pixels)
        return pixels
    }

    package func displayedResultHasMaskedPixels(
        image: FloatImage?, version: Int, regionReference: Bool,
        colormap: ColormapKind
    ) -> Bool {
        guard image != nil else { return false }
        _ = normalizedResultPixels(
            image: image, version: version,
            regionReference: regionReference, colormap: colormap
        )
        return resultNormCache?.hasInvalid ?? false
    }
}

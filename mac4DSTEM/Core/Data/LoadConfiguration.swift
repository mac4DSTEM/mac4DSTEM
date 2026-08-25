//
//  LoadConfiguration.swift
//  Role: Turn what the user DRAGS on the open-time preview into a
//        `LoadSpecification`, and say what that specification would cost.
//
//  This is the arithmetic half of L5's configurator, kept out of the view so it
//  can be tested without a screen. The view owns gestures and layout; every
//  coordinate decision is here.
//
//  THE COORDINATE TRAP THIS TYPE EXISTS FOR. The real-space preview is drawn on
//  the SAMPLED grid, not the scan grid — `DatasetPreview.realSpace` has the
//  sample's dimensions, deliberately, so that nobody compares it pixel-for-pixel
//  with a real virtual image (invariant I4). So a rectangle dragged on it is in
//  units of *sampled positions*, and turning it into a `scanCrop` means
//  multiplying by the stride. Forget that and the crop lands at a fraction of
//  the intended position — on a stride-6 preview, a selection near the bottom of
//  the scan becomes a selection near the top. It reads as a UI bug and is a data
//  bug: the wrong region gets analysed, and every number computed from it is
//  correct about the wrong place.
//
//  The diffraction preview is NOT sampled in that way — `meanDP`/`maxDP` are
//  full detector resolution — so a rectangle there maps 1:1. The asymmetry is
//  the whole reason these two conversions are separate functions with separate
//  tests rather than one shared helper with a scale parameter.
//
//  VOCABULARY (L5 item 4, §1). What this type produces is a CROP: it changes
//  what data exists in the loaded view. It is not an ROI — `realSpaceShape`,
//  `acomRegionRadius` and strain's "current real-space ROI" select among data
//  that is already loaded. Different words, different controls, and never in the
//  same section of the UI.
//

import Foundation

/// A rectangle a user dragged, in the coordinate system of the image they
/// dragged on. Corners in any order — a drag up-and-left is as valid as one
/// down-and-right, and normalising that is this type's job rather than every
/// call site's.
nonisolated struct DragRectangle: Equatable, Sendable {
    var startX: Double
    var startY: Double
    var endX: Double
    var endY: Double

    var minX: Double { min(startX, endX) }
    var maxX: Double { max(startX, endX) }
    var minY: Double { min(startY, endY) }
    var maxY: Double { max(startY, endY) }
}

/// What the user has configured for a load that has not happened yet.
nonisolated struct LoadConfiguration: Equatable, Sendable {
    /// The dataset as stored, at full extent.
    var source: DatasetDescriptor

    /// The scan crop, already in SOURCE scan coordinates.
    var scanCrop: AxisCrop?
    /// The diffraction crop, already in SOURCE detector coordinates.
    var detectorCrop: AxisCrop?
    /// 1 = no binning.
    var detectorBin: Int = 1

    var specification: LoadSpecification {
        LoadSpecification(scanCrop: scanCrop, detectorCrop: detectorCrop,
                          detectorBin: detectorBin)
    }

    /// The view this configuration would produce, or nil if it is not loadable.
    /// Goes through the validating initialiser rather than reimplementing its
    /// rules — the configurator must not be able to offer something the loader
    /// would refuse.
    ///
    /// `try?` is correct here (v2 S7 audit): nil means "this in-progress
    /// configuration is not loadable", which the configurator renders as a
    /// disabled Load with its own captions — the thrown reasons belong to the
    /// commit path, which re-runs the validating initialiser and surfaces
    /// them there.
    var view: LoadView? {
        try? LoadView(source: source, specification: specification)
    }

    // MARK: - Turning a drag into a crop

    /// Map a rectangle dragged on the **real-space preview** to a scan crop.
    ///
    /// `strideY`/`strideX` are the preview's, from `DatasetPreview`. A preview
    /// pixel `(py, px)` is source scan position `(py * strideY, px * strideX)`,
    /// so a rectangle covering preview pixels `[a, b]` covers source positions
    /// `[a * stride, (b + 1) * stride)` — the whole footprint of the last
    /// sampled pixel, not just the position that was sampled. Taking
    /// `b * stride` instead would drop up to `stride - 1` scan rows off the
    /// bottom and right of every selection.
    static func scanCrop(
        from rectangle: DragRectangle, strideY: Int, strideX: Int,
        source: DatasetDescriptor
    ) -> AxisCrop? {
        crop(
            from: rectangle,
            scaleY: max(1, strideY), scaleX: max(1, strideX),
            limitHeight: source.ry, limitWidth: source.rx
        )
    }

    /// Map a rectangle dragged on the **diffraction preview** to a detector
    /// crop. The DP preview is full detector resolution, so this is 1:1.
    static func detectorCrop(
        from rectangle: DragRectangle, source: DatasetDescriptor
    ) -> AxisCrop? {
        crop(from: rectangle, scaleY: 1, scaleX: 1,
             limitHeight: source.qy, limitWidth: source.qx)
    }

    /// The shared half: normalise the drag, scale it, clamp it to the extent,
    /// and refuse anything that has collapsed to nothing.
    ///
    /// Clamping rather than refusing an out-of-bounds drag is deliberate: a
    /// user dragging past the edge of an image means "to the edge", and every
    /// direct-manipulation control in this app behaves that way. What is
    /// refused is an EMPTY selection, because there is no sensible reading of
    /// it and silently substituting the full extent would load something the
    /// user did not ask for.
    private static func crop(
        from rectangle: DragRectangle,
        scaleY: Int, scaleX: Int,
        limitHeight: Int, limitWidth: Int
    ) -> AxisCrop? {
        guard limitHeight > 0, limitWidth > 0 else { return nil }
        // Validated on the RAW corners, not on `minX`/`maxX`. `Swift.min` and
        // `max` compare with `<` and `>`, both of which are false against NaN,
        // so a NaN corner is silently replaced by the other one and the guard
        // would pass — a drag with a corrupt coordinate would quietly become a
        // 1x1 crop at the origin. Infinity is worse than quiet: `Int(.infinity)`
        // TRAPS, so the clamp below would crash rather than clamp. Both found by
        // the test that asserts a non-finite drag is refused.
        guard rectangle.startX.isFinite, rectangle.startY.isFinite,
              rectangle.endX.isFinite, rectangle.endY.isFinite else { return nil }
        // And bound the magnitudes before converting to Int, so a finite but
        // absurd coordinate cannot overflow on the way in.
        let bound = Double(Int32.max)
        guard abs(rectangle.startX) < bound, abs(rectangle.startY) < bound,
              abs(rectangle.endX) < bound, abs(rectangle.endY) < bound else { return nil }

        // Floor the near edge and ceil the far one, so a drag that covers any
        // part of a pixel includes that pixel. A user who has dragged a box
        // around a feature expects the feature, not a box one pixel smaller.
        let y0 = Int(rectangle.minY.rounded(.down)) * scaleY
        let x0 = Int(rectangle.minX.rounded(.down)) * scaleX
        let y1 = (Int(rectangle.maxY.rounded(.down)) + 1) * scaleY
        let x1 = (Int(rectangle.maxX.rounded(.down)) + 1) * scaleX

        let clampedY0 = min(max(0, y0), limitHeight - 1)
        let clampedX0 = min(max(0, x0), limitWidth - 1)
        let clampedY1 = min(max(clampedY0 + 1, y1), limitHeight)
        let clampedX1 = min(max(clampedX0 + 1, x1), limitWidth)

        let height = clampedY1 - clampedY0
        let width = clampedX1 - clampedX0
        guard height > 0, width > 0 else { return nil }

        // A crop that covers everything is not a crop. Returning nil rather
        // than a full-extent AxisCrop keeps `LoadSpecification.isFullExtent`
        // true, which is what makes "removing the specification promotes the
        // rehearsal to the full dataset" hold (docs/v2-scope.md §6.1).
        if clampedY0 == 0, clampedX0 == 0,
           height == limitHeight, width == limitWidth {
            return nil
        }
        return AxisCrop(yOffset: clampedY0, xOffset: clampedX0,
                        height: height, width: width)
    }

    // MARK: - What it would cost

    /// Bytes the loaded cube would occupy as float32, or nil when the
    /// configuration is not loadable.
    ///
    /// Reads return Float32 whatever the on-disk dtype (see `FourDDataSource`),
    /// so a uint16 file costs twice its file size here. That is the number that
    /// decides whether a cube can be held, and the flattering one would be the
    /// file size.
    var byteCount: Int? { view?.descriptor.byteCountAsFloat32 }

    /// Bytes at full extent, for the "instead of" half of the comparison.
    var fullExtentByteCount: Int { source.byteCountAsFloat32 }

    /// The fraction of the full cube this configuration would load, 0...1.
    var fractionOfFullExtent: Double? {
        guard let byteCount, fullExtentByteCount > 0 else { return nil }
        return Double(byteCount) / Double(fullExtentByteCount)
    }

    /// Whether this configuration would fit resident on a machine whose Metal
    /// working set is `workingSetSize`, under L2's admission rule.
    ///
    /// **Answers the question the user is actually asking at the open screen** —
    /// "will this fit?" — which is L5 item 5's hinge: when the full cube does
    /// not fit, crop and bin are how it is made to fit, and that is what turns
    /// three features into one.
    ///
    /// Returns nil when the rule cannot answer, which today is the normal case:
    /// `ResidencyAdmission.measuredWorkingSetFraction` is deliberately nil until
    /// the threshold is measured on a second machine, and the honest answer is
    /// "not decided" rather than a guess.
    ///
    /// **No production caller exists yet** — the open screen never wired this
    /// L5 hook, and with the constant nil it answers nil everywhere. It is
    /// kept, not deleted, because it is the answer surface a returning
    /// `.automatic` (docs/v2-release.md §3) plugs into. The body is only the
    /// device clamp plus `admits` — `admits` already checks `is4D` and a
    /// positive byte count, and duplicating `shouldAdmit`'s guards here is
    /// exactly the drift the harness could not see (Gate A review, 2026-08-19).
    func fitsResident(workingSetSize: UInt64, maximumBufferLength: Int) -> Bool? {
        guard let view, let fraction = ResidencyAdmission.measuredWorkingSetFraction
        else { return nil }
        let descriptor = view.descriptor
        guard descriptor.byteCountAsFloat32 <= maximumBufferLength else { return false }
        return ResidencyAdmission.admits(
            descriptor, workingSetSize: workingSetSize, fraction: fraction
        )
    }
}

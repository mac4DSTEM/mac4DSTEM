//
//  PrecipitateSegmentation.swift
//  Role: Step 3 of the precipitate chain (docs/ai-ml/precipitates.md §2) —
//        classical real-space segmentation of one dark-field / BF / ADF image
//        into precipitate objects. Background flattening, a ridge filter for
//        needles (an oriented second-derivative measure, via the Hessian —
//        §8 "ridge filter choice" is open; the eigenvalue form here is the
//        baseline) or the flattened image itself for particles, a robust
//        threshold, 8-connected components, then per-object measurement from
//        the pixel-coordinate covariance. Plain Swift, no ML (§2 step 6 is
//        out of scope here).
//
//  Coordinates: scan-domain (ry x rx), row-major, matching every other
//  scan-domain product in the app.
//

import Foundation

package nonisolated enum PrecipitateSegmentation {

    package nonisolated enum Mode: String, Sendable, CaseIterable {
        case needles = "Needles"
        case particles = "Particles"
    }

    package nonisolated struct Settings: Sendable, Equatable {
        package var mode: Mode = .needles
        /// Gaussian sigma (scan px) used to smooth before ridge/particle
        /// filtering. Background flattening uses 8x this sigma.
        package var ridgeSigmaPx: Float = 1.5
        /// Threshold, in robust-sigma units (1.4826 x MAD) above the median
        /// of the filtered image.
        package var thresholdSigmas: Float = 3
        package var minimumAreaPx: Int = 6
        package var minimumLengthPx: Float = 4

        // Bare init (not a full memberwise init, unlike `Object`): callers
        // start from the defaults above and mutate the fields they need,
        // matching the API contract this type was specified against.
        package nonisolated init() {}
    }

    /// One segmented object. `lengthPx`/`widthPx` are the extents along and
    /// across the principal axis of the pixel-coordinate covariance, end to
    /// end: the range of the members' projections + 1, over members at or
    /// above half the object's peak footprint value (see `measure`). Not a
    /// moment estimate (4·√eigenvalue, skimage's `regionprops` convention).
    package nonisolated struct Object: Sendable, Identifiable, Equatable {
        package let id: Int
        /// Row-major pixel indices into the segmented image, ascending.
        package let pixelIndices: [Int]
        /// Pixel count of the thresholded detection mask — identical to
        /// `pixelIndices.count`, and NOT the drawn area of the underlying
        /// object: on the noise-free needle fixture the mask runs ~2x the
        /// drawn bar, because the ridge response spreads past the object's
        /// own edges (open question for the owner, recorded in
        /// `docs/archive/v3/ai-gateD-2026-09-06/gateD-C3.md` §area). `lengthPx`/`widthPx` are measured on
        /// the narrower half-maximum footprint instead, so `area` is NOT
        /// `lengthPx * widthPx`.
        package let area: Int
        package let centroidX: Float
        package let centroidY: Float
        package let lengthPx: Float
        package let widthPx: Float
        /// Orientation of the long axis, folded into (-90, 90]: 0 = +x, and
        /// the angle increases from +x toward +y. The frame is image
        /// coordinates — increasing column = +x, increasing row = +y — so +y
        /// points DOWN the screen and a positive angle is therefore
        /// mathematically positive in (x, y) but reads CLOCKWISE on screen.
        /// (The comment here said "counter-clockwise" until 2026-09-06; the
        /// number never changed, only the description of it.)
        package let orientationDegrees: Float
        package let touchesEdge: Bool
        package let meanIntensity: Float

        /// The inspector row's identity, in its OWN namespace — the object
        /// half of the pair described on
        /// `PrecipitateReflections.Candidate.rowIdentity`. The two `Int` id
        /// spaces overlap, so a shared `ForEach(id: \.id)` inside one
        /// `Section` let the reflection rows claim ids 1…23 and hide the
        /// objects with those ids (`docs/archive/v3/ai-gateD-2026-09-06/gateD-P6.md`).
        package nonisolated var rowIdentity: String { "precipitate.object.\(id)" }

        // Explicit so the memberwise initializer is `package` (synthesized ones are internal). // v2.5 step 2b
        package nonisolated init(
            id: Int, pixelIndices: [Int], area: Int, centroidX: Float, centroidY: Float,
            lengthPx: Float, widthPx: Float, orientationDegrees: Float,
            touchesEdge: Bool, meanIntensity: Float
        ) {
            self.id = id
            self.pixelIndices = pixelIndices
            self.area = area
            self.centroidX = centroidX
            self.centroidY = centroidY
            self.lengthPx = lengthPx
            self.widthPx = widthPx
            self.orientationDegrees = orientationDegrees
            self.touchesEdge = touchesEdge
            self.meanIntensity = meanIntensity
        }
    }

    /// The semantic roles of labels in a spatial class map. Labels are kept
    /// separate from their presentation names: this Core type only needs to
    /// know which labels are counted as precipitate, matrix, and refused.
    package nonisolated struct LabelRoles: Sendable, Equatable {
        package let precipitateClasses: Set<Int32>
        package let matrix: Set<Int32>
        package let notIndexed: Set<Int32>

        package nonisolated init(
            precipitateClasses: Set<Int32>, matrix: Set<Int32>, notIndexed: Set<Int32>
        ) {
            self.precipitateClasses = precipitateClasses
            self.matrix = matrix
            self.notIndexed = notIndexed
        }
    }

    /// Objects and statistics for one precipitate class in a label map.
    package nonisolated struct ClassObjects: Sendable, Equatable {
        package let label: Int32
        package let objects: [Object]
        package let pixelCount: Int
        /// Class pixels divided by every indexed pixel, including matrix and
        /// other indexed classes. Nil when the map has no indexed pixels.
        package let areaFraction: Double?
        package let density: PrecipitateStatistics.Density

        package nonisolated init(
            label: Int32, objects: [Object], pixelCount: Int,
            areaFraction: Double?, density: PrecipitateStatistics.Density
        ) {
            self.label = label
            self.objects = objects
            self.pixelCount = pixelCount
            self.areaFraction = areaFraction
            self.density = density
        }
    }

    /// The pure bridge from a classified scan map to per-class spatial
    /// objects. It deliberately does not attach phase names, templates, or
    /// product state; those belong to the Session product that will consume
    /// this value after the classification route has passed its ship gate.
    package nonisolated struct ClassMapObjects: Sendable, Equatable {
        package let width: Int
        package let height: Int
        package let connectivity: Int
        package let classes: [ClassObjects]
        package let matrixPixels: Int
        package let otherPixels: Int
        package let notIndexedPixels: Int
        package let analysedPixels: Int
        package let notIndexedFraction: Double?
        /// Provenance text for the density denominator. A position with an
        /// indexed verdict remains in the area even when it is neither matrix
        /// nor a selected precipitate class.
        package let analysedAreaRule: String

        package nonisolated init(
            width: Int, height: Int, connectivity: Int, classes: [ClassObjects],
            matrixPixels: Int, otherPixels: Int, notIndexedPixels: Int,
            analysedPixels: Int, notIndexedFraction: Double?, analysedAreaRule: String
        ) {
            self.width = width
            self.height = height
            self.connectivity = connectivity
            self.classes = classes
            self.matrixPixels = matrixPixels
            self.otherPixels = otherPixels
            self.notIndexedPixels = notIndexedPixels
            self.analysedPixels = analysedPixels
            self.notIndexedFraction = notIndexedFraction
            self.analysedAreaRule = analysedAreaRule
        }
    }

    /// Segment `image` into objects. `validity` (row-major, same size as
    /// `image`), when supplied, excludes pixels from ever joining an object —
    /// masked-out pixels never seed or extend a component, but still
    /// contribute to the background/threshold statistics computed over the
    /// whole image (a local hole must not bias the object it sits inside).
    package nonisolated static func segment(
        image: FloatImage, validity: [Bool]?, settings: Settings
    ) -> [Object] {
        let width = image.width, height = image.height
        let n = width * height
        guard n > 0, width >= 1, height >= 1 else { return [] }
        var valid = validity ?? [Bool](repeating: true, count: n)
        precondition(valid.count == n, "validity must match the image size")

        // Non-finite guard (Gate D + Gate B, 2026-09-11). `image` is any
        // scan-domain scalar product, and main writes Float.nan into exactly
        // those at invalid scan positions (Core/Analysis/StrainMapping.swift
        // :77,:81 and StrainFrame.swift:113) — which is why DisplayedProduct
        // derives its validityMask from `.isFinite` at all (:111).
        //
        // Two independent things break without this, both measured:
        //   1. `gaussianBlur` truncates at FOUR sigma (see its own MARK below:
        //      `radius = max(1, Int((4 * sigma).rounded()))`), so at the default
        //      backgroundSigma of 12 a single NaN poisons a 48 px half-width of
        //      the background estimate — 5 723 pixels of a 128x128 frame.
        //   2. `robustThreshold` calls `.sorted()`, and Float comparison with
        //      NaN is not a strict weak ordering, so median and MAD are
        //      undefined, and with them the threshold.
        // Guard removed, one NaN pixel on a six-needle fixture: `.needles`
        // returns 1 object of 65.2 px — a plausible wrong answer — while
        // `.particles` returns 0. The modes fail differently and only one of
        // them fails quietly; that asymmetry is why this is a fixture and not
        // a comment.
        //
        // Imputing the finite median leaves the blur and the threshold computed
        // over the whole image, which is what this function's contract above
        // promises; marking the pixels invalid keeps them out of every object.
        // When no pixel is non-finite this block does not fire, so no number
        // the engine already produced can move — Gate B attacked that claim
        // five ways and could not move a single digit.
        //
        // KNOWN LIMIT, measured and NOT fixed here (docs/open-items.md).
        // This handles SCATTERED non-finite pixels. It does not survive a large
        // contiguous invalid REGION, which is the shape StrainMapping.swift:81
        // actually writes. The imputed region is a synthetic constant, so its
        // ridge response is ~0; once it is a large enough share of the frame it
        // dominates the median AND the MAD of `filtered` and collapses the
        // threshold until background noise clears it. Measured on a six-needle
        // fixture with a masked column band: 6 objects up to 18 % masked, then
        // 9 at 25 %, 23 at 31 %, 25 at 37 % — eighteen fabricated precipitates
        // at 31 %, each with an area and a length. `valid[i] = false` cannot
        // help, because every fabricated object lies wholly in valid territory.
        // **Do not wire this engine to a product until that is resolved**; the
        // candidate remedy (threshold statistics over the finite subset) needs
        // its own Gate D, because the obvious spelling of it silently breaks
        // the caller-validity contract above.
        var pixels = image.pixels
        if pixels.contains(where: { !$0.isFinite }) {
            let finite = pixels.filter(\.isFinite).sorted()
            let fill = medianOf(finite)          // 0 when every pixel is non-finite
            for i in 0..<n where !pixels[i].isFinite {
                pixels[i] = fill
                valid[i] = false
            }
        }

        // Background flattening: subtract a large-sigma Gaussian blur.
        let backgroundSigma = 8 * settings.ridgeSigmaPx
        let background = gaussianBlur(pixels, width: width, height: height, sigma: backgroundSigma)
        var flattened = [Float](repeating: 0, count: n)
        for i in 0..<n { flattened[i] = pixels[i] - background[i] }

        let filtered: [Float]
        switch settings.mode {
        case .particles:
            filtered = gaussianBlur(flattened, width: width, height: height, sigma: settings.ridgeSigmaPx)
        case .needles:
            let smoothed = gaussianBlur(flattened, width: width, height: height, sigma: settings.ridgeSigmaPx)
            filtered = ridgeMeasure(smoothed, width: width, height: height)
        }

        let threshold = robustThreshold(filtered, sigmas: settings.thresholdSigmas)

        var mask = [Bool](repeating: false, count: n)
        for i in 0..<n where valid[i] {
            mask[i] = filtered[i] > threshold
        }

        let components = connectedComponents(mask: mask, width: width, height: height)

        var scored: [(area: Int, object: Object)] = []
        for members in components {
            let area = members.count
            guard area >= settings.minimumAreaPx else { continue }

            let object = measure(
                members: members, width: width, height: height,
                footprintValues: flattened, intensity: pixels
            )

            if settings.mode == .needles, object.lengthPx < settings.minimumLengthPx { continue }

            scored.append((area, object))
        }

        scored.sort { $0.area > $1.area }
        return scored.enumerated().map { index, entry in
            let o = entry.object
            return Object(
                id: index + 1, pixelIndices: o.pixelIndices, area: o.area,
                centroidX: o.centroidX, centroidY: o.centroidY,
                lengthPx: o.lengthPx, widthPx: o.widthPx,
                orientationDegrees: o.orientationDegrees,
                touchesEdge: o.touchesEdge, meanIntensity: o.meanIntensity
            )
        }
    }

    /// Object id per pixel, 0 elsewhere.
    package nonisolated static func labelImage(objects: [Object], width: Int, height: Int) -> FloatImage {
        var pixels = [Float](repeating: 0, count: width * height)
        for object in objects {
            for i in object.pixelIndices where i >= 0 && i < pixels.count {
                pixels[i] = Float(object.id)
            }
        }
        return FloatImage(width: width, height: height, pixels: pixels)
    }

    /// Split each selected class independently into 8-connected objects.
    ///
    /// The density denominator is the complete indexed scan area: matrix,
    /// selected precipitate labels, and all other indexed labels. Only labels
    /// explicitly marked `notIndexed` are refused from it. This prevents a
    /// caller from making density rise merely by hiding another indexed class.
    package nonisolated static func classObjects(
        labels: [Int32], width: Int, height: Int, roles: LabelRoles,
        pixelSize: Double?, pixelUnit: String?
    ) -> ClassMapObjects {
        precondition(width >= 0 && height >= 0, "class-map dimensions must be non-negative")
        precondition(labels.count == width * height, "labels must match class-map dimensions")
        precondition(
            roles.precipitateClasses.isDisjoint(with: roles.matrix)
                && roles.precipitateClasses.isDisjoint(with: roles.notIndexed)
                && roles.matrix.isDisjoint(with: roles.notIndexed),
            "role sets must be disjoint; labels in no set are indexed other labels"
        )

        let total = labels.count
        let notIndexedPixels = labels.count { roles.notIndexed.contains($0) }
        let matrixPixels = labels.count { roles.matrix.contains($0) }
        let analysedPixels = total - notIndexedPixels
        let precipitatePixels = labels.count { roles.precipitateClasses.contains($0) }
        let otherPixels = total - notIndexedPixels - matrixPixels - precipitatePixels
        let areaRule = "All indexed labels, including matrix and other classes, are in the analysed area; only not-indexed labels are excluded."

        var nextObjectID = 1
        let classes = roles.precipitateClasses.sorted().map { label -> ClassObjects in
            let mask = labels.map { $0 == label }
            let values = mask.map { $0 ? Float(1) : Float(0) }
            let raw = connectedComponents(mask: mask, width: width, height: height)
                .map {
                    measure(
                        members: $0, width: width, height: height,
                        footprintValues: values, intensity: values
                    )
                }
                .sorted {
                    $0.area != $1.area
                        ? $0.area > $1.area
                        : ($0.pixelIndices.first ?? 0) < ($1.pixelIndices.first ?? 0)
                }
            let objects = raw.map { object -> Object in
                defer { nextObjectID += 1 }
                return Object(
                    id: nextObjectID, pixelIndices: object.pixelIndices, area: object.area,
                    centroidX: object.centroidX, centroidY: object.centroidY,
                    lengthPx: object.lengthPx, widthPx: object.widthPx,
                    orientationDegrees: object.orientationDegrees,
                    touchesEdge: object.touchesEdge, meanIntensity: object.meanIntensity
                )
            }
            let density = PrecipitateStatistics.density(
                objects: objects, accepted: Set(objects.map(\.id)),
                analysedPixels: analysedPixels, pixelSize: pixelSize, pixelUnit: pixelUnit
            )
            let pixelCount = objects.reduce(0) { $0 + $1.area }
            return ClassObjects(
                label: label, objects: objects, pixelCount: pixelCount,
                areaFraction: analysedPixels > 0 ? Double(pixelCount) / Double(analysedPixels) : nil,
                density: density
            )
        }

        return ClassMapObjects(
            width: width, height: height, connectivity: 8, classes: classes,
            matrixPixels: matrixPixels, otherPixels: otherPixels,
            notIndexedPixels: notIndexedPixels, analysedPixels: analysedPixels,
            notIndexedFraction: total > 0 ? Double(notIndexedPixels) / Double(total) : nil,
            analysedAreaRule: areaRule
        )
    }

    // MARK: - Connected components (8-connected, iterative flood fill)

    /// Shared geometry for intensity segmentation and discrete class maps.
    /// This is the former body of `segment`'s per-component measurement,
    /// extracted without changing its calculation.
    private static func measure(
        members: [Int], width: Int, height: Int,
        footprintValues: [Float], intensity: [Float]
    ) -> Object {
        precondition(!members.isEmpty, "an object needs at least one member")
        precondition(footprintValues.count == width * height && intensity.count == width * height)
        let area = members.count
        var sumX: Float = 0, sumY: Float = 0, sumIntensity: Float = 0
        var touchesEdge = false
        for i in members {
            let row = i / width, col = i % width
            sumX += Float(col)
            sumY += Float(row)
            sumIntensity += intensity[i]
            if row == 0 || row == height - 1 || col == 0 || col == width - 1 {
                touchesEdge = true
            }
        }
        let centroidX = sumX / Float(area)
        let centroidY = sumY / Float(area)

        var cxx: Float = 0, cyy: Float = 0, cxy: Float = 0
        for i in members {
            let dx = Float(i % width) - centroidX
            let dy = Float(i / width) - centroidY
            cxx += dx * dx
            cyy += dy * dy
            cxy += dx * dy
        }
        cxx /= Float(area); cyy /= Float(area); cxy /= Float(area)

        let (_, _, axis) = principalAxis(cxx: cxx, cyy: cyy, cxy: cxy)
        let peak = members.reduce(-Float.greatestFiniteMagnitude) { max($0, footprintValues[$1]) }
        let half = 0.5 * peak
        let ax = cos(axis * .pi / 180), ay = sin(axis * .pi / 180)
        var uMin = Float.greatestFiniteMagnitude, uMax = -Float.greatestFiniteMagnitude
        var vMin = Float.greatestFiniteMagnitude, vMax = -Float.greatestFiniteMagnitude
        for i in members where footprintValues[i] >= half {
            let dx = Float(i % width) - centroidX, dy = Float(i / width) - centroidY
            let u = dx * ax + dy * ay, v = -dx * ay + dy * ax
            uMin = min(uMin, u); uMax = max(uMax, u)
            vMin = min(vMin, v); vMax = max(vMax, v)
        }
        let length = uMax > uMin ? uMax - uMin + 1 : 1
        let width_ = vMax > vMin ? vMax - vMin + 1 : 1
        return Object(
            id: 0, pixelIndices: members.sorted(), area: area,
            centroidX: centroidX, centroidY: centroidY,
            lengthPx: length, widthPx: width_, orientationDegrees: axis,
            touchesEdge: touchesEdge, meanIntensity: sumIntensity / Float(area)
        )
    }

    private static func connectedComponents(mask: [Bool], width: Int, height: Int) -> [[Int]] {
        let n = width * height
        var labelled = [Bool](repeating: false, count: n)
        var components: [[Int]] = []
        var stack: [Int] = []
        for start in 0..<n {
            guard mask[start], !labelled[start] else { continue }
            labelled[start] = true
            stack.append(start)
            var members: [Int] = []
            while let i = stack.popLast() {
                members.append(i)
                let row = i / width, col = i % width
                for dy in -1...1 {
                    for dx in -1...1 where !(dx == 0 && dy == 0) {
                        let r = row + dy, c = col + dx
                        guard r >= 0, r < height, c >= 0, c < width else { continue }
                        let j = r * width + c
                        if mask[j], !labelled[j] {
                            labelled[j] = true
                            stack.append(j)
                        }
                    }
                }
            }
            components.append(members)
        }
        return components
    }

    // MARK: - Robust threshold (median + k x 1.4826 x MAD)

    private static func robustThreshold(_ values: [Float], sigmas: Float) -> Float {
        guard !values.isEmpty else { return .greatestFiniteMagnitude }
        let median = medianOf(values.sorted())
        let deviations = values.map { abs($0 - median) }.sorted()
        let mad = medianOf(deviations)
        let robustSigma = 1.4826 * mad
        return median + sigmas * robustSigma
    }

    private static func medianOf(_ sorted: [Float]) -> Float {
        guard !sorted.isEmpty else { return 0 }
        let n = sorted.count
        if n % 2 == 1 { return sorted[n / 2] }
        return (sorted[n / 2 - 1] + sorted[n / 2]) / 2
    }

    // MARK: - Principal axis (analytic 2x2 eigen-decomposition)

    /// Returns (larger eigenvalue, smaller eigenvalue, orientation of the
    /// larger eigenvalue's eigenvector in degrees, folded into (-90, 90]).
    private static func principalAxis(cxx: Float, cyy: Float, cxy: Float) -> (Float, Float, Float) {
        let trace = cxx + cyy
        let diff = cxx - cyy
        let discriminant = max(0, diff * diff + 4 * cxy * cxy)
        let root = discriminant.squareRoot()
        let lambda1 = (trace + root) / 2
        let lambda2 = (trace - root) / 2

        var vx: Float, vy: Float
        if cxy != 0 {
            vx = lambda1 - cyy
            vy = cxy
        } else if cxx >= cyy {
            vx = 1; vy = 0
        } else {
            vx = 0; vy = 1
        }
        let norm = (vx * vx + vy * vy).squareRoot()
        if norm > 0 { vx /= norm; vy /= norm }
        var angle = atan2(vy, vx) * 180 / .pi
        while angle <= -90 { angle += 180 }
        while angle > 90 { angle -= 180 }
        return (lambda1, lambda2, angle)
    }

    // MARK: - Ridge measure (analytic 2x2 Hessian eigen-decomposition)

    /// Bright-ridge strength: the larger-magnitude eigenvalue of the pixel
    /// Hessian when it is negative (a bright ridge curves sharply downward
    /// across its width), clamped to zero otherwise so troughs and flat
    /// regions never register.
    private static func ridgeMeasure(_ src: [Float], width: Int, height: Int) -> [Float] {
        var out = [Float](repeating: 0, count: width * height)
        func at(_ row: Int, _ col: Int) -> Float {
            let r = min(max(row, 0), height - 1)
            let c = min(max(col, 0), width - 1)
            return src[r * width + c]
        }
        for row in 0..<height {
            for col in 0..<width {
                let center = at(row, col)
                let hxx = at(row, col + 1) - 2 * center + at(row, col - 1)
                let hyy = at(row + 1, col) - 2 * center + at(row - 1, col)
                let hxy = (
                    at(row + 1, col + 1) - at(row + 1, col - 1)
                    - at(row - 1, col + 1) + at(row - 1, col - 1)
                ) / 4
                let trace = hxx + hyy
                let diff = hxx - hyy
                let discriminant = max(0, diff * diff + 4 * hxy * hxy)
                let root = discriminant.squareRoot()
                let lambdaMin = (trace - root) / 2   // most negative eigenvalue
                out[row * width + col] = max(0, -lambdaMin)
            }
        }
        return out
    }

    // MARK: - Separable Gaussian blur (reflect boundary, truncated at 4 sigma)

    private static func gaussianBlur(_ src: [Float], width: Int, height: Int, sigma: Float) -> [Float] {
        guard sigma > 0 else { return src }
        let radius = max(1, Int((4 * sigma).rounded()))
        var taps = [Float](repeating: 0, count: 2 * radius + 1)
        var sum: Float = 0
        for i in -radius...radius {
            let v = exp(-Float(i * i) / (2 * sigma * sigma))
            taps[i + radius] = v
            sum += v
        }
        for i in taps.indices { taps[i] /= sum }

        func reflected(_ value: Int, _ count: Int) -> Int {
            var v = value
            while v < 0 || v >= count {
                v = v < 0 ? -v - 1 : 2 * count - v - 1
            }
            return v
        }

        var temp = [Float](repeating: 0, count: width * height)
        for row in 0..<height {
            for col in 0..<width {
                var acc: Float = 0
                for k in -radius...radius {
                    acc += taps[k + radius] * src[row * width + reflected(col + k, width)]
                }
                temp[row * width + col] = acc
            }
        }
        var out = [Float](repeating: 0, count: width * height)
        for col in 0..<width {
            for row in 0..<height {
                var acc: Float = 0
                for k in -radius...radius {
                    acc += taps[k + radius] * temp[reflected(row + k, height) * width + col]
                }
                out[row * width + col] = acc
            }
        }
        return out
    }
}

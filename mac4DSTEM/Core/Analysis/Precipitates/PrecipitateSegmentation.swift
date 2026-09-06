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

    /// One segmented object. `lengthPx`/`widthPx` are the pixel extents along and across the principal axis (end to end); the earlier wording below described a moment estimate that is no longer used. Historically: the principal-axis
    /// extents of an ellipse with the same normalized second moments as the
    /// pixel set (4 x sqrt of the covariance eigenvalues — the skimage
    /// `regionprops` convention: this reproduces the true axis length for a
    /// uniformly-filled ellipse).
    package nonisolated struct Object: Sendable, Identifiable, Equatable {
        package let id: Int
        /// Row-major pixel indices into the segmented image, ascending.
        package let pixelIndices: [Int]
        /// Pixel count of the thresholded detection mask — identical to
        /// `pixelIndices.count`, and NOT the drawn area of the underlying
        /// object: on the noise-free needle fixture the mask runs ~2x the
        /// drawn bar, because the ridge response spreads past the object's
        /// own edges (open question for the owner, recorded in
        /// `fix-c/gateD-C3.md` §area). `lengthPx`/`widthPx` are measured on
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
        /// objects with those ids (`fix-b/gateD-P6.md`).
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
        let valid = validity ?? [Bool](repeating: true, count: n)
        precondition(valid.count == n, "validity must match the image size")

        // Background flattening: subtract a large-sigma Gaussian blur.
        let backgroundSigma = 8 * settings.ridgeSigmaPx
        let background = gaussianBlur(image.pixels, width: width, height: height, sigma: backgroundSigma)
        var flattened = [Float](repeating: 0, count: n)
        for i in 0..<n { flattened[i] = image.pixels[i] - background[i] }

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

            var sumX: Float = 0, sumY: Float = 0, sumIntensity: Float = 0
            var touchesEdge = false
            for i in members {
                let row = i / width, col = i % width
                sumX += Float(col)
                sumY += Float(row)
                sumIntensity += image.pixels[i]
                if row == 0 || row == height - 1 || col == 0 || col == width - 1 {
                    touchesEdge = true
                }
            }
            let centroidX = sumX / Float(area)
            let centroidY = sumY / Float(area)

            var cxx: Float = 0, cyy: Float = 0, cxy: Float = 0
            for i in members {
                let row = i / width, col = i % width
                let dx = Float(col) - centroidX
                let dy = Float(row) - centroidY
                cxx += dx * dx
                cyy += dy * dy
                cxy += dx * dy
            }
            cxx /= Float(area); cyy /= Float(area); cxy /= Float(area)

            let (_, _, axis) = principalAxis(cxx: cxx, cyy: cyy, cxy: cxy)
            // Length and width are the pixel EXTENTS along and across the principal
            // axis (end to end, the number a microscopist means), not 4·sqrt of the
            // covariance eigenvalues: that moment estimate read the drawn needles of
            // the fixture ~1.5x too long (build 2026-09-07), because a ridge response
            // is not a uniform bar and the tips spread with the filter's smoothing.
            // Measured on the IMAGE, not on the filter response: the ridge measure's
            // smoothing spreads ~4 px past each tip (the fixture's two shortest needles
            // read 8 px long, 2026-09-07). The mask stays the detection; the extents are
            // taken over the member pixels whose flattened intensity is at least half
            // the object's peak — the half-maximum footprint, which the filter does not
            // widen.
            let peak = members.reduce(-Float.greatestFiniteMagnitude) { max($0, flattened[$1]) }
            let half = 0.5 * peak
            let ax = cos(axis * .pi / 180), ay = sin(axis * .pi / 180)
            var uMin = Float.greatestFiniteMagnitude, uMax = -Float.greatestFiniteMagnitude
            var vMin = Float.greatestFiniteMagnitude, vMax = -Float.greatestFiniteMagnitude
            for i in members where flattened[i] >= half {
                let dx = Float(i % width) - centroidX, dy = Float(i / width) - centroidY
                let u = dx * ax + dy * ay, v = -dx * ay + dy * ax
                uMin = min(uMin, u); uMax = max(uMax, u); vMin = min(vMin, v); vMax = max(vMax, v)
            }
            let length = uMax > uMin ? uMax - uMin + 1 : 1
            let width_ = vMax > vMin ? vMax - vMin + 1 : 1

            if settings.mode == .needles, length < settings.minimumLengthPx { continue }

            scored.append((area, Object(
                id: 0, pixelIndices: members.sorted(), area: area,
                centroidX: centroidX, centroidY: centroidY,
                lengthPx: length, widthPx: width_,
                orientationDegrees: axis,
                touchesEdge: touchesEdge,
                meanIntensity: sumIntensity / Float(area)
            )))
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

    // MARK: - Connected components (8-connected, iterative flood fill)

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

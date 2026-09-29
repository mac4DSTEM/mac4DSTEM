//
//  PrecipitateSegmentation.swift
//  Role: Step 3 of the precipitate chain (docs/ai-ml/precipitates.md §2) —
//        splits a classified scan map into 8-connected precipitate objects
//        per class and measures each from its pixel-coordinate covariance
//        (`classObjects`). The image-domain segmenter (background flatten,
//        Hessian ridge filter, robust threshold) was retired 2026-09-30:
//        unwired, four open defects (docs/archive/closed-items-2026-09.md,
//        "Precipitate segmentation defects").
//
//  Coordinates: scan-domain (ry x rx), row-major, matching every other
//  scan-domain product in the app.
//

import Foundation

package nonisolated enum PrecipitateSegmentation {

    /// One segmented object. `lengthPx`/`widthPx` are the extents along and
    /// across the principal axis of the pixel-coordinate covariance, end to
    /// end: the range of the members' projections + 1, over members at or
    /// above half the object's peak footprint value (see `measure`; 1 on a class map, so every member). Not a
    /// moment estimate (4·√eigenvalue, skimage's `regionprops` convention).
    package nonisolated struct Object: Sendable, Identifiable, Equatable {
        package let id: Int
        /// Row-major pixel indices into the class map, ascending.
        package let pixelIndices: [Int]
        /// Pixel count of the object's 8-connected component —
        /// identical to `pixelIndices.count`. `lengthPx`/`widthPx` are the
        /// projection extents (see the type comment), so `area` is NOT
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
                analysedPixels: analysedPixels, frameWidth: width, frameHeight: height,
                pixelSize: pixelSize, pixelUnit: pixelUnit
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

    /// Per-component geometry for a discrete class map (`classObjects`).
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
}

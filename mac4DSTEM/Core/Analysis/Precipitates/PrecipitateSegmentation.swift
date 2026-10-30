//
//  PrecipitateSegmentation.swift
//  Role: Step 3 of the precipitate chain (the archived notes §2) —
//        splits a classified scan map into 8-connected precipitate objects
//        per class (`classObjects`). Since ImagoKit 0.7.0 (suite task 39) the labelling, every
//        measurement (area, centroid, extents, perimeter, equivalent diameter, solidity, Feret) and the
//        areal density are the kit's (`Segmentation.label`, `regionProperties`,
//        `ObjectStatistics.arealDensity`); what stays here is the app's logic: the class map's roles,
//        the object ids across classes, the order, and the analysed-area rule. The image-domain
//        segmenter was retired 2026-09-30.
//
//  Coordinates: scan-domain (ry x rx), row-major, matching every other
//  scan-domain product in the app.
//

import Foundation
import ImagoCore

package nonisolated enum PrecipitateSegmentation {

    /// One segmented object. `lengthPx` is the needle length: scikit-image's `feret_diameter_max`, the largest caliper distance
    /// (since task 39; it was the extent along the principal axis plus 1 px, which differs by under 1 px on diagonals).
    /// `widthPx` is the extent across the principal axis, end to end (the range of the members' projections + 1).
    /// `axisMajorLengthPx` is 4·√λ1 of the inertia tensor (skimage's `axis_major_length`), kept beside it.
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
        /// scikit-image `perimeter` (4-neighbourhood), `equivalent_diameter_area`, `axis_major_length`, `solidity`: the kit's.
        package let perimeterPx: Double
        package let equivalentDiameterPx: Double
        package let axisMajorLengthPx: Double
        package let solidity: Double
        /// The kit's measurements of this object (`Segmentation.regionProperties`); the class's Feret summary is the kit's `ObjectStatistics.feretSummary` over these.
        package let region: RegionProperties?

        /// The inspector row's identity, in its OWN namespace — the object
        /// half of the pair described on
        /// `PrecipitateReflections.Candidate.rowIdentity`. The two `Int` id
        /// spaces overlap, so a shared `ForEach(id: \.id)` inside one
        /// `Section` let the reflection rows claim ids 1…23 and hide the
        /// objects with those ids.
        package nonisolated var rowIdentity: String { "precipitate.object.\(id)" }

        // Explicit so the memberwise initializer is `package` (synthesized ones are internal). // v2.5 step 2b
        package nonisolated init(
            id: Int, pixelIndices: [Int], area: Int, centroidX: Float, centroidY: Float,
            lengthPx: Float, widthPx: Float, orientationDegrees: Float,
            touchesEdge: Bool, meanIntensity: Float,
            perimeterPx: Double = 0, equivalentDiameterPx: Double = 0, axisMajorLengthPx: Double? = nil, solidity: Double = 1,
            region: RegionProperties? = nil
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
            self.perimeterPx = perimeterPx
            self.equivalentDiameterPx = equivalentDiameterPx
            self.axisMajorLengthPx = axisMajorLengthPx ?? Double(lengthPx)
            self.solidity = solidity
            self.region = region
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
        package let density: ObjectStatistics.ArealDensity

        package nonisolated init(
            label: Int32, objects: [Object], pixelCount: Int,
            areaFraction: Double?, density: ObjectStatistics.ArealDensity
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
            let objects = Self.objects(of: labels.map { $0 == label }, width: width, height: height, firstID: nextObjectID)
            nextObjectID += objects.count
            let density = Self.density(objects: objects, accepted: Set(objects.map(\.id)),
                                       analysedPixels: analysedPixels, width: width, height: height,
                                       pixelSize: pixelSize, pixelUnit: pixelUnit)
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

    // MARK: - The kit's objects

    /// The 8-connected objects of one class's mask, measured by ImagoKit, largest first (ties: the earlier first pixel), ids
    /// `firstID`... in that order.
    package nonisolated static func objects(of mask: [Bool], width: Int, height: Int, firstID: Int) -> [Object] {
        guard width > 0, height > 0, let image = try? Segmentation.label(mask, width: width, height: height, connectivity: .eight),
              let properties = try? Segmentation.regionProperties(image) else { return [] }
        var members = [[Int]](repeating: [], count: image.count)
        for (i, l) in image.labels.enumerated() where l > 0 { members[Int(l) - 1].append(i) }   // ascending
        let sorted = properties
            .map { (p: $0, pixels: members[Int($0.moments.label) - 1]) }
            .sorted {
                $0.p.moments.area != $1.p.moments.area
                    ? $0.p.moments.area > $1.p.moments.area
                    : ($0.pixels.first ?? 0) < ($1.pixels.first ?? 0)
            }
        return sorted.enumerated().map { index, entry in
            let m = entry.p.moments
            return Object(
                id: firstID + index, pixelIndices: entry.pixels, area: m.area,
                centroidX: Float(m.centroidCol), centroidY: Float(m.centroidRow),
                lengthPx: Float(entry.p.feretDiameterMax), widthPx: Float(m.widthPx),
                orientationDegrees: Float(m.orientationDegrees),
                touchesEdge: m.touchesEdge, meanIntensity: 1,
                perimeterPx: entry.p.perimeter, equivalentDiameterPx: entry.p.equivalentDiameterArea,
                axisMajorLengthPx: m.axisMajorLength, solidity: entry.p.solidity, region: entry.p)
        }
    }

    /// The objects as a kit label image: object `i` of `objects` is label `i + 1`.
    package nonisolated static func kitLabels(of objects: [Object], width: Int, height: Int) -> Segmentation.LabelImage {
        var labels = [Int32](repeating: 0, count: width * height)
        for (index, object) in objects.enumerated() {
            for i in object.pixelIndices where i >= 0 && i < labels.count { labels[i] = Int32(index + 1) }
        }
        return Segmentation.LabelImage(width: width, height: height, labels: labels, count: objects.count)
    }

    /// The class's density from the kit: edge-corrected, no scale no density. `accepted` are object ids.
    package nonisolated static func density(
        objects: [Object], accepted: Set<Int>, analysedPixels: Int, width: Int, height: Int,
        pixelSize: Double?, pixelUnit: String?
    ) -> ObjectStatistics.ArealDensity {
        let image = kitLabels(of: objects, width: width, height: height)
        let labels = Set(objects.enumerated().filter { accepted.contains($0.element.id) }.map { Int32($0.offset + 1) })
        // The frame is the label image and `analysedPixels` is within it by construction; the kit refuses only a malformed image.
        return try! ObjectStatistics.arealDensity(labels: image, accepted: labels, analysedPixels: analysedPixels,
                                                  pixelSize: pixelSize, pixelUnit: pixelUnit)
    }
}

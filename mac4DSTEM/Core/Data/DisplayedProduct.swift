import Foundation

/// Immutable description of the scientific product presented by the viewer.
/// Pixel payload, coordinate domain, validity, units, provenance, and fit
/// evidence travel together so UI code never has to infer semantics from a
/// display title or array dimensions.
package enum ProductDomain: String, Codable, Sendable {
    case scan
    case detector
    case reconstruction
}

package enum ProductQuantitativeStatus: String, Codable, Sendable {
    case quantitative
    case relative
    case exploratory
    case categorical
}

package struct ProductSampling: Equatable, Sendable {
    package let row: Double?
    package let column: Double?
    package let units: String?

    // Explicit so the memberwise initializer is `package` (synthesized ones are internal). // v2.5 step 2b
    package init(row: Double?, column: Double?, units: String?) {
        self.row = row
        self.column = column
        self.units = units
    }
}

package enum ProductPayload {
    case scalar(FloatImage)
    case rgba(RGBAImage)

    package var dimensions: (width: Int, height: Int) {
        switch self {
        case .scalar(let image): (image.width, image.height)
        case .rgba(let image): (image.width, image.height)
        }
    }
}

package struct ProductQualityField {
    package let name: String
    package let units: String
    package let image: FloatImage

    // Explicit so the memberwise initializer is `package` (synthesized ones are internal). // v2.5 step 2b
    package init(name: String, units: String, image: FloatImage) {
        self.name = name
        self.units = units
        self.image = image
    }
}

package struct ProductOverlayDescriptor: Equatable, Sendable {
    package let kind: String
    package let provenance: String

    // Explicit so the memberwise initializer is `package` (synthesized ones are internal). // v2.5 step 2b
    package init(kind: String, provenance: String) {
        self.kind = kind
        self.provenance = provenance
    }
}

package struct DisplayedProduct {
    package let kind: String
    package let displayName: String
    package let payload: ProductPayload
    package let domain: ProductDomain
    package let validityMask: [Bool]
    package let qualityFields: [ProductQualityField]
    package let sampling: ProductSampling
    package let valueUnits: String
    package let quantitativeStatus: ProductQuantitativeStatus
    package let provenance: [String: String]
    package let overlays: [ProductOverlayDescriptor]

    package var width: Int { payload.dimensions.width }
    package var height: Int { payload.dimensions.height }

    package init(
        kind: String, displayName: String, payload: ProductPayload,
        domain: ProductDomain, validityMask: [Bool]? = nil,
        qualityFields: [ProductQualityField] = [], sampling: ProductSampling,
        valueUnits: String, quantitativeStatus: ProductQuantitativeStatus,
        provenance: [String: String] = [:], overlays: [ProductOverlayDescriptor] = []
    ) {
        self.kind = kind
        self.displayName = displayName
        self.payload = payload
        self.domain = domain
        let count = payload.dimensions.width * payload.dimensions.height
        if let validityMask, validityMask.count == count {
            self.validityMask = validityMask
        } else if case .scalar(let image) = payload {
            self.validityMask = image.pixels.map(\.isFinite)
        } else {
            self.validityMask = [Bool](repeating: true, count: count)
        }
        self.qualityFields = qualityFields.filter {
            $0.image.width == payload.dimensions.width
                && $0.image.height == payload.dimensions.height
        }
        self.sampling = sampling
        self.valueUnits = valueUnits
        self.quantitativeStatus = quantitativeStatus
        var recorded = provenance
        recorded["display_domain"] = domain.rawValue
        recorded["quantitative_status"] = quantitativeStatus.rawValue
        self.provenance = recorded
        self.overlays = overlays
    }

    package func sample(x: Int, y: Int) -> ProductSample? {
        guard x >= 0, y >= 0, x < width, y < height else { return nil }
        let index = y * width + x
        guard validityMask[index] else {
            return ProductSample(x: x, y: y, value: nil, units: valueUnits, quality: [:])
        }
        var quality: [String: Float] = [:]
        for field in qualityFields {
            let value = field.image.pixels[index]
            if value.isFinite { quality[field.name] = value }
        }
        let value: Float?
        switch payload {
        case .scalar(let image):
            let candidate = image.pixels[index]
            value = candidate.isFinite ? candidate : nil
        case .rgba:
            value = nil
        }
        return ProductSample(x: x, y: y, value: value, units: valueUnits, quality: quality)
    }
}

package struct ProductSample: Equatable {
    package let x: Int
    package let y: Int
    package let value: Float?
    package let units: String
    package let quality: [String: Float]

    package var accessibilityText: String {
        guard let value else { return "X \(x), Y \(y): no data" }
        return "X \(x), Y \(y): \(value) \(units)"
    }

    // Explicit so the memberwise initializer is `package` (synthesized ones are internal). // v2.5 step 2b
    package init(x: Int, y: Int, value: Float?, units: String, quality: [String: Float]) {
        self.x = x
        self.y = y
        self.value = value
        self.units = units
        self.quality = quality
    }
}

package enum ProductComparison {
    package enum Compatibility: Equatable {
        case compatible
        case incompatible(String)
    }

    package static func compatibility(_ lhs: DisplayedProduct, _ rhs: DisplayedProduct)
        -> Compatibility {
        guard case .scalar = lhs.payload, case .scalar = rhs.payload else {
            return .incompatible("Difference requires two scalar products.")
        }
        guard lhs.width == rhs.width, lhs.height == rhs.height else {
            return .incompatible("Pixel dimensions differ.")
        }
        guard lhs.domain == rhs.domain else {
            return .incompatible("Coordinate domains differ.")
        }
        guard lhs.valueUnits == rhs.valueUnits else {
            return .incompatible("Value units differ.")
        }
        guard lhs.sampling == rhs.sampling else {
            return .incompatible("Axis sampling differs.")
        }
        guard lhs.quantitativeStatus == rhs.quantitativeStatus else {
            return .incompatible("Quantitative status differs.")
        }
        return .compatible
    }

    package static func difference(_ lhs: DisplayedProduct, _ rhs: DisplayedProduct)
        -> DisplayedProduct? {
        guard compatibility(lhs, rhs) == .compatible,
              case .scalar(let a) = lhs.payload,
              case .scalar(let b) = rhs.payload else { return nil }
        var pixels = [Float](repeating: .nan, count: a.pixels.count)
        var valid = [Bool](repeating: false, count: pixels.count)
        for index in pixels.indices where lhs.validityMask[index] && rhs.validityMask[index] {
            let av = a.pixels[index], bv = b.pixels[index]
            guard av.isFinite, bv.isFinite else { continue }
            pixels[index] = av - bv
            valid[index] = true
        }
        return DisplayedProduct(
            kind: "difference", displayName: "\(lhs.displayName) − \(rhs.displayName)",
            payload: .scalar(FloatImage(width: a.width, height: a.height, pixels: pixels)),
            domain: lhs.domain, validityMask: valid, sampling: lhs.sampling,
            valueUnits: lhs.valueUnits, quantitativeStatus: lhs.quantitativeStatus,
            provenance: ["left_kind": lhs.kind, "right_kind": rhs.kind]
        )
    }

    package static func provenanceDifferences(_ lhs: DisplayedProduct, _ rhs: DisplayedProduct)
        -> [(key: String, left: String?, right: String?)] {
        Set(lhs.provenance.keys).union(rhs.provenance.keys).sorted().compactMap { key in
            let left = lhs.provenance[key], right = rhs.provenance[key]
            return left == right ? nil : (key, left, right)
        }
    }
}

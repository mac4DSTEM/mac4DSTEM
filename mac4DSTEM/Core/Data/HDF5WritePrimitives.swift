import Darwin
import Foundation
import FormatoHDF5
import SpectroCore

//
//  HDF5WritePrimitives.swift
//  Role: the small HDF5 write and read helpers every sidecar and export writer shares (groups, string and scalar attributes
//        and datasets, link listing), over `HDF5WriteLibrary`. Split out of BraggVectorEMDWriter.swift (2026-10-20).
//

nonisolated extension BraggVectorEMDWriter {
    static func createGroup(
        _ name: String, in parent: hid_t, hdf5 h5: HDF5WriteLibrary
    ) throws -> hid_t {
        let id = name.withCString {
            h5.h5gcreate2(parent, $0, h5DefaultProperty, h5DefaultProperty, h5DefaultProperty)
        }
        guard id >= 0 else { throw WriterError.hdf5("creating group \(name)") }
        return id
    }

    static func writeNodeAttributes(
        groupType: String, pythonClass: String, on object: hid_t, hdf5 h5: HDF5WriteLibrary
    ) throws {
        try writeStringAttribute("emd_group_type", value: groupType, on: object, hdf5: h5)
        try writeStringAttribute("python_class", value: pythonClass, on: object, hdf5: h5)
    }

    static func makeVariableStringType(_ h5: HDF5WriteLibrary) throws -> hid_t {
        let type = h5.h5tcopy(h5.stringC1)
        guard type >= 0,
              h5.h5tsetSize(type, UInt.max) >= 0,
              h5.h5tsetCset(type, h5UTF8CharacterSet) >= 0 else {
            if type >= 0 { _ = h5.h5tclose(type) }
            throw WriterError.hdf5("creating a UTF-8 string type")
        }
        return type
    }

    static func writeStringAttribute(
        _ name: String, value: String, on object: hid_t, hdf5 h5: HDF5WriteLibrary
    ) throws {
        let type = try makeVariableStringType(h5)
        defer { _ = h5.h5tclose(type) }
        let space = h5.h5screate(h5ScalarDataspace)
        guard space >= 0 else { throw WriterError.hdf5("creating attribute \(name)") }
        defer { _ = h5.h5sclose(space) }
        let attribute = name.withCString {
            h5.h5acreate2(object, $0, type, space, h5DefaultProperty, h5DefaultProperty)
        }
        guard attribute >= 0 else { throw WriterError.hdf5("creating attribute \(name)") }
        defer { _ = h5.h5aclose(attribute) }
        let status = value.withCString { characters in
            var pointer: UnsafePointer<CChar>? = characters
            return withUnsafePointer(to: &pointer) { h5.h5awrite(attribute, type, $0) }
        }
        guard status >= 0 else { throw WriterError.hdf5("writing attribute \(name)") }
    }

    // try? OK: serializing a [String: String] that
    // `isValidJSONObject` just accepted cannot fail; the guard is belt and
    // braces around an unreachable branch, and nil means "write no
    // provenance attribute", which reads back as an absent one.
    static func encodeProvenance(_ values: [String: String]) -> String? {
        guard !values.isEmpty,
              JSONSerialization.isValidJSONObject(values),
              let data = try? JSONSerialization.data(
                withJSONObject: values, options: [.sortedKeys]
              ) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // try? accepted with a stated limit: a malformed
    // provenance attribute decodes as EMPTY — visibly absent labels, which a
    // reader can see and question. This is the opposite shape from the
    // specification/recipe attributes above, where absent has a load-bearing
    // meaning ("full extent" / "no recipe") and malformed must therefore
    // refuse (`WriterError.malformedAttribute`); absent provenance asserts
    // nothing.
    static func decodeProvenance(_ value: String?) -> [String: String] {
        guard let value, let data = value.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: String] else { return [:] }
        return dictionary
    }

    static func writeScalarAttribute<T>(
        _ name: String, value: T, type: hid_t, on object: hid_t, hdf5 h5: HDF5WriteLibrary
    ) throws {
        let space = h5.h5screate(h5ScalarDataspace)
        guard space >= 0 else { throw WriterError.hdf5("creating attribute \(name)") }
        defer { _ = h5.h5sclose(space) }
        let attribute = name.withCString {
            h5.h5acreate2(object, $0, type, space, h5DefaultProperty, h5DefaultProperty)
        }
        guard attribute >= 0 else { throw WriterError.hdf5("creating attribute \(name)") }
        defer { _ = h5.h5aclose(attribute) }
        var mutableValue = value
        guard withUnsafePointer(to: &mutableValue, {
            h5.h5awrite(attribute, type, UnsafeRawPointer($0))
        }) >= 0 else { throw WriterError.hdf5("writing attribute \(name)") }
    }

    static func writeScalarDataset<T>(
        _ name: String, value: inout T, type: hid_t, metadataType: String?,
        in parent: hid_t, hdf5 h5: HDF5WriteLibrary
    ) throws {
        let space = h5.h5screate(h5ScalarDataspace)
        guard space >= 0 else { throw WriterError.hdf5("creating dataset \(name)") }
        defer { _ = h5.h5sclose(space) }
        let dataset = name.withCString {
            h5.h5dcreate2(parent, $0, type, space, h5DefaultProperty,
                          h5DefaultProperty, h5DefaultProperty)
        }
        guard dataset >= 0 else { throw WriterError.hdf5("creating dataset \(name)") }
        defer { _ = h5.h5dclose(dataset) }
        guard withUnsafePointer(to: &value, {
            h5.h5dwrite(dataset, type, h5EntireDataspace, h5EntireDataspace,
                        h5DefaultProperty, UnsafeRawPointer($0))
        }) >= 0 else { throw WriterError.hdf5("writing dataset \(name)") }
        if let metadataType {
            try writeStringAttribute("type", value: metadataType, on: dataset, hdf5: h5)
        }
    }

    static func writeStringDataset(
        _ name: String, value: String, metadataType: String?,
        in parent: hid_t, hdf5 h5: HDF5WriteLibrary
    ) throws {
        let type = try makeVariableStringType(h5)
        defer { _ = h5.h5tclose(type) }
        let space = h5.h5screate(h5ScalarDataspace)
        guard space >= 0 else { throw WriterError.hdf5("creating dataset \(name)") }
        defer { _ = h5.h5sclose(space) }
        let dataset = name.withCString {
            h5.h5dcreate2(parent, $0, type, space, h5DefaultProperty,
                          h5DefaultProperty, h5DefaultProperty)
        }
        guard dataset >= 0 else { throw WriterError.hdf5("creating dataset \(name)") }
        defer { _ = h5.h5dclose(dataset) }
        let status = value.withCString { characters in
            var pointer: UnsafePointer<CChar>? = characters
            return withUnsafePointer(to: &pointer) {
                h5.h5dwrite(dataset, type, h5EntireDataspace, h5EntireDataspace,
                            h5DefaultProperty, $0)
            }
        }
        guard status >= 0 else { throw WriterError.hdf5("writing dataset \(name)") }
        if let metadataType {
            try writeStringAttribute("type", value: metadataType, on: dataset, hdf5: h5)
        }
    }

    static func writeInt64VectorDataset(
        _ name: String, values: [Int64], metadataType: String,
        in parent: hid_t, hdf5 h5: HDF5WriteLibrary
    ) throws {
        let dimensions = [hsize_t(values.count)]
        let space = dimensions.withUnsafeBufferPointer {
            h5.h5screateSimple(1, $0.baseAddress, nil)
        }
        guard space >= 0 else { throw WriterError.hdf5("creating dataset \(name)") }
        defer { _ = h5.h5sclose(space) }
        let dataset = name.withCString {
            h5.h5dcreate2(parent, $0, h5.nativeLongLong, space, h5DefaultProperty,
                          h5DefaultProperty, h5DefaultProperty)
        }
        guard dataset >= 0 else { throw WriterError.hdf5("creating dataset \(name)") }
        defer { _ = h5.h5dclose(dataset) }
        guard values.withUnsafeBytes({
            h5.h5dwrite(dataset, h5.nativeLongLong, h5EntireDataspace, h5EntireDataspace,
                        h5DefaultProperty, $0.baseAddress)
        }) >= 0 else { throw WriterError.hdf5("writing dataset \(name)") }
        try writeStringAttribute("type", value: metadataType, on: dataset, hdf5: h5)
    }

    static func writeDoubleVectorDataset(
        _ name: String, values: [Double], name dimName: String, units: String,
        in parent: hid_t, hdf5 h5: HDF5WriteLibrary
    ) throws {
        let dimensions = [hsize_t(values.count)]
        let space = dimensions.withUnsafeBufferPointer {
            h5.h5screateSimple(1, $0.baseAddress, nil)
        }
        guard space >= 0 else { throw WriterError.hdf5("creating dataset \(name)") }
        defer { _ = h5.h5sclose(space) }
        let dataset = name.withCString {
            h5.h5dcreate2(parent, $0, h5.nativeDouble, space, h5DefaultProperty,
                          h5DefaultProperty, h5DefaultProperty)
        }
        guard dataset >= 0 else { throw WriterError.hdf5("creating dataset \(name)") }
        defer { _ = h5.h5dclose(dataset) }
        guard values.withUnsafeBytes({
            h5.h5dwrite(dataset, h5.nativeDouble, h5EntireDataspace, h5EntireDataspace,
                        h5DefaultProperty, $0.baseAddress)
        }) >= 0 else { throw WriterError.hdf5("writing dataset \(name)") }
        try writeStringAttribute("name", value: dimName, on: dataset, hdf5: h5)
        try writeStringAttribute("units", value: units, on: dataset, hdf5: h5)
    }

    static func writeDoubleMatrixDataset(
        _ name: String, values: [Double], shape: [Int],
        in parent: hid_t, hdf5 h5: HDF5WriteLibrary
    ) throws {
        guard shape.count == 2, shape.allSatisfy({ $0 > 0 }),
              values.count == shape[0] * shape[1] else {
            throw WriterError.invalidDimensions("calibration matrix \(name) is inconsistent")
        }
        let dimensions = shape.map(hsize_t.init)
        let space = dimensions.withUnsafeBufferPointer {
            h5.h5screateSimple(2, $0.baseAddress, nil)
        }
        guard space >= 0 else { throw WriterError.hdf5("creating dataset \(name)") }
        defer { _ = h5.h5sclose(space) }
        let dataset = name.withCString {
            h5.h5dcreate2(parent, $0, h5.nativeDouble, space, h5DefaultProperty,
                          h5DefaultProperty, h5DefaultProperty)
        }
        guard dataset >= 0 else { throw WriterError.hdf5("creating dataset \(name)") }
        defer { _ = h5.h5dclose(dataset) }
        guard values.withUnsafeBytes({
            h5.h5dwrite(dataset, h5.nativeDouble, h5EntireDataspace, h5EntireDataspace,
                        h5DefaultProperty, $0.baseAddress)
        }) >= 0 else { throw WriterError.hdf5("writing dataset \(name)") }
        try writeStringAttribute("type", value: "array", on: dataset, hdf5: h5)
    }

    static func linkExists(
        _ path: String, in parent: hid_t, hdf5 h5: HDF5WriteLibrary
    ) -> Bool {
        path.withCString { h5.h5lexists(parent, $0, h5DefaultProperty) > 0 }
    }

    static func childLinkNames(
        in group: hid_t, hdf5 h5: HDF5WriteLibrary
    ) -> [String] {
        var childCount: hsize_t = 0
        guard h5.h5ggetNumObjects(group, &childCount) >= 0 else { return [] }
        var names = [String]()
        names.reserveCapacity(Int(childCount))
        for index in 0..<childCount {
            let length = ".".withCString { groupName in
                h5.h5lgetNameByIndex(
                    group, groupName, h5IndexByName, h5IterationIncreasing,
                    index, nil, 0, h5DefaultProperty
                )
            }
            guard length >= 0 else { continue }
            var bytes = [CChar](repeating: 0, count: length + 1)
            let read = ".".withCString { groupName in
                bytes.withUnsafeMutableBufferPointer { buffer in
                    h5.h5lgetNameByIndex(
                        group, groupName, h5IndexByName, h5IterationIncreasing,
                        index, buffer.baseAddress, buffer.count, h5DefaultProperty
                    )
                }
            }
            guard read >= 0 else { continue }
            names.append(String(cString: bytes))
        }
        return names
    }
}

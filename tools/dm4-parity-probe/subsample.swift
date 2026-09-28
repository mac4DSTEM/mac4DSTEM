//
//  tools/dm4-parity-probe/subsample.swift
//  `--subsample RAW.dm4 OUT.h5 --stride N` and `--verify-subsample RAW OUT --stride N`
//  (owner's plan, 2026-09-29: the 28 GB DM4 cannot be preprocessed whole on an
//  8 GB Mac, so keep every N-th real-space position at the FULL detector and
//  work on that).
//
//  Streaming: one scan row of kept patterns (outCols x qy x qx elements, in the
//  stored dtype) is the most this ever holds. The source is read through the
//  app's own `DM4Reader` (memory-mapped, `readPattern` per kept position, so
//  the skipped positions' pages are never touched); the output is written with
//  one HDF5 hyperslab per row.
//
//  WRITER NOT REUSED, AND WHY. The app's `BraggVectorEMDWriter.
//  writeCalibratedDataCube` is the py4DSTEM-readable datacube writer, but it is
//  `private` and always writes float32 with an integer detector bin. This file
//  writes the SAME EMD layout (same groups, attributes, dim vectors, chunking
//  (1, 1, qy, qx), calibration bundle) in the stored dtype. The layout is a
//  copy: if `writeCalibratedDataCubeFile` changes, so must this. Provenance
//  attributes `mac4dstem_subsample_*` on `datacube_root` are additions;
//  py4DSTEM ignores unknown attributes.
//
//  DEVIATION from the app's writer: dtype is the stored one (no float32
//  promotion). `DM4Reader` decodes every dtype to Float, so a dtype whose
//  values Float cannot hold is refused rather than written rounded: float64,
//  and int32/uint32 values of magnitude >= 2^24. int8/uint8/int16/uint16
//  and float32 are exact through Float.
//
import Darwin
import Foundation

/// Peak `phys_footprint` of the process so far (the kernel's own ledger),
/// which is what a full read into anonymous memory grows. A mapped file's
/// clean pages do not count in it.
nonisolated func peakFootprintMB() -> Double {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
    let kr = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
        }
    }
    guard kr == KERN_SUCCESS else { return .nan }
    return Double(info.ledger_phys_footprint_peak) / 1_048_576
}

nonisolated enum StoredType {
    case int8, uint8, int16, uint16, int32, uint32, float32

    init?(dtype: String) {
        switch dtype {
        case "int8": self = .int8
        case "uint8": self = .uint8
        case "int16": self = .int16
        case "uint16": self = .uint16
        case "int32": self = .int32
        case "uint32": self = .uint32
        case "float32": self = .float32
        default: return nil
        }
    }

    var size: Int {
        switch self {
        case .int8, .uint8: return 1
        case .int16, .uint16: return 2
        case .int32, .uint32, .float32: return 4
        }
    }

    var nativeSymbol: String {
        switch self {
        case .int8: return "H5T_NATIVE_INT8_g"
        case .uint8: return "H5T_NATIVE_UINT8_g"
        case .int16: return "H5T_NATIVE_INT16_g"
        case .uint16: return "H5T_NATIVE_UINT16_g"
        case .int32: return "H5T_NATIVE_INT32_g"
        case .uint32: return "H5T_NATIVE_UINT32_g"
        case .float32: return "H5T_NATIVE_FLOAT_g"
        }
    }

    /// Store `pattern` (Float, as `DM4Reader` decodes it) in the stored dtype
    /// at element `at` of `buffer`. Throws on any value the dtype cannot
    /// hold exactly.
    func encode(_ pattern: [Float], into buffer: UnsafeMutableRawPointer, at element: Int) throws {
        func ints<T: FixedWidthInteger>(_: T.Type, limit24: Bool) throws {
            let p = buffer.bindMemory(to: T.self, capacity: element + pattern.count) + element
            for i in 0..<pattern.count {
                let f = pattern[i]
                guard let v = T(exactly: f), !limit24 || abs(f) < 16_777_216 else {
                    throw SubsampleError.notExact("value \(f) is not exactly a \(T.self), or is ≥ 2^24 where Float32 cannot vouch for a 32-bit integer")
                }
                p[i] = v
            }
        }
        switch self {
        case .int8: try ints(Int8.self, limit24: false)
        case .uint8: try ints(UInt8.self, limit24: false)
        case .int16: try ints(Int16.self, limit24: false)
        case .uint16: try ints(UInt16.self, limit24: false)
        case .int32: try ints(Int32.self, limit24: true)
        case .uint32: try ints(UInt32.self, limit24: true)
        case .float32:
            let p = buffer.bindMemory(to: Float.self, capacity: element + pattern.count) + element
            for i in 0..<pattern.count { p[i] = pattern[i] }
        }
    }
}

nonisolated enum SubsampleError: LocalizedError {
    case notExact(String)
    case hdf5(String)
    case unsupported(String)

    var errorDescription: String? {
        switch self {
        case .notExact(let m): return "not exact through the reader: \(m)"
        case .hdf5(let m): return "HDF5: \(m)"
        case .unsupported(let m): return m
        }
    }
}

/// The HDF5 entry points the datacube writer needs, loaded like the app's own
/// (`MAC4DSTEM_HDF5_PATH`, else the bare name). Every call runs under
/// `HDF5Serial`, the process-wide lock the app's readers and writers share.
nonisolated struct SubsampleHDF5 {
    typealias H5open = @convention(c) () -> herr_t
    typealias H5Fcreate = @convention(c) (UnsafePointer<CChar>?, UInt32, hid_t, hid_t) -> hid_t
    typealias H5Close = @convention(c) (hid_t) -> herr_t
    typealias H5Gcreate2 = @convention(c) (hid_t, UnsafePointer<CChar>?, hid_t, hid_t, hid_t) -> hid_t
    typealias H5Screate = @convention(c) (Int32) -> hid_t
    typealias H5ScreateSimple = @convention(c) (Int32, UnsafePointer<hsize_t>?, UnsafePointer<hsize_t>?) -> hid_t
    typealias H5SselectHyperslab = @convention(c) (hid_t, Int32, UnsafePointer<hsize_t>?, UnsafePointer<hsize_t>?, UnsafePointer<hsize_t>?, UnsafePointer<hsize_t>?) -> herr_t
    typealias H5Dcreate2 = @convention(c) (hid_t, UnsafePointer<CChar>?, hid_t, hid_t, hid_t, hid_t, hid_t) -> hid_t
    typealias H5DgetSpace = @convention(c) (hid_t) -> hid_t
    typealias H5Dwrite = @convention(c) (hid_t, hid_t, hid_t, hid_t, hid_t, UnsafeRawPointer?) -> herr_t
    typealias H5Tcopy = @convention(c) (hid_t) -> hid_t
    typealias H5TsetSize = @convention(c) (hid_t, UInt) -> herr_t
    typealias H5TsetCset = @convention(c) (hid_t, Int32) -> herr_t
    typealias H5Acreate2 = @convention(c) (hid_t, UnsafePointer<CChar>?, hid_t, hid_t, hid_t, hid_t) -> hid_t
    typealias H5Awrite = @convention(c) (hid_t, hid_t, UnsafeRawPointer?) -> herr_t
    typealias H5Pcreate = @convention(c) (hid_t) -> hid_t
    typealias H5PsetChunk = @convention(c) (hid_t, Int32, UnsafePointer<hsize_t>?) -> herr_t

    static let defaultProperty: hid_t = 0
    static let fileTruncate: UInt32 = 0x0002
    static let scalarSpace: Int32 = 0
    static let utf8: Int32 = 1
    static let selectSet: Int32 = 0

    let fcreate: H5Fcreate
    let fclose, gclose, sclose, dclose, tclose, aclose, pclose: H5Close
    let gcreate2: H5Gcreate2
    let screate: H5Screate
    let screateSimple: H5ScreateSimple
    let sselectHyperslab: H5SselectHyperslab
    let dcreate2: H5Dcreate2
    let dgetSpace: H5DgetSpace
    let dwrite: H5Dwrite
    let tcopy: H5Tcopy
    let tsetSize: H5TsetSize
    let tsetCset: H5TsetCset
    let acreate2: H5Acreate2
    let awrite: H5Awrite
    let pcreate: H5Pcreate
    let psetChunk: H5PsetChunk
    let nativeInt: hid_t
    let nativeDouble: hid_t
    let nativeLongLong: hid_t
    let stringC1: hid_t
    let datasetCreateClass: hid_t
    let handle: UnsafeMutableRawPointer

    static func load() throws -> SubsampleHDF5 {
        let paths = [ProcessInfo.processInfo.environment["MAC4DSTEM_HDF5_PATH"], "libhdf5.dylib"].compactMap { $0 }
        var handle: UnsafeMutableRawPointer?
        for p in paths where handle == nil { handle = dlopen(p, RTLD_NOW | RTLD_LOCAL) }
        guard let handle else { throw SubsampleError.hdf5("libhdf5 not found (MAC4DSTEM_HDF5_PATH)") }
        func sym<T>(_ n: String, _: T.Type) throws -> T {
            guard let p = dlsym(handle, n) else { throw SubsampleError.hdf5("symbol \(n) missing") }
            return unsafeBitCast(p, to: T.self)
        }
        func glob(_ n: String) throws -> hid_t {
            guard let p = dlsym(handle, n) else { throw SubsampleError.hdf5("symbol \(n) missing") }
            return p.assumingMemoryBound(to: hid_t.self).pointee
        }
        _ = try sym("H5open", H5open.self)()
        return SubsampleHDF5(
            fcreate: try sym("H5Fcreate", H5Fcreate.self),
            fclose: try sym("H5Fclose", H5Close.self), gclose: try sym("H5Gclose", H5Close.self),
            sclose: try sym("H5Sclose", H5Close.self), dclose: try sym("H5Dclose", H5Close.self),
            tclose: try sym("H5Tclose", H5Close.self), aclose: try sym("H5Aclose", H5Close.self),
            pclose: try sym("H5Pclose", H5Close.self),
            gcreate2: try sym("H5Gcreate2", H5Gcreate2.self),
            screate: try sym("H5Screate", H5Screate.self),
            screateSimple: try sym("H5Screate_simple", H5ScreateSimple.self),
            sselectHyperslab: try sym("H5Sselect_hyperslab", H5SselectHyperslab.self),
            dcreate2: try sym("H5Dcreate2", H5Dcreate2.self),
            dgetSpace: try sym("H5Dget_space", H5DgetSpace.self),
            dwrite: try sym("H5Dwrite", H5Dwrite.self),
            tcopy: try sym("H5Tcopy", H5Tcopy.self),
            tsetSize: try sym("H5Tset_size", H5TsetSize.self),
            tsetCset: try sym("H5Tset_cset", H5TsetCset.self),
            acreate2: try sym("H5Acreate2", H5Acreate2.self),
            awrite: try sym("H5Awrite", H5Awrite.self),
            pcreate: try sym("H5Pcreate", H5Pcreate.self),
            psetChunk: try sym("H5Pset_chunk", H5PsetChunk.self),
            nativeInt: try glob("H5T_NATIVE_INT_g"),
            nativeDouble: try glob("H5T_NATIVE_DOUBLE_g"),
            nativeLongLong: try glob("H5T_NATIVE_LLONG_g"),
            stringC1: try glob("H5T_C_S1_g"),
            datasetCreateClass: try glob("H5P_CLS_DATASET_CREATE_ID_g"),
            handle: handle)
    }

    func native(_ symbol: String) throws -> hid_t {
        guard let p = dlsym(handle, symbol) else { throw SubsampleError.hdf5("symbol \(symbol) missing") }
        return p.assumingMemoryBound(to: hid_t.self).pointee
    }

    // MARK: EMD helpers (same shapes as BraggVectorEMDWriter's private ones)

    func group(_ name: String, in parent: hid_t) throws -> hid_t {
        let g = name.withCString { gcreate2(parent, $0, Self.defaultProperty, Self.defaultProperty, Self.defaultProperty) }
        guard g >= 0 else { throw SubsampleError.hdf5("creating group \(name)") }
        return g
    }

    private func stringType() throws -> hid_t {
        let t = tcopy(stringC1)
        guard t >= 0, tsetSize(t, UInt.max) >= 0, tsetCset(t, Self.utf8) >= 0 else {
            throw SubsampleError.hdf5("creating a UTF-8 string type")
        }
        return t
    }

    func stringAttribute(_ name: String, _ value: String, on object: hid_t) throws {
        let type = try stringType(); defer { _ = tclose(type) }
        let space = screate(Self.scalarSpace); defer { _ = sclose(space) }
        let a = name.withCString { acreate2(object, $0, type, space, Self.defaultProperty, Self.defaultProperty) }
        guard a >= 0 else { throw SubsampleError.hdf5("creating attribute \(name)") }
        defer { _ = aclose(a) }
        let status = value.withCString { chars -> herr_t in
            var pointer: UnsafePointer<CChar>? = chars
            return withUnsafePointer(to: &pointer) { awrite(a, type, $0) }
        }
        guard status >= 0 else { throw SubsampleError.hdf5("writing attribute \(name)") }
    }

    func int32Attribute(_ name: String, _ value: Int32, on object: hid_t) throws {
        let space = screate(Self.scalarSpace); defer { _ = sclose(space) }
        let a = name.withCString { acreate2(object, $0, nativeInt, space, Self.defaultProperty, Self.defaultProperty) }
        guard a >= 0 else { throw SubsampleError.hdf5("creating attribute \(name)") }
        defer { _ = aclose(a) }
        var v = value
        guard withUnsafePointer(to: &v, { awrite(a, nativeInt, $0) }) >= 0 else {
            throw SubsampleError.hdf5("writing attribute \(name)")
        }
    }

    func nodeAttributes(groupType: String, pythonClass: String, on object: hid_t) throws {
        try stringAttribute("emd_group_type", groupType, on: object)
        try stringAttribute("python_class", pythonClass, on: object)
    }

    func doubleScalarDataset(_ name: String, _ value: Double, in parent: hid_t) throws {
        let space = screate(Self.scalarSpace); defer { _ = sclose(space) }
        let d = name.withCString { dcreate2(parent, $0, nativeDouble, space, Self.defaultProperty, Self.defaultProperty, Self.defaultProperty) }
        guard d >= 0 else { throw SubsampleError.hdf5("creating dataset \(name)") }
        defer { _ = dclose(d) }
        var v = value
        guard withUnsafePointer(to: &v, { dwrite(d, nativeDouble, 0, 0, Self.defaultProperty, $0) }) >= 0 else {
            throw SubsampleError.hdf5("writing dataset \(name)")
        }
        try stringAttribute("type", "number", on: d)
    }

    func stringDataset(_ name: String, _ value: String, metadataType: String?, in parent: hid_t) throws {
        let type = try stringType(); defer { _ = tclose(type) }
        let space = screate(Self.scalarSpace); defer { _ = sclose(space) }
        let d = name.withCString { dcreate2(parent, $0, type, space, Self.defaultProperty, Self.defaultProperty, Self.defaultProperty) }
        guard d >= 0 else { throw SubsampleError.hdf5("creating dataset \(name)") }
        defer { _ = dclose(d) }
        let status = value.withCString { chars -> herr_t in
            var pointer: UnsafePointer<CChar>? = chars
            return withUnsafePointer(to: &pointer) { dwrite(d, type, 0, 0, Self.defaultProperty, $0) }
        }
        guard status >= 0 else { throw SubsampleError.hdf5("writing dataset \(name)") }
        if let metadataType { try stringAttribute("type", metadataType, on: d) }
    }

    func doubleVectorDataset(_ name: String, _ values: [Double], dimName: String, units: String, in parent: hid_t) throws {
        let dims = [hsize_t(values.count)]
        let space = dims.withUnsafeBufferPointer { screateSimple(1, $0.baseAddress, nil) }
        guard space >= 0 else { throw SubsampleError.hdf5("creating dataset \(name)") }
        defer { _ = sclose(space) }
        let d = name.withCString { dcreate2(parent, $0, nativeDouble, space, Self.defaultProperty, Self.defaultProperty, Self.defaultProperty) }
        guard d >= 0 else { throw SubsampleError.hdf5("creating dataset \(name)") }
        defer { _ = dclose(d) }
        guard values.withUnsafeBytes({ dwrite(d, nativeDouble, 0, 0, Self.defaultProperty, $0.baseAddress) }) >= 0 else {
            throw SubsampleError.hdf5("writing dataset \(name)")
        }
        try stringAttribute("name", dimName, on: d)
        try stringAttribute("units", units, on: d)
    }
}

nonisolated enum Subsample {
    /// Kept scan extent for `stride` over `n` positions: 0, N, 2N, … < n.
    static func keptCount(_ n: Int, stride: Int) -> Int { (n + stride - 1) / stride }

    static func write(raw: String, out: String, stride: Int) async throws {
        let t0 = Date()
        let reader = try await DM4Reader(path: raw)
        let d = try await reader.discoverPrimaryDataset()
        let view = LoadView(fullExtentOf: d)
        guard let type = StoredType(dtype: d.dtypeDescription) else {
            throw SubsampleError.unsupported("stored dtype \(d.dtypeDescription) cannot be carried exactly through the reader's Float32 path")
        }
        let cal = await reader.pixelCalibration()
        let (outRy, outRx) = (keptCount(d.ry, stride: stride), keptCount(d.rx, stride: stride))
        let (qy, qx) = (d.qy, d.qx)
        print("source \(d.ry)×\(d.rx)×\(qy)×\(qx) \(d.dtypeDescription) → \(outRy)×\(outRx)×\(qy)×\(qx) (stride \(stride)); "
              + "output ≈ \(outRy * outRx * qy * qx * type.size / 1_048_576) MB; \(memory())")

        let h5 = try SubsampleHDF5.load()
        let partial = out + ".partial"
        try? FileManager.default.removeItem(atPath: partial)
        var completed = false
        defer { if !completed { try? FileManager.default.removeItem(atPath: partial) } }

        // Setup (all handles that the row loop needs stay open; the lock is
        // not held across the awaits below).
        var fileID: hid_t = -1, rootG: hid_t = -1, cubeG: hid_t = -1, dataset: hid_t = -1
        try HDF5Serial.run {
            fileID = partial.withCString { h5.fcreate($0, SubsampleHDF5.fileTruncate, 0, 0) }
            guard fileID >= 0 else { throw SubsampleError.hdf5("creating \(partial)") }
            try h5.stringAttribute("emd_group_type", "file", on: fileID)
            try h5.int32Attribute("version_major", 1, on: fileID)
            try h5.int32Attribute("version_minor", 0, on: fileID)
            try h5.stringAttribute("UUID", UUID().uuidString, on: fileID)
            try h5.stringAttribute("authoring_program", "mac4DSTEM", on: fileID)
            try h5.stringAttribute("authoring_user", "", on: fileID)
            rootG = try h5.group("datacube_root", in: fileID)
            try h5.nodeAttributes(groupType: "root", pythonClass: "Root", on: rootG)
            try h5.stringAttribute("mac4dstem_subsample_source", URL(fileURLWithPath: raw).lastPathComponent, on: rootG)
            try h5.stringAttribute("mac4dstem_subsample_stride", String(stride), on: rootG)
            cubeG = try h5.group("datacube", in: rootG)
            try h5.nodeAttributes(groupType: "array", pythonClass: "DataCube", on: cubeG)

            let dims = [outRy, outRx, qy, qx].map(hsize_t.init)
            let space = dims.withUnsafeBufferPointer { h5.screateSimple(4, $0.baseAddress, nil) }
            guard space >= 0 else { throw SubsampleError.hdf5("creating the datacube dataspace") }
            defer { _ = h5.sclose(space) }
            let plist = h5.pcreate(h5.datasetCreateClass)
            guard plist >= 0 else { throw SubsampleError.hdf5("creating the chunk property list") }
            defer { _ = h5.pclose(plist) }
            let chunk = [hsize_t(1), hsize_t(1), dims[2], dims[3]]
            guard chunk.withUnsafeBufferPointer({ h5.psetChunk(plist, 4, $0.baseAddress) }) >= 0 else {
                throw SubsampleError.hdf5("configuring datacube chunks")
            }
            let native = try h5.native(type.nativeSymbol)
            dataset = "data".withCString { h5.dcreate2(cubeG, $0, native, space, 0, plist, 0) }
            guard dataset >= 0 else { throw SubsampleError.hdf5("creating the datacube dataset") }
            try h5.stringAttribute("units", "pixel intensity", on: dataset)

            // Calibration: pixel sizes/units as the source states them; the
            // real-space step is the source's times the stride.
            let rStep = (cal?.rSize).map { $0 * Double(stride) } ?? 1
            let qStep = cal?.qSize ?? 1
            let rUnits = cal?.rUnits ?? "pixels"
            let qUnits = cal?.qUnits ?? "pixels"
            func linear(_ count: Int, _ step: Double) -> [Double] { count > 1 ? [0, step] : [0] }
            try h5.doubleVectorDataset("dim0", linear(outRy, rStep), dimName: "Rx", units: rUnits, in: cubeG)
            try h5.doubleVectorDataset("dim1", linear(outRx, rStep), dimName: "Ry", units: rUnits, in: cubeG)
            try h5.doubleVectorDataset("dim2", linear(qy, qStep), dimName: "Qx", units: qUnits, in: cubeG)
            try h5.doubleVectorDataset("dim3", linear(qx, qStep), dimName: "Qy", units: qUnits, in: cubeG)

            let bundle = try h5.group("metadatabundle", in: rootG)
            defer { _ = h5.gclose(bundle) }
            try h5.stringAttribute("emd_group_type", "metadatabundle", on: bundle)
            let calGroup = try h5.group("calibration", in: bundle)
            defer { _ = h5.gclose(calGroup) }
            try h5.nodeAttributes(groupType: "metadata", pythonClass: "Calibration", on: calGroup)
            if let v = cal?.qSize { try h5.doubleScalarDataset("Q_pixel_size", v, in: calGroup) }
            if let v = cal?.qUnits { try h5.stringDataset("Q_pixel_units", v, metadataType: "string", in: calGroup) }
            if let v = cal?.rSize { try h5.doubleScalarDataset("R_pixel_size", v * Double(stride), in: calGroup) }
            if let v = cal?.rUnits { try h5.stringDataset("R_pixel_units", v, metadataType: "string", in: calGroup) }
            try h5.stringDataset("_root_treepath", "", metadataType: "string", in: calGroup)
            let targets = try h5.group("_target_paths", in: calGroup)
            defer { _ = h5.gclose(targets) }
            try h5.stringAttribute("type", "list_of_strings", on: targets)
            try h5.int32Attribute("length", 1, on: targets)
            try h5.stringDataset("0", "/datacube", metadataType: nil, in: targets)
        }
        defer { HDF5Serial.run {
            if dataset >= 0 { _ = h5.dclose(dataset) }
            if cubeG >= 0 { _ = h5.gclose(cubeG) }
            if rootG >= 0 { _ = h5.gclose(rootG) }
            if fileID >= 0 { _ = h5.fclose(fileID) }
        } }

        let patternElements = qy * qx
        var rowBytes = [UInt8](repeating: 0, count: outRx * patternElements * type.size)
        var lastReported = -1
        var footprintPeak = memoryMB().footprint
        for i in 0..<outRy {
            for j in 0..<outRx {
                let p = try await reader.readPattern(view, ry: i * stride, rx: j * stride)
                try rowBytes.withUnsafeMutableBytes {
                    try type.encode(p, into: $0.baseAddress!, at: j * patternElements)
                }
            }
            try HDF5Serial.run {
                let space = h5.dgetSpace(dataset)
                guard space >= 0 else { throw SubsampleError.hdf5("opening the output dataspace") }
                defer { _ = h5.sclose(space) }
                let start = [hsize_t(i), 0, 0, 0]
                let count = [1, hsize_t(outRx), hsize_t(qy), hsize_t(qx)]
                let selected = start.withUnsafeBufferPointer { s in
                    count.withUnsafeBufferPointer { c in
                        h5.sselectHyperslab(space, SubsampleHDF5.selectSet, s.baseAddress, nil, c.baseAddress, nil)
                    }
                }
                guard selected >= 0 else { throw SubsampleError.hdf5("selecting row \(i)") }
                let mem = count.withUnsafeBufferPointer { h5.screateSimple(4, $0.baseAddress, nil) }
                guard mem >= 0 else { throw SubsampleError.hdf5("creating the row dataspace") }
                defer { _ = h5.sclose(mem) }
                let native = try h5.native(type.nativeSymbol)
                let wrote = rowBytes.withUnsafeBytes { h5.dwrite(dataset, native, mem, space, 0, $0.baseAddress) }
                guard wrote >= 0 else { throw SubsampleError.hdf5("writing row \(i)") }
            }
            footprintPeak = max(footprintPeak, memoryMB().footprint)
            let step = (i + 1) * 20 / outRy                     // 5 % steps
            if step > lastReported {
                lastReported = step
                print(String(format: "  %3d %%: row %d/%d, %d patterns, %.0f s; ", step * 5, i + 1, outRy,
                             (i + 1) * outRx, Date().timeIntervalSince(t0)) + memory())
            }
        }
        // Close before the rename so the file is complete on disk.
        HDF5Serial.run {
            _ = h5.dclose(dataset); dataset = -1
            _ = h5.gclose(cubeG); cubeG = -1
            _ = h5.gclose(rootG); rootG = -1
            _ = h5.fclose(fileID); fileID = -1
        }
        try? FileManager.default.removeItem(atPath: out)
        try FileManager.default.moveItem(atPath: partial, toPath: out)
        completed = true
        let size = ((try? FileManager.default.attributesOfItem(atPath: out))?[.size] as? Int) ?? 0
        print(String(format: "SUBSAMPLE: wrote %@ (%d×%d×%d×%d %@, %.1f MB on disk) in %.0f s; "
                     + "peak phys_footprint %.0f MB (sampled %.0f MB), ru_maxrss %.0f MB, source file %.0f MB",
                     out, outRy, outRx, qy, qx, d.dtypeDescription, Double(size) / 1_048_576,
                     Date().timeIntervalSince(t0), peakFootprintMB(), footprintPeak, maxRSSMB(),
                     Double(((try? FileManager.default.attributesOfItem(atPath: raw))?[.size] as? Int) ?? 0) / 1_048_576))
    }

    static func maxRSSMB() -> Double {
        var u = rusage()
        getrusage(RUSAGE_SELF, &u)
        return Double(u.ru_maxrss) / 1_048_576              // bytes on Darwin
    }

    /// Every kept position, both sides read pattern by pattern (source through
    /// `DM4Reader`, output through the app's `H5Reader`); bit patterns of the
    /// Float32 decodes must be identical. Shape, dtype and calibration too.
    static func verify(raw: String, out: String, stride: Int) async throws {
        let t0 = Date()
        let dm = try await DM4Reader(path: raw)
        let dRaw = try await dm.discoverPrimaryDataset()
        let rawView = LoadView(fullExtentOf: dRaw)
        let h5 = try H5Reader(path: out)
        let dOut = try await h5.discoverPrimaryDataset()
        let outView = LoadView(fullExtentOf: dOut)
        let (outRy, outRx) = (keptCount(dRaw.ry, stride: stride), keptCount(dRaw.rx, stride: stride))
        print("raw \(dRaw.ry)×\(dRaw.rx)×\(dRaw.qy)×\(dRaw.qx) \(dRaw.dtypeDescription); "
              + "output \(dOut.ry)×\(dOut.rx)×\(dOut.qy)×\(dOut.qx) \(dOut.dtypeDescription) at \(dOut.datasetPath); expected \(outRy)×\(outRx)")
        var problems = [String]()
        if [dOut.ry, dOut.rx, dOut.qy, dOut.qx] != [outRy, outRx, dRaw.qy, dRaw.qx] { problems.append("shape") }
        if dOut.dtypeDescription != dRaw.dtypeDescription { problems.append("dtype \(dOut.dtypeDescription) != \(dRaw.dtypeDescription)") }
        let rawCal = await dm.pixelCalibration()
        let outCal = await h5.pixelCalibration()
        let wantR = rawCal?.rSize.map { $0 * Double(stride) }
        if outCal?.qSize != rawCal?.qSize || outCal?.rSize != wantR
            || outCal?.qUnits != rawCal?.qUnits || outCal?.rUnits != rawCal?.rUnits {
            problems.append("calibration: out q \(String(describing: outCal?.qSize)) \(String(describing: outCal?.qUnits)) r \(String(describing: outCal?.rSize)) \(String(describing: outCal?.rUnits)); "
                            + "raw q \(String(describing: rawCal?.qSize)) \(String(describing: rawCal?.qUnits)) r \(String(describing: wantR)) \(String(describing: rawCal?.rUnits))")
        }
        print("calibration: raw q \(String(describing: rawCal?.qSize)) \(rawCal?.qUnits ?? "nil"), r \(String(describing: rawCal?.rSize)) \(rawCal?.rUnits ?? "nil") "
              + "→ output q \(String(describing: outCal?.qSize)) \(outCal?.qUnits ?? "nil"), r \(String(describing: outCal?.rSize)) \(outCal?.rUnits ?? "nil") (expected r × \(stride))")
        guard problems.isEmpty else { fail(problems.joined(separator: "; ")) }
        var compared = 0, identical = 0, badPixels = 0
        var lastReported = -1
        var firstBad: (Int, Int)?
        for i in 0..<outRy {
            for j in 0..<outRx {
                let a = try await dm.readPattern(rawView, ry: i * stride, rx: j * stride)
                let b = try await h5.readPattern(outView, ry: i, rx: j)
                var same = a.count == b.count
                if same {
                    for k in 0..<a.count where a[k].bitPattern != b[k].bitPattern { same = false; badPixels += 1 }
                } else { badPixels += max(a.count, b.count) }
                compared += 1
                if same { identical += 1 } else if firstBad == nil { firstBad = (i, j) }
            }
            let step = (i + 1) * 20 / outRy
            if step > lastReported {
                lastReported = step
                print(String(format: "  %3d %%: %d compared, %d identical; ", step * 5, compared, identical) + memory())
            }
        }
        print(String(format: "VERIFY: %d kept positions (stride %d), %d bit-identical, %d differing (%d differing pixels)%@; %.0f s; peak phys_footprint %.0f MB",
                     compared, stride, identical, compared - identical, badPixels,
                     firstBad.map { " first at (\($0.0), \($0.1))" } ?? "", Date().timeIntervalSince(t0), peakFootprintMB()))
        if identical != compared { fail("output differs from the source at kept positions") }
    }
}

//
//  HDF5SingleLibraryTests.swift
//  SpectroKit 0.4.0 + FormatoKit 0.0.3 (2026-10-15, lane R2), tier 2. The app no longer embeds libhdf5 / libsz / libaec of its own
//  (the root dylibs and the "Embed Libraries" phase are gone, owner 2026-10-15): the only copies are FormatoKit's, the resource
//  bundle `FormatoKit_FormatoHDF5.bundle` of FormatoHDF5. libhdf5 is built Threadsafety OFF, so a process that mapped two copies
//  would have two libraries (and two sets of global state) behind the one `HDF5Serial` lock. The app's own `H5Reader` /
//  `BraggVectorEMDWriter` and FormatoKit's Velox reader each `dlopen` by their own lookup list; this runs both and lists what
//  dyld mapped.
//
//  The test host IS the app (mac4DSTEM.app, hosted XCTest), so the running app's bundle is the one checked.
//

import XCTest
import MachO
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM
import FormatoEMD
import FormatoHDF5

final class HDF5SingleLibraryTests: XCTestCase {

    private static let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures")

    /// Every mapped image whose file name starts with libhdf5, libsz or libaec (libhdf5_hl would show too: none is shipped).
    private func hdf5Images() -> [String] {
        (0..<_dyld_image_count()).compactMap { index -> String? in
            guard let cName = _dyld_get_image_name(index) else { return nil }
            let path = String(cString: cName)
            let name = (path as NSString).lastPathComponent
            return ["libhdf5", "libsz", "libaec"].contains { name.hasPrefix($0) } ? path : nil
        }.sorted()
    }

    /// After the app's writer AND FormatoKit's Velox reader have both entered libhdf5, exactly one copy of each of the three
    /// libraries is mapped, and it is the one in the app's `FormatoKit_FormatoHDF5.bundle`.
    /// Mutation it catches: either reader resolving to another copy (a stray libhdf5 on the loader path, or `MAC4DSTEM_HDF5_PATH`
    /// pointing one reader at a copy outside the bundle after the other loaded the bundle's: two libhdf5 images, and this fails).
    func testOnlyTheFormatoBundlesCopyOfLibhdf5IsMappedAfterBothReadersRan() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("hdf5-single-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        // 1. The app's own entry: the sidecar writer opens libhdf5 through its lookup (BraggVectorEMDWriter / H5Reader).
        let sidecar = BraggVectorEMDWriter.sessionSidecarURL(forSourcePath: directory.appendingPathComponent("cube.h5").path)
        let calibration = PixelCalibration(rSize: 1.2, rUnits: "nm", qSize: 0.01, qUnits: "A^-1", qrFlip: true,
                                           ellipseA: 1.01, ellipseB: 0.99, ellipseTheta: 0.2)
        try BraggVectorEMDWriter.mergeCalibration(calibration, qWidth: 64, qHeight: 64, to: sidecar)
        XCTAssertNotNil(try BraggVectorEMDWriter.loadSession(from: sidecar).calibration, "the writer's file reads back through the same library")

        // 2. FormatoKit's entry: the Velox reader opens the committed fixture through its own lookup.
        let velox = Self.fixtures.appendingPathComponent("velox-tiny.emd").path
        XCTAssertTrue(VeloxEMDReader.isVeloxEMD(path: velox), "the fixture is a Velox spectrum image")
        _ = try VeloxEMDReader(path: velox).storedElementSelection()

        // 3. One lock: the type both entries take is FormatoKit's alone.
        XCTAssertEqual(String(reflecting: HDF5Serial.self), "FormatoHDF5.HDF5Serial")

        let images = hdf5Images()
        print("HDF5SingleLibraryTests: mapped HDF5 images: \(images)")
        let bundled = try XCTUnwrap(FormatoHDF5Library.bundledLibraryPath, "the app carries FormatoKit's resource bundle")
        let folder = URL(fileURLWithPath: bundled).deletingLastPathComponent().resolvingSymlinksInPath().path
        XCTAssertTrue(folder.hasSuffix("/mac4DSTEM.app/Contents/Resources/FormatoKit_FormatoHDF5.bundle/Contents/Resources/hdf5"),
                      "the bundle the lookup finds is the app's: \(folder)")
        let byName = Dictionary(grouping: images) { ($0 as NSString).lastPathComponent }
        XCTAssertEqual(byName.keys.sorted(), ["libaec.0.dylib", "libhdf5.dylib", "libsz.2.dylib"],
                       "the three libraries of the bundle are the only ones mapped: \(images)")
        for (name, paths) in byName {
            XCTAssertEqual(paths.count, 1, "\(name) is mapped \(paths.count) times: \(paths)")
            for path in paths {
                XCTAssertEqual(URL(fileURLWithPath: path).resolvingSymlinksInPath().path, "\(folder)/\(name)",
                               "\(name) is not the app's FormatoKit bundle copy")
            }
        }
    }
}

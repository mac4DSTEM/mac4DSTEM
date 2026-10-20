//
//  HDF5SingleLibraryTests.swift
//  SpectroKit 0.4.0 + FormatoKit 0.0.3 (2026-10-15, lane R2), tier 2; moved to FormatoKit 0.4.0's frameworks 2026-10-20. The app embeds no
//  libhdf5 / libsz / libaec of its own (owner 2026-10-15): the only copies are FormatoKit's three dynamic frameworks FormatoLibHDF5,
//  FormatoLibSZ and FormatoLibAEC, which Xcode embeds in `Contents/Frameworks` and signs with the app's identity. libhdf5 is built Threadsafety OFF, so a process that mapped two copies
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

    /// Every mapped image whose file name is one of FormatoKit's three library frameworks (a stray Homebrew libhdf5 would show too: see the check below).
    private func hdf5Images() -> [String] {
        (0..<_dyld_image_count()).compactMap { index -> String? in
            guard let cName = _dyld_get_image_name(index) else { return nil }
            let path = String(cString: cName)
            let name = (path as NSString).lastPathComponent
            return ["FormatoLibHDF5", "FormatoLibSZ", "FormatoLibAEC", "libhdf5", "libsz", "libaec"].contains { name.hasPrefix($0) } ? path : nil
        }.sorted()
    }

    /// After the app's writer AND FormatoKit's Velox reader have both entered libhdf5, exactly one copy of each of the three
    /// libraries is mapped, and it is the one in the app's `Contents/Frameworks` (FormatoLibHDF5, FormatoLibSZ, FormatoLibAEC).
    /// Mutation it catches: either reader resolving to another copy (a stray libhdf5 on the loader path, or `MAC4DSTEM_HDF5_PATH`
    /// pointing one reader at a copy outside the app's frameworks after the other loaded theirs: two libhdf5 images, and this fails).
    func testOnlyTheFormatoFrameworksCopyOfLibhdf5IsMappedAfterBothReadersRan() throws {
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
        let bundled = try XCTUnwrap(FormatoHDF5Library.bundledLibraryPath, "the app carries FormatoKit's FormatoLibHDF5.framework")
        // .../Frameworks/FormatoLibHDF5.framework/Versions/A/FormatoLibHDF5, resolved, up four levels is the folder holding the three frameworks.
        let frameworks = URL(fileURLWithPath: bundled).resolvingSymlinksInPath().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().path
        // The app carries its own embedded, signed copy (checked here and, in the built Release app, by package-test). Under
        // `xcodebuild test` the test host is the Debug app in the build products folder and dyld maps the identical frameworks from the
        // products folder itself (Xcode puts them there too; measured 2026-10-20), so the folder is the app's Contents/Frameworks or
        // the products folder that holds the app.
        let appFrameworks = try XCTUnwrap(Bundle.main.privateFrameworksURL).resolvingSymlinksInPath().path
        XCTAssertTrue(FileManager.default.fileExists(atPath: "\(appFrameworks)/FormatoLibHDF5.framework/FormatoLibHDF5"),
                      "the app embeds FormatoLibHDF5.framework in Contents/Frameworks: \(appFrameworks)")
        let productsFolder = Bundle.main.bundleURL.deletingLastPathComponent().resolvingSymlinksInPath().path
        XCTAssertTrue(frameworks == appFrameworks || frameworks == productsFolder,
                      "the framework the lookup finds is the app's embedded one or the build products' copy beside the app: \(bundled)")
        let byName = Dictionary(grouping: images) { ($0 as NSString).lastPathComponent }
        XCTAssertEqual(byName.keys.sorted(), ["FormatoLibAEC", "FormatoLibHDF5", "FormatoLibSZ"],
                       "the three libraries of the frameworks are the only ones mapped: \(images)")
        for (name, paths) in byName {
            XCTAssertEqual(paths.count, 1, "\(name) is mapped \(paths.count) times: \(paths)")
            for path in paths {
                XCTAssertEqual(URL(fileURLWithPath: path).resolvingSymlinksInPath().path, "\(frameworks)/\(name).framework/Versions/A/\(name)",
                               "\(name) is not the app's embedded FormatoKit framework")
            }
        }
    }
}

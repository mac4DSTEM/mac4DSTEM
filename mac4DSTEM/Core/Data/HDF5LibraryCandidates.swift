import Foundation
import FormatoHDF5

/// WHERE libhdf5 is looked for: exactly FormatoKit's `SharedHDF5.loadStandard` order (the `FORMATO_HDF5_PATH` override, the host's
/// `Frameworks/libhdf5.dylib`, the framework FormatoKit ships, then the loader's search path), so the kit's readers, this app's
/// writer and `HDF5LegacyProbe` all map ONE copy in every configuration. `MAC4DSTEM_HDF5_PATH` is not read: a process that
/// resolved the two lookups differently would hold two non-thread-safe libhdf5 images behind the one `HDF5Serial` lock.
nonisolated enum HDF5LibraryCandidates {
    static var paths: [String] {
        [ProcessInfo.processInfo.environment["FORMATO_HDF5_PATH"],
         Bundle.main.privateFrameworksURL?.appendingPathComponent("libhdf5.dylib").path,
         Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("../Frameworks/libhdf5.dylib").standardized.path,
         FormatoHDF5Library.bundledLibraryPath, "libhdf5.dylib"].compactMap { $0 }
    }
}

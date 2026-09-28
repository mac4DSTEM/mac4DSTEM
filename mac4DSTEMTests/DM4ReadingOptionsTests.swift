import XCTest
import DSTEMCore

/// open-items "DM4Reader silently reads whole files into RAM off non-local
/// volumes": `.mappedIfSafe` read the owner's 28 GB raw DM4 into anonymous
/// memory off an external SSD and panicked an 8 GB Mac (2026-09-24). The
/// reader now maps on every `MNT_LOCAL` volume. The footprint proof on an
/// exFAT disk image is `tools/dm4-parity-probe` (record:
/// `docs/archive/v4/almgsi-gateD-2026-09-24.md` part 8); these pin the
/// choice, and `run-tests.sh inventory` pins that `init` uses it.
final class DM4ReadingOptionsTests: XCTestCase {

    /// The temporary directory is on the internal APFS volume, which is
    /// `MNT_LOCAL`: the reader must map the file, not read it.
    func testALocalVolumeIsAlwaysMapped() throws {
        let path = NSTemporaryDirectory()
        XCTAssertEqual(DM4Reader.readingOptions(forPath: path), .alwaysMapped)
    }

    /// When `statfs` cannot answer, the reader keeps the old, conservative
    /// option rather than guessing the volume is safe to map.
    func testAPathStatfsCannotResolveKeepsMappedIfSafe() {
        let path = NSTemporaryDirectory() + "mac4dstem-no-such-directory/cube.dm4"
        XCTAssertEqual(DM4Reader.readingOptions(forPath: path), .mappedIfSafe)
    }
}

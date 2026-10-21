//
//  H5ReaderChunkShapeTests.swift
//  `describe` reports a dataset's chunk shape: nil means "not chunked" and nothing else. A failed read of the layout is an error,
//  not a nil that would make the loader treat a chunked dataset as contiguous (cropping then skips nothing, unannounced).
//

import XCTest
import DSTEMCore
@testable import mac4DSTEM

final class H5ReaderChunkShapeTests: XCTestCase {
    private struct LayoutReadFailed: Error {}

    /// Mutation: `(try? lookup()) ?? nil` -> the failure returns nil, no throw -> red.
    func testAFailedLayoutReadThrowsAndOnlyNotChunkedIsNil() throws {
        XCTAssertEqual(try H5Reader.chunkShape("/d") { [1, 12, 64, 64] }, [1, 12, 64, 64])
        XCTAssertNil(try H5Reader.chunkShape("/d") { nil }, "contiguous or compact storage")
        XCTAssertThrowsError(try H5Reader.chunkShape("/d") { throw LayoutReadFailed() }) {
            guard case H5Error.datasetOpenFailed("/d") = $0 else { return XCTFail("\($0)") }
        }
    }
}

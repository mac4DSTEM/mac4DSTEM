import XCTest
import DSTEMCore
@testable import mac4DSTEM

/// docs/ui-workflow-backlog.md #9: recoverable compute failures must stay on
/// the non-blocking status bar + log surface; only session-level failures
/// (file open/read, dataset activation) may raise the window-modal alert,
/// because the modal swallows every later interaction in the window.
final class ErrorRoutingTests: XCTestCase {
    func testComputeFailureRoutesToStatusBarOnly() {
        let state = AppState()
        state.presentComputeFailure(SimpleError("No well-conditioned lattice explains the peaks."))
        XCTAssertNil(state.errorMessage,
                     "A recoverable compute failure must not raise the window-modal alert")
        XCTAssertTrue(state.statusText.contains("No well-conditioned lattice explains the peaks."),
                      "The compute failure must still reach the status bar")
        XCTAssertTrue(state.logMessages.last?.contains("No well-conditioned lattice") == true,
                      "The compute failure must still reach the log pane")
    }

    func testSessionLevelFailureStillPresentsModally() {
        let state = AppState()
        state.present(SimpleError("The file could not be read."))
        XCTAssertEqual(state.errorMessage, "The file could not be read.",
                       "A session-level failure keeps the window-modal alert")
        XCTAssertTrue(state.statusText.contains("The file could not be read."))
    }

    /// A data-source failure surfacing through a compute catch block
    /// (corrupted or vanished file mid-scan) invalidates the session and must
    /// escalate to the modal path even when routed via presentComputeFailure.
    func testDataSourceFailureEscalatesToModal() {
        let state = AppState()
        state.presentComputeFailure(H5Error.readFailed("/data"))
        XCTAssertNotNil(state.errorMessage,
                        "A file-read failure mid-compute must still raise the modal")

        let posix = NSError(domain: NSPOSIXErrorDomain, code: 5)
        let state2 = AppState()
        state2.presentComputeFailure(posix)
        XCTAssertNotNil(state2.errorMessage,
                        "A POSIX I/O failure mid-compute must still raise the modal")
    }

    func testStrainPrerequisiteFailureIsNonModal() async {
        let state = AppState()
        state.descriptor = DatasetDescriptor(
            filePath: "/tmp/example.h5", datasetPath: "/data",
            shape: [8, 8, 32, 32], dtypeDescription: "float32",
            chunkShape: nil
        )
        // No detected Bragg peaks: the strain step must fail without blocking
        // the window (the measured backlog #9 scenario).
        await state.runStrainMapping()
        XCTAssertNil(state.errorMessage)
        XCTAssertTrue(state.statusText.contains("Run disk detection first"))
    }
}

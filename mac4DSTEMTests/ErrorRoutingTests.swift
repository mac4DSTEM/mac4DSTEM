import XCTest
import DSTEMCore
import DSTEMSession
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

    // MARK: - A refusal names the file, never the folders above it

    /// A file that will not open is a session-level failure, so by the rule
    /// above its message goes to the window-modal alert — the most
    /// screenshotted surface in the app, in a public repo. The folders above
    /// the file are the user's home directory, volume names and project
    /// names, and none of them helps anyone fix an unreadable file.
    ///
    /// Deliberately NOT covered here: `H5Error.libraryUnavailable`, whose
    /// detail is `dlopen` failures over app-install paths. That string carries
    /// no user data and is the only diagnostic for a bundled-HDF5 load
    /// failure, which is a live failure class in this repo.
    func testReaderRefusalsNameTheFileAndNotTheFoldersAboveIt() {
        let directory = "/Users/someone/Unpublished/Grant-2027"
        let path = "\(directory)/scan_042.h5"

        for message in [H5Error.cannotOpenFile(path).errorDescription,
                        VendorRawError.cannotOpen(path).errorDescription] {
            let message = try? XCTUnwrap(message)
            XCTAssertEqual(message?.contains("scan_042.h5"), true,
                           "the user must be told which file: \(message ?? "nil")")
            XCTAssertEqual(message?.contains(directory), false,
                           "the path above the file must not appear: \(message ?? "nil")")
            XCTAssertEqual(message?.contains("Users"), false,
                           "no home directory: \(message ?? "nil")")
        }
    }

    /// `DM4Reader` composes its refusal at the throw site rather than in
    /// `errorDescription`, so this exercises the real one. The underlying
    /// error still travels with it — that was the v2 S7 audit's point, which
    /// distinguishes EPERM from ENOENT from a short read — only the path
    /// above the file is gone.
    func testTheDM4RefusalKeepsItsUnderlyingErrorWithoutTheEnclosingPath() async {
        let directory = NSTemporaryDirectory() + "mac4dstem-refusal-fixture"
        let path = directory + "/no_such_cube.dm4"
        do {
            _ = try await DM4Reader(path: path)
            XCTFail("a file that does not exist must not open")
        } catch {
            let message = error.localizedDescription
            XCTAssertTrue(message.contains("no_such_cube.dm4"),
                          "names the file: \(message)")
            XCTAssertFalse(message.contains(directory),
                           "but not the folder it is in: \(message)")
        }
    }

    /// The helper itself, at the edges a path can actually have.
    func testDisplayFileNameFallsBackRatherThanReturningNothing() {
        XCTAssertEqual(displayFileName("/a/b/c.h5"), "c.h5")
        XCTAssertEqual(displayFileName("c.h5"), "c.h5")
        XCTAssertEqual(displayFileName("/a/b/"), "b", "a trailing slash is not a file name")
        XCTAssertEqual(displayFileName(""), "", "nothing to name, and nothing invented")
    }
}

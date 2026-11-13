import XCTest
import DSTEMCore
import DSTEMSession
@testable import mac4DSTEM

/// mac4DSTEM#279: a task inside a room could be chosen only by a pointer click on its sidebar row. Workspace › Next Task and
/// Previous Task (and the row's accessibility action) choose it through `selectTask`, the path the row's selection takes.
@MainActor
final class TaskSwitchingAccessibilityTests: XCTestCase {

    /// Crystal Maps lists Strain, Orientation, Phase mapping: the next and previous task wrap round the list, and choosing
    /// one makes it the task on screen. A room with one task or none offers neither. Red before the fix: neither function
    /// existed, so no keyboard or accessibility way changed the task.
    func testNextAndPreviousTaskWalkTheRoomsTaskList() async throws {
        let state = AppState()
        await state.openDemoFixture()
        XCTAssertNotNil(state.descriptor, state.statusText)

        state.selectWorkspace(.map)
        XCTAssertEqual(state.navigation.analysisMode, .strain, "precondition: the room's first task")
        XCTAssertEqual(state.adjacentTask(1), .acom)
        XCTAssertEqual(state.adjacentTask(-1), .phaseMapping, "previous wraps to the last task")

        state.selectTask(try XCTUnwrap(state.adjacentTask(1)))
        XCTAssertEqual(state.navigation.analysisMode, .acom)
        state.selectTask(try XCTUnwrap(state.adjacentTask(1)))
        XCTAssertEqual(state.navigation.analysisMode, .phaseMapping)
        XCTAssertEqual(state.adjacentTask(1), .strain, "next wraps to the first task")
        XCTAssertEqual(state.workspaceRoute.wrappedValue, .task(.phaseMapping), "the sidebar selection follows")

        // A task of another room is entered with its room, as a click on its row in that room does.
        state.selectTask(.dpc)
        XCTAssertEqual(state.navigation.workspaceArea, .reconstruct)
        XCTAssertEqual(state.navigation.analysisMode, .dpc)

        state.selectWorkspace(.braggDisks)
        XCTAssertNil(state.adjacentTask(1), "one task: nothing to step to")
        state.selectWorkspace(.prepare)
        XCTAssertNil(state.adjacentTask(-1), "no tasks: nothing to step to")
    }
}

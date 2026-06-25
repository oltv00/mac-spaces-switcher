import XCTest
@testable import MacSpacesSwitcher

final class MoveTargetTests: XCTestCase {
    private func layout(current: UInt64,
                        spaces: [(UInt64, Int)]) -> DisplayLayout {
        DisplayLayout(displayIdentifier: "Main",
                      spaces: spaces.map { SpaceInfo(id: $0.0, type: $0.1) },
                      currentSpaceID: current)
    }

    func testMoveRightToDesktop() {
        let l = layout(current: 5, spaces: [(5, 0), (7, 0), (9, 4)])
        XCTAssertEqual(SpaceLogic.adjacentDesktop(for: .right, in: l), 7)
    }

    func testMoveLeftToDesktop() {
        let l = layout(current: 7, spaces: [(5, 0), (7, 0)])
        XCTAssertEqual(SpaceLogic.adjacentDesktop(for: .left, in: l), 5)
    }

    func testFullscreenNeighborIsNoOp() {
        // neighbor (9) is a fullscreen space — not a valid window-move target
        let l = layout(current: 7, spaces: [(5, 0), (7, 0), (9, 4)])
        XCTAssertNil(SpaceLogic.adjacentDesktop(for: .right, in: l))
    }

    func testClampAtEndsIsNoOp() {
        let l = layout(current: 5, spaces: [(5, 0), (7, 0)])
        XCTAssertNil(SpaceLogic.adjacentDesktop(for: .left, in: l))
        let r = layout(current: 7, spaces: [(5, 0), (7, 0)])
        XCTAssertNil(SpaceLogic.adjacentDesktop(for: .right, in: r))
    }

    func testCurrentNotInListIsNoOp() {
        let l = layout(current: 99, spaces: [(5, 0), (7, 0)])
        XCTAssertNil(SpaceLogic.adjacentDesktop(for: .right, in: l))
    }
}

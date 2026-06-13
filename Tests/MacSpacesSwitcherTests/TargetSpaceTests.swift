import XCTest
@testable import MacSpacesSwitcher

final class TargetSpaceTests: XCTestCase {
    private func layout(current: UInt64,
                        spaces: [(UInt64, Int)]) -> DisplayLayout {
        DisplayLayout(displayIdentifier: "Main",
                      spaces: spaces.map { SpaceInfo(id: $0.0, type: $0.1) },
                      currentSpaceID: current)
    }

    func testMoveRight() {
        let l = layout(current: 5, spaces: [(5, 0), (7, 0), (9, 4)])
        XCTAssertEqual(SpaceLogic.targetSpace(for: .right, in: l), 7)
    }

    func testMoveLeft() {
        let l = layout(current: 7, spaces: [(5, 0), (7, 0), (9, 4)])
        XCTAssertEqual(SpaceLogic.targetSpace(for: .left, in: l), 5)
    }

    func testClampAtStartIsNoOp() {
        let l = layout(current: 5, spaces: [(5, 0), (7, 0)])
        XCTAssertNil(SpaceLogic.targetSpace(for: .left, in: l))
    }

    func testClampAtEndIsNoOp() {
        let l = layout(current: 7, spaces: [(5, 0), (7, 0)])
        XCTAssertNil(SpaceLogic.targetSpace(for: .right, in: l))
    }

    func testRelativeIncludesFullscreenSpaces() {
        let l = layout(current: 7, spaces: [(5, 0), (7, 0), (9, 4)])
        XCTAssertEqual(SpaceLogic.targetSpace(for: .right, in: l), 9)
    }

    func testJumpToDesktopByOrdinal() {
        // desktops (type 0) are 5, 7, 11 — jump(3) -> 11
        let l = layout(current: 5, spaces: [(5, 0), (7, 0), (9, 4), (11, 0)])
        XCTAssertEqual(SpaceLogic.targetSpace(for: .jump(3), in: l), 11)
    }

    func testJumpSkipsFullscreenSpaces() {
        // desktops are 5, 7 — jump(2) -> 7 (the fullscreen 9 is ignored)
        let l = layout(current: 5, spaces: [(5, 0), (9, 4), (7, 0)])
        XCTAssertEqual(SpaceLogic.targetSpace(for: .jump(2), in: l), 7)
    }

    func testJumpOutOfRangeIsNoOp() {
        let l = layout(current: 5, spaces: [(5, 0), (7, 0)])
        XCTAssertNil(SpaceLogic.targetSpace(for: .jump(5), in: l))
    }

    func testCurrentSpaceNotInListIsNoOp() {
        let l = layout(current: 99, spaces: [(5, 0), (7, 0)])
        XCTAssertNil(SpaceLogic.targetSpace(for: .right, in: l))
    }
}

import XCTest
@testable import MacSpacesSwitcher

final class FocusedDisplayTests: XCTestCase {
    private func display(_ id: String) -> DisplayLayout {
        DisplayLayout(displayIdentifier: id, spaces: [], currentSpaceID: 1)
    }

    func testExactUUIDMatch() {
        let layouts = [display("UUID-A"), display("UUID-B")]
        let focused = SpaceLogic.focusedDisplay(in: layouts,
                                                focusedUUID: "UUID-B",
                                                isPrimary: false)
        XCTAssertEqual(focused?.displayIdentifier, "UUID-B")
    }

    func testFallsBackToMainWhenPrimaryAndNoUUIDMatch() {
        // SkyLight labels the primary display "Main" instead of a UUID.
        let layouts = [display("Main")]
        let focused = SpaceLogic.focusedDisplay(in: layouts,
                                                focusedUUID: "UUID-X",
                                                isPrimary: true)
        XCTAssertEqual(focused?.displayIdentifier, "Main")
    }

    func testNoMatchReturnsNil() {
        let layouts = [display("UUID-A")]
        let focused = SpaceLogic.focusedDisplay(in: layouts,
                                                focusedUUID: "UUID-X",
                                                isPrimary: false)
        XCTAssertNil(focused)
    }

    func testUUIDMatchWinsOverMainEvenWhenPrimary() {
        let layouts = [display("Main"), display("UUID-A")]
        let focused = SpaceLogic.focusedDisplay(in: layouts,
                                                focusedUUID: "UUID-A",
                                                isPrimary: true)
        XCTAssertEqual(focused?.displayIdentifier, "UUID-A")
    }
}

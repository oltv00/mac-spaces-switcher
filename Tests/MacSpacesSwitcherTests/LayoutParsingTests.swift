import XCTest
@testable import MacSpacesSwitcher

final class LayoutParsingTests: XCTestCase {
    // Modeled on the CGSCopyManagedDisplaySpaces dictionary shape.
    func testParsesSingleDisplay() {
        let raw: [[String: Any]] = [[
            "Display Identifier": "Main",
            "Current Space": ["ManagedSpaceID": 7],
            "Spaces": [
                ["ManagedSpaceID": 5, "type": 0],
                ["ManagedSpaceID": 7, "type": 0],
                ["ManagedSpaceID": 9, "type": 4], // fullscreen app space
            ],
        ]]

        let layouts = SpaceLogic.parseDisplaySpaces(raw)

        XCTAssertEqual(layouts.count, 1)
        XCTAssertEqual(layouts[0].displayIdentifier, "Main")
        XCTAssertEqual(layouts[0].currentSpaceID, 7)
        XCTAssertEqual(layouts[0].spaces.map(\.id), [5, 7, 9])
        XCTAssertEqual(layouts[0].spaces.map(\.type), [0, 0, 4])
    }

    func testSkipsDisplaysMissingRequiredKeys() {
        let raw: [[String: Any]] = [
            ["Display Identifier": "Main"], // no Spaces / Current Space
            [
                "Display Identifier": "UUID-B",
                "Current Space": ["ManagedSpaceID": 3],
                "Spaces": [["ManagedSpaceID": 3, "type": 0]],
            ],
        ]

        let layouts = SpaceLogic.parseDisplaySpaces(raw)

        XCTAssertEqual(layouts.count, 1)
        XCTAssertEqual(layouts[0].displayIdentifier, "UUID-B")
    }
}

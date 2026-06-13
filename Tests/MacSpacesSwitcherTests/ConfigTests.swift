import XCTest
@testable import MacSpacesSwitcher

final class ConfigTests: XCTestCase {
    func testParseShortcuts() {
        let parsed = Config.parseShortcuts([
            "left": "ctrl+left",
            "right": "ctrl+right",
            "1": "ctrl+1",
        ])
        XCTAssertEqual(parsed[.left], Hotkey(keyCode: 0x7B, modifiers: 0x1000))
        XCTAssertEqual(parsed[.right], Hotkey(keyCode: 0x7C, modifiers: 0x1000))
        XCTAssertEqual(parsed[.jump(1)], Hotkey(keyCode: 0x12, modifiers: 0x1000))
    }

    func testInvalidEntriesAreSkipped() {
        let parsed = Config.parseShortcuts([
            "left": "ctrl+left",   // valid
            "bogus": "ctrl+1",     // unknown action key
            "right": "nope+right", // unknown modifier
        ])
        XCTAssertEqual(parsed.count, 1)
        XCTAssertNotNil(parsed[.left])
    }

    func testDefaultsParseToElevenShortcuts() {
        let parsed = Config.parseShortcuts(Config.defaultShortcuts)
        XCTAssertEqual(parsed.count, 11) // left, right, 1...9
        XCTAssertNotNil(parsed[.left])
        XCTAssertNotNil(parsed[.right])
        XCTAssertNotNil(parsed[.jump(9)])
    }
}

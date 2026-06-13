import XCTest
@testable import MacSpacesSwitcher

final class HotkeyParsingTests: XCTestCase {
    func testCtrlArrow() {
        // controlKey == 0x1000, kVK_LeftArrow == 0x7B
        XCTAssertEqual(Config.parseHotkey("ctrl+left"),
                       Hotkey(keyCode: 0x7B, modifiers: 0x1000))
    }

    func testCtrlDigit() {
        // kVK_ANSI_1 == 0x12
        XCTAssertEqual(Config.parseHotkey("ctrl+1"),
                       Hotkey(keyCode: 0x12, modifiers: 0x1000))
    }

    func testMultipleModifiers() {
        // controlKey | shiftKey == 0x1000 | 0x0200, kVK_RightArrow == 0x7C
        XCTAssertEqual(Config.parseHotkey("ctrl+shift+right"),
                       Hotkey(keyCode: 0x7C, modifiers: 0x1200))
    }

    func testUnknownKeyReturnsNil() {
        XCTAssertNil(Config.parseHotkey("ctrl+foo"))
    }

    func testUnknownModifierReturnsNil() {
        XCTAssertNil(Config.parseHotkey("hyper+left"))
    }
}

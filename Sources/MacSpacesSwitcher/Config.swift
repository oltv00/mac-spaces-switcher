import Foundation

/// What a hotkey does.
enum Action: Hashable {
    case left
    case right
    case moveLeft
    case moveRight
    case jump(Int)
}

/// A Carbon-style hotkey: a virtual key code plus a Carbon modifier mask.
struct Hotkey: Equatable {
    let keyCode: UInt32
    let modifiers: UInt32
}

enum Config {
    /// Carbon virtual key codes (kVK_*) for the keys we support.
    private static let keyCodes: [String: UInt32] = [
        "left": 0x7B, "right": 0x7C, "up": 0x7E, "down": 0x7D,
        "1": 0x12, "2": 0x13, "3": 0x14, "4": 0x15, "5": 0x17,
        "6": 0x16, "7": 0x1A, "8": 0x1C, "9": 0x19, "0": 0x1D,
    ]

    /// Carbon modifier masks (controlKey, optionKey, cmdKey, shiftKey).
    private static let modifierMasks: [String: UInt32] = [
        "ctrl": 0x1000, "control": 0x1000,
        "alt": 0x0800, "option": 0x0800,
        "cmd": 0x0100, "command": 0x0100,
        "shift": 0x0200,
    ]

    /// Parses a `"mod+...+key"` string into a `Hotkey`. Returns nil if any
    /// component is unknown.
    static func parseHotkey(_ string: String) -> Hotkey? {
        let parts = string.lowercased().split(separator: "+").map(String.init)
        guard let keyName = parts.last, let keyCode = keyCodes[keyName] else {
            return nil
        }
        var modifiers: UInt32 = 0
        for modifier in parts.dropLast() {
            guard let mask = modifierMasks[modifier] else { return nil }
            modifiers |= mask
        }
        return Hotkey(keyCode: keyCode, modifiers: modifiers)
    }

    /// Maps a config action key (`"left"`, `"right"`, `"1"`...`"9"`) to an Action.
    static func action(forKey key: String) -> Action? {
        switch key {
        case "left": return .left
        case "right": return .right
        case "move-left": return .moveLeft
        case "move-right": return .moveRight
        default:
            if let n = Int(key), (1...9).contains(n) { return .jump(n) }
            return nil
        }
    }

    /// Turns a raw `{actionKey: hotkeyString}` map into `[Action: Hotkey]`,
    /// silently skipping any entry whose key or hotkey string is invalid.
    static func parseShortcuts(_ raw: [String: String]) -> [Action: Hotkey] {
        var result: [Action: Hotkey] = [:]
        for (key, value) in raw {
            guard let action = action(forKey: key),
                  let hotkey = parseHotkey(value) else { continue }
            result[action] = hotkey
        }
        return result
    }

    /// The native-key defaults: ctrl+arrows and ctrl+1...9.
    static let defaultShortcuts: [String: String] = [
        "left": "ctrl+left", "right": "ctrl+right",
        "move-left": "ctrl+shift+left", "move-right": "ctrl+shift+right",
        "1": "ctrl+1", "2": "ctrl+2", "3": "ctrl+3",
        "4": "ctrl+4", "5": "ctrl+5", "6": "ctrl+6",
        "7": "ctrl+7", "8": "ctrl+8", "9": "ctrl+9",
    ]

    private struct ConfigFile: Decodable {
        let shortcuts: [String: String]
    }

    /// Loads `~/.config/mac-spaces-switcher/config.json`, falling back to the
    /// built-in defaults if the file is missing or unparseable.
    static func load() -> [Action: Hotkey] {
        let path = ("~/.config/mac-spaces-switcher/config.json" as NSString)
            .expandingTildeInPath
        let url = URL(fileURLWithPath: path)
        guard let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(ConfigFile.self, from: data)
        else {
            return parseShortcuts(defaultShortcuts)
        }
        return parseShortcuts(file.shortcuts)
    }
}

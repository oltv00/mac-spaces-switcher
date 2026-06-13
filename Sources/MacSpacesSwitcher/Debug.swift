import Foundation

/// Whether MSS_DEBUG is set in the environment. When on, the app traces hotkey
/// registration, key presses, and space switches to stderr for debugging.
let debugEnabled = ProcessInfo.processInfo.environment["MSS_DEBUG"] != nil

/// Writes a line to stderr only when MSS_DEBUG is set.
func debugLog(_ message: @autoclosure () -> String) {
    guard debugEnabled else { return }
    FileHandle.standardError.write(
        Data("mac-spaces-switcher[debug]: \(message())\n".utf8))
}

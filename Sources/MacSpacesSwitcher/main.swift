import AppKit
import ApplicationServices

let arguments = CommandLine.arguments
let controller = SpaceController()

if arguments.contains("--dump") {
    controller.dumpLayout()
    exit(0)
}

if arguments.contains("--probe") {
    controller.probeSwitch()
    exit(0)
}

// Same probe, but first put the process in the agent's exact state (an accessory
// NSApplication) to test whether that context is what breaks the switch.
if arguments.contains("--probe-app") {
    let probeApp = NSApplication.shared
    probeApp.setActivationPolicy(.accessory)
    probeApp.finishLaunching()
    RunLoop.main.run(until: Date().addingTimeInterval(0.3))
    controller.probeSwitch()
    exit(0)
}

let shortcuts = Config.load()
if shortcuts.isEmpty {
    FileHandle.standardError.write(
        Data("mac-spaces-switcher: no shortcuts configured\n".utf8))
}

// Becoming an accessory NSApplication gives the process the WindowServer
// connection and Carbon-dispatching event loop that RegisterEventHotKey events
// require — a bare RunLoop registers hotkeys but never receives their presses.
// .accessory keeps it out of the Dock and stops it stealing focus.
let app = NSApplication.shared
app.setActivationPolicy(.accessory)

// Posting the synthetic Dock-swipe gestures that switch spaces requires
// Accessibility permission. Prompt for it on first launch; warn (but keep
// running, so hotkeys still register) if it hasn't been granted yet.
let axOptions = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
if !AXIsProcessTrustedWithOptions(axOptions) {
    FileHandle.standardError.write(Data(
        ("mac-spaces-switcher: needs Accessibility permission — grant it in "
         + "System Settings > Privacy & Security > Accessibility, then restart "
         + "the agent. Space switching won't work until then.\n").utf8))
}

let hotkeyManager = HotkeyManager { action in
    controller.switchSpace(action)
}
hotkeyManager.register(shortcuts)

app.run()

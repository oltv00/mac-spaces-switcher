import AppKit
import ApplicationServices
import CSkyLight

/// One space on a display. `type == 0` is a normal desktop; other values
/// (e.g. 4) are fullscreen-app or system spaces.
struct SpaceInfo: Equatable {
    let id: UInt64
    let type: Int
}

/// The ordered space list and current space for one display.
struct DisplayLayout: Equatable {
    let displayIdentifier: String
    let spaces: [SpaceInfo]
    let currentSpaceID: UInt64
}

/// Pure logic over space layouts — no private-API calls live here.
enum SpaceLogic {
    /// Parses the array-of-dictionaries returned by CGSCopyManagedDisplaySpaces
    /// into typed `DisplayLayout`s, skipping malformed entries.
    static func parseDisplaySpaces(_ raw: [[String: Any]]) -> [DisplayLayout] {
        raw.compactMap { dict in
            guard let identifier = dict["Display Identifier"] as? String,
                  let spacesRaw = dict["Spaces"] as? [[String: Any]],
                  let currentRaw = dict["Current Space"] as? [String: Any],
                  let currentID = (currentRaw["ManagedSpaceID"] as? NSNumber)?.uint64Value
            else { return nil }

            let spaces = spacesRaw.compactMap { space -> SpaceInfo? in
                guard let id = (space["ManagedSpaceID"] as? NSNumber)?.uint64Value
                else { return nil }
                let type = (space["type"] as? NSNumber)?.intValue ?? 0
                return SpaceInfo(id: id, type: type)
            }

            return DisplayLayout(displayIdentifier: identifier,
                                 spaces: spaces,
                                 currentSpaceID: currentID)
        }
    }

    /// Computes the space id to switch to, or nil for a safe no-op (clamped at
    /// an end, jump out of range, or current space not found).
    static func targetSpace(for action: Action, in display: DisplayLayout) -> UInt64? {
        switch action {
        case .left, .right:
            guard let index = display.spaces.firstIndex(where: {
                $0.id == display.currentSpaceID
            }) else { return nil }
            let target: Int
            if case .left = action {
                target = index - 1
            } else {
                target = index + 1
            }
            guard target >= 0, target < display.spaces.count else { return nil }
            return display.spaces[target].id

        case .jump(let n):
            let desktops = display.spaces.filter { $0.type == 0 }
            guard n >= 1, n <= desktops.count else { return nil }
            return desktops[n - 1].id

        case .moveLeft, .moveRight:
            return nil // window-move actions resolve via adjacentDesktop, not here
        }
    }

    /// Adjacent Space for a window move — like targetSpace(.left/.right) but only
    /// when the immediate neighbor is a normal desktop (type 0). Moving a window
    /// onto a fullscreen-app Space isn't meaningful, so that (and the list ends)
    /// clamps to nil (a safe no-op). `action` must be `.left` or `.right`.
    static func adjacentDesktop(for action: Action, in display: DisplayLayout) -> UInt64? {
        guard let index = display.spaces.firstIndex(where: {
            $0.id == display.currentSpaceID
        }) else { return nil }
        let target = (action == .left) ? index - 1 : index + 1
        guard target >= 0, target < display.spaces.count else { return nil }
        let space = display.spaces[target]
        return space.type == 0 ? space.id : nil
    }

    /// Finds the layout for the focused display. Prefers an exact match on the
    /// display UUID; if the focused display is the primary one, falls back to
    /// the SkyLight "Main" special-case entry.
    static func focusedDisplay(in layouts: [DisplayLayout],
                               focusedUUID: String,
                               isPrimary: Bool) -> DisplayLayout? {
        if let exact = layouts.first(where: { $0.displayIdentifier == focusedUUID }) {
            return exact
        }
        if isPrimary,
           let main = layouts.first(where: { $0.displayIdentifier == "Main" }) {
            return main
        }
        return nil
    }
}

/// Reads the live display/space layout via private SkyLight APIs and switches
/// spaces. The only file that touches private APIs.
final class SpaceController {
    /// Switches the focused display to the space implied by `action`.
    /// No-ops safely when the layout can't be read or the move is clamped.
    func switchSpace(_ action: Action) {
        let connection = CGSMainConnectionID()
        guard let cfDisplays = CGSCopyManagedDisplaySpaces(connection),
              let rawDisplays = (cfDisplays as NSArray) as? [[String: Any]] else {
            logError("could not read display spaces")
            return
        }
        let layouts = SpaceLogic.parseDisplaySpaces(rawDisplays)
        // The display whose space should switch is the one with the frontmost
        // app — i.e. the active menu-bar display, which tracks ⌘-Tab (unlike the
        // cursor/last-clicked display the OS otherwise uses for swipes). Fall
        // back to NSScreen.main only if that can't be read.
        let uuid = activeMenuBarDisplay(connection) ?? currentDisplayUUID()
        let primary = isMainDisplayPrimary()
        guard let focused = SpaceLogic.focusedDisplay(
            in: layouts,
            focusedUUID: uuid,
            isPrimary: primary
        ) else {
            logError("could not determine focused display "
                     + "(uuid=\(uuid) primary=\(primary))")
            return
        }
        guard let target = SpaceLogic.targetSpace(for: action, in: focused) else {
            debugLog("\(action): no-op on \(focused.displayIdentifier) "
                     + "(current \(focused.currentSpaceID) — clamped/out of range)")
            return // clamped / out of range — intentional no-op
        }
        // Move via synthetic Dock-swipe gestures (one per adjacent step toward
        // the target). The number of steps is the distance between the current
        // and target space in the display's ordered space list; the sign is the
        // direction. This drives the real compositor path, so the outgoing space
        // is replaced rather than ghosted.
        guard let currentIndex = focused.spaces.firstIndex(where: {
                  $0.id == focused.currentSpaceID
              }),
              let targetIndex = focused.spaces.firstIndex(where: { $0.id == target })
        else {
            logError("could not locate current/target space in layout")
            return
        }
        let steps = targetIndex - currentIndex
        guard steps != 0 else { return } // already there — no-op
        let direction: Int32 = steps > 0 ? 1 : -1
        // Land the swipe on the focused display. If we can't resolve its bounds,
        // pass NaN so the gesture falls back to the cursor's display.
        let at = displayCenter(forUUID: focused.displayIdentifier)
            ?? CGPoint(x: CGFloat.nan, y: CGFloat.nan)
        withSwitchDebug(action: action, steps: abs(steps), direction: direction,
                        focused: focused, target: target, at: at,
                        connection: connection) {
            for _ in 0..<abs(steps) {
                MSSSwitchSpaceGesture(direction, at.x, at.y)
            }
        }
    }

    /// Moves the focused window to the adjacent desktop Space (left/right) on the
    /// focused display, then follows it via the existing instant swipe. No-ops
    /// safely when the layout/window can't be read or the neighbor isn't a
    /// desktop (end of list or a fullscreen Space). `action` is `.left`/`.right`.
    func moveFocusedWindow(_ action: Action) {
        let connection = CGSMainConnectionID()
        guard let cfDisplays = CGSCopyManagedDisplaySpaces(connection),
              let rawDisplays = (cfDisplays as NSArray) as? [[String: Any]] else {
            logError("could not read display spaces")
            return
        }
        let layouts = SpaceLogic.parseDisplaySpaces(rawDisplays)
        let uuid = activeMenuBarDisplay(connection) ?? currentDisplayUUID()
        guard let focused = SpaceLogic.focusedDisplay(
            in: layouts, focusedUUID: uuid, isPrimary: isMainDisplayPrimary()
        ) else {
            logError("could not determine focused display")
            return
        }
        guard let target = SpaceLogic.adjacentDesktop(for: action, in: focused) else {
            debugLog("\(action): no-op "
                     + "(no adjacent desktop on \(focused.displayIdentifier))")
            return
        }
        guard let windowID = focusedWindowID() else { return }
        debugLog("\(action): move window \(windowID) "
                 + "\(focused.currentSpaceID) -> \(target), then follow")
        CGSMoveWindowsToManagedSpace(connection,
                                     [NSNumber(value: windowID)] as CFArray,
                                     target)
        switchSpace(action) // follow — one swipe lands on the same neighbor
    }

    /// CGWindowID of the frontmost app's focused window, via the Accessibility
    /// API. nil (logged) when there's no frontmost app, no standard focused
    /// window (e.g. Finder desktop), or the id can't be resolved.
    private func focusedWindowID() -> CGWindowID? {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            logError("no frontmost application")
            return nil
        }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
                  appElement, kAXFocusedWindowAttribute as CFString, &value
              ) == .success,
              let window = value, CFGetTypeID(window) == AXUIElementGetTypeID() else {
            logError("no focused window for \(app.localizedName ?? "frontmost app")")
            return nil
        }
        var windowID: CGWindowID = 0
        guard _AXUIElementGetWindow((window as! AXUIElement), &windowID) == .success,
              windowID != 0 else {
            logError("could not resolve focused window id")
            return nil
        }
        return windowID
    }

    /// Runs `performSwitch` and, when MSS_DEBUG is set, brackets it with a
    /// before/after snapshot for diagnosing space/display issues: the target and
    /// the three display signals (menu-bar / cursor / NSScreen.main), then the
    /// active space and on-screen window set before vs. after the swipe. When
    /// debugging is off this just runs the switch with no overhead.
    private func withSwitchDebug(action: Action, steps: Int, direction: Int32,
                                 focused: DisplayLayout, target: UInt64,
                                 at: CGPoint, connection: CGSConnectionID,
                                 performSwitch: () -> Void) {
        guard debugEnabled else {
            performSwitch()
            return
        }
        let dir = direction > 0 ? "right" : "left"
        debugLog("\(action): \(steps) swipe(s) \(dir) on \(focused.displayIdentifier) "
                 + "(\(focused.currentSpaceID) -> \(target)) at (\(at.x), \(at.y)); "
                 + "menubar=\(activeMenuBarDisplay(connection) ?? "nil") "
                 + "cursor=\(cursorDisplayUUID()) nsmain=\(currentDisplayUUID())")
        let beforeActive = CGSGetActiveSpace(connection)
        let beforeWindows = onScreenWindows()
        performSwitch()
        usleep(150_000)
        debugLog("  active space \(beforeActive) -> \(CGSGetActiveSpace(connection)); "
                 + "on-screen \(describe(beforeWindows)) -> \(describe(onScreenWindows()))")
    }

    /// Prints the parsed layout so display/space detection can be verified
    /// without registering hotkeys.
    func dumpLayout() {
        let connection = CGSMainConnectionID()
        guard let cfDisplays = CGSCopyManagedDisplaySpaces(connection),
              let rawDisplays = (cfDisplays as NSArray) as? [[String: Any]] else {
            logError("could not read display spaces")
            return
        }
        let layouts = SpaceLogic.parseDisplaySpaces(rawDisplays)
        print("Focused display UUID: \(currentDisplayUUID()) "
              + "(primary: \(isMainDisplayPrimary()))")
        for display in layouts {
            print("Display \(display.displayIdentifier) "
                  + "— current space \(display.currentSpaceID)")
            for (index, space) in display.spaces.enumerated() {
                let kind = space.type == 0 ? "desktop" : "type \(space.type)"
                print("  [\(index)] id=\(space.id) (\(kind))")
            }
        }
    }

    /// Investigative probe: measures whether `CGSManagedDisplaySetCurrentSpace`
    /// actually moves the visible space. Uses the public on-screen window list as
    /// ground truth (independent of SkyLight's own metadata, which just echoes our
    /// write) plus `CGSGetActiveSpace` as a second signal. Restores metadata after.
    func probeSwitch() {
        let connection = CGSMainConnectionID()
        let realActive = CGSGetActiveSpace(connection)
        guard let cfDisplays = CGSCopyManagedDisplaySpaces(connection),
              let rawDisplays = (cfDisplays as NSArray) as? [[String: Any]] else {
            logError("could not read display spaces")
            return
        }
        let layouts = SpaceLogic.parseDisplaySpaces(rawDisplays)
        guard let focused = SpaceLogic.focusedDisplay(
            in: layouts,
            focusedUUID: currentDisplayUUID(),
            isPrimary: isMainDisplayPrimary()
        ) else {
            logError("could not determine focused display")
            return
        }
        let desktops = focused.spaces.filter { $0.type == 0 }
        guard let target = desktops.first(where: { $0.id != realActive })
                ?? desktops.first(where: { $0.id != focused.currentSpaceID }) else {
            print("Probe needs >= 2 desktop spaces on the focused display; "
                  + "found \(desktops.count).")
            return
        }

        let before = onScreenWindows()
        print("Display \(focused.displayIdentifier)")
        print("CGSGetActiveSpace (real):  \(realActive)")
        print("Managed current space:     \(focused.currentSpaceID)")
        print("Probing switch -> \(target.id)")
        print("On-screen windows before:  \(describe(before))")

        CGSManagedDisplaySetCurrentSpace(connection,
                                         focused.displayIdentifier as CFString,
                                         target.id)
        usleep(400_000)

        let realActiveAfter = CGSGetActiveSpace(connection)
        let after = onScreenWindows()
        print("CGSGetActiveSpace after:   \(realActiveAfter)")
        print("On-screen windows after:   \(describe(after))")

        let activeChanged = realActive != realActiveAfter
        let windowsChanged = Set(before.keys) != Set(after.keys)
        print("---")
        print("Real active-space changed: \(activeChanged); "
              + "on-screen windows changed: \(windowsChanged)")
        if !activeChanged && !windowsChanged {
            print("VERDICT: BLOCKED — metadata is writable but the WindowServer "
                  + "does not perform the switch from this process.")
        } else {
            print("VERDICT: a REAL switch occurred via this userspace call.")
        }

        // Restore metadata to the real active space so we don't leave it pointing
        // at a space we never actually moved to.
        CGSManagedDisplaySetCurrentSpace(connection,
                                         focused.displayIdentifier as CFString,
                                         realActive)
    }

    /// Investigative probe (companion to probeSwitch): measures whether
    /// `CGSMoveWindowsToManagedSpace` actually moves the focused window to
    /// another Space. Uses `CGSCopySpacesForWindows` as ground truth — the
    /// window's Space membership before vs. after the call. Restores the window
    /// to its original Space if the move took effect.
    func probeMoveWindow() {
        let connection = CGSMainConnectionID()
        guard let windowID = focusedWindowID() else {
            print("Probe needs a focused window; none resolved. "
                  + "Focus a normal window, then run --probe-move.")
            return
        }
        guard let cfDisplays = CGSCopyManagedDisplaySpaces(connection),
              let rawDisplays = (cfDisplays as NSArray) as? [[String: Any]] else {
            logError("could not read display spaces")
            return
        }
        let layouts = SpaceLogic.parseDisplaySpaces(rawDisplays)
        let uuid = activeMenuBarDisplay(connection) ?? currentDisplayUUID()
        guard let focused = SpaceLogic.focusedDisplay(
            in: layouts, focusedUUID: uuid, isPrimary: isMainDisplayPrimary()
        ) else {
            logError("could not determine focused display")
            return
        }
        let desktops = focused.spaces.filter { $0.type == 0 }
        guard let target = desktops.first(where: { $0.id != focused.currentSpaceID })
        else {
            print("Probe needs >= 2 desktop spaces on the focused display; "
                  + "found \(desktops.count).")
            return
        }

        let windows = [NSNumber(value: windowID)] as CFArray
        let before = spacesForWindows(connection, windows)
        print("Focused window:        \(windowID)")
        print("Focused display:       \(focused.displayIdentifier)")
        print("Current space:         \(focused.currentSpaceID)")
        print("Window spaces before:  \(before)")
        print("Moving window -> space \(target.id) ...")

        CGSMoveWindowsToManagedSpace(connection, windows, target.id)
        usleep(300_000)

        let after = spacesForWindows(connection, windows)
        print("Window spaces after:   \(after)")
        print("---")
        if Set(before) != Set(after) {
            print("VERDICT: the move WORKED — window Space membership changed.")
            CGSMoveWindowsToManagedSpace(connection, windows, focused.currentSpaceID)
            print("(restored window to space \(focused.currentSpaceID))")
        } else {
            print("VERDICT: BLOCKED — CGSMoveWindowsToManagedSpace is a no-op from "
                  + "this process (needs the SIP scripting addition).")
        }
    }

    /// Space ids the given windows belong to, via the private
    /// CGSCopySpacesForWindows (mask 0x7 = all space types). Empty on failure.
    private func spacesForWindows(_ connection: CGSConnectionID,
                                  _ windows: CFArray) -> [UInt64] {
        guard let cf = CGSCopySpacesForWindows(connection, 0x7, windows),
              let arr = (cf as NSArray) as? [NSNumber] else { return [] }
        return arr.map { $0.uint64Value }
    }

    /// Window number -> owning app name for the normal (layer 0) windows that are
    /// currently composited on screen, i.e. the windows of the visible space.
    private func onScreenWindows() -> [Int: String] {
        let options: CGWindowListOption = [.optionOnScreenOnly,
                                           .excludeDesktopElements]
        guard let infos = CGWindowListCopyWindowInfo(options, kCGNullWindowID)
                as? [[String: Any]] else { return [:] }
        var result: [Int: String] = [:]
        for info in infos {
            let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
            guard layer == 0,
                  let num = (info[kCGWindowNumber as String] as? NSNumber)?.intValue
            else { continue }
            result[num] = (info[kCGWindowOwnerName as String] as? String) ?? "?"
        }
        return result
    }

    private func describe(_ windows: [Int: String]) -> String {
        let names = Set(windows.values).sorted()
        return "\(windows.count) windows [\(names.joined(separator: ", "))]"
    }

    /// Identifier of the display whose menu bar is active (i.e. where the
    /// frontmost app lives). Matches a "Display Identifier" from
    /// CGSCopyManagedDisplaySpaces. nil if the API returns nothing.
    private func activeMenuBarDisplay(_ connection: CGSConnectionID) -> String? {
        guard let cf = CGSCopyActiveMenuBarDisplayIdentifier(connection) else {
            return nil
        }
        return cf as String
    }

    /// Center of the display with the given UUID, in global top-left CG
    /// coordinates (what CGEventSetLocation expects). nil if not found — e.g.
    /// the "Main" special-case identifier, which isn't a real display UUID.
    private func displayCenter(forUUID uuid: String) -> CGPoint? {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else {
            return nil
        }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else {
            return nil
        }
        for id in ids {
            guard let cfUUID = CGDisplayCreateUUIDFromDisplayID(id)?
                .takeRetainedValue() else { continue }
            if (CFUUIDCreateString(nil, cfUUID) as String) == uuid {
                let bounds = CGDisplayBounds(id)
                return CGPoint(x: bounds.midX, y: bounds.midY)
            }
        }
        return nil
    }

    /// UUID string of the display under the mouse cursor (for debug logging).
    private func cursorDisplayUUID() -> String {
        let location = NSEvent.mouseLocation // Cocoa coords; only display match matters
        var displayID = CGDirectDisplayID(0)
        var matchCount: UInt32 = 0
        for screen in NSScreen.screens {
            if screen.frame.contains(location),
               let number = screen.deviceDescription[
                NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
                displayID = CGDirectDisplayID(number.uint32Value)
                matchCount = 1
                break
            }
        }
        guard matchCount > 0,
              let cfUUID = CGDisplayCreateUUIDFromDisplayID(displayID)?
                .takeRetainedValue() else { return "unknown" }
        return CFUUIDCreateString(nil, cfUUID) as String
    }

    /// The UUID string of the focused display, or "Main" if it can't be read.
    private func currentDisplayUUID() -> String {
        guard let screen = NSScreen.main,
              let number = screen.deviceDescription[
                NSDeviceDescriptionKey("NSScreenNumber")
              ] as? NSNumber else {
            return "Main"
        }
        let displayID = CGDirectDisplayID(number.uint32Value)
        guard let cfUUID = CGDisplayCreateUUIDFromDisplayID(displayID)?
            .takeRetainedValue() else {
            return "Main"
        }
        return CFUUIDCreateString(nil, cfUUID) as String
    }

    /// Whether the focused display is also the primary (menu-bar) display.
    private func isMainDisplayPrimary() -> Bool {
        NSScreen.main == NSScreen.screens.first
    }

    private func logError(_ message: String) {
        FileHandle.standardError.write(
            Data("mac-spaces-switcher: \(message)\n".utf8))
    }
}

import Carbon

/// Registers global hotkeys via Carbon and invokes a callback with the matched
/// Action on each press. Knows nothing about Spaces.
final class HotkeyManager {
    private let onPress: (Action) -> Void
    private var actionsByID: [UInt32: Action] = [:]
    private var hotKeyRefs: [EventHotKeyRef?] = []
    private var handlerRef: EventHandlerRef?
    private var nextID: UInt32 = 1

    init(onPress: @escaping (Action) -> Void) {
        self.onPress = onPress
        installHandler()
    }

    /// Registers each binding. Logs a warning (pointing at the README setup) for
    /// any hotkey that fails to register — usually because the native shortcut
    /// is still enabled.
    func register(_ bindings: [Action: Hotkey]) {
        for (action, hotkey) in bindings {
            let id = nextID
            nextID += 1
            actionsByID[id] = action

            let hotKeyID = EventHotKeyID(signature: OSType(0x4D535357), id: id) // 'MSSW'
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(
                hotkey.keyCode,
                hotkey.modifiers,
                hotKeyID,
                GetEventDispatcherTarget(),
                0,
                &ref
            )
            if status == noErr {
                hotKeyRefs.append(ref)
                debugLog("registered \(action) "
                         + "keyCode=0x\(String(hotkey.keyCode, radix: 16)) "
                         + "modifiers=0x\(String(hotkey.modifiers, radix: 16))")
            } else {
                warn("failed to register hotkey for \(action) "
                     + "(status \(status)); is the native shortcut still enabled? "
                     + "See README setup.")
            }
        }
    }

    private func installHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, event, userData in
                guard let event, let userData else { return noErr }
                var hotKeyID = EventHotKeyID()
                GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                let manager = Unmanaged<HotkeyManager>
                    .fromOpaque(userData).takeUnretainedValue()
                if let action = manager.actionsByID[hotKeyID.id] {
                    debugLog("hotkey pressed -> \(action)")
                    manager.onPress(action)
                } else {
                    debugLog("hotkey event for unknown id \(hotKeyID.id)")
                }
                return noErr
            },
            1,
            &eventType,
            selfPtr,
            &handlerRef
        )
    }

    private func warn(_ message: String) {
        FileHandle.standardError.write(
            Data("mac-spaces-switcher: \(message)\n".utf8))
    }
}

import Carbon.HIToolbox

/// System-wide shortcuts through Carbon hot keys, which work without the Accessibility permission.
@MainActor
final class HotKeyCenter {
    /// The 1 to 9 keys of the main keyboard row.
    private static let digitKeyCodes = [
        kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5, kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9,
    ]
    /// Tags this app's hot keys ('VMIX').
    nonisolated private static let signature: OSType = 0x564D_4958

    private var handler: EventHandlerRef?
    private var hotKeys: [EventHotKeyRef] = []
    private var actions: [UInt32: () -> Void] = [:]

    /// Runs `action` on Control-Option-`number` (1...9), whichever app is in front. A combination
    /// another app already holds is skipped with a log line and returns false.
    @discardableResult
    func registerControlOption(number: Int, action: @escaping () -> Void) -> Bool {
        guard Self.digitKeyCodes.indices.contains(number - 1) else { return false }
        installHandlerIfNeeded()
        let id = UInt32(number)
        var hotKey: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(Self.digitKeyCodes[number - 1]),
            UInt32(controlKey | optionKey),
            EventHotKeyID(signature: Self.signature, id: id),
            GetApplicationEventTarget(),
            0,
            &hotKey
        )
        guard status == noErr, let hotKey else {
            log.error("Control-Option-\(number) is taken by another app (\(status))")
            return false
        }
        hotKeys.append(hotKey)
        actions[id] = action
        return true
    }

    func unregisterAll() {
        for hotKey in hotKeys {
            UnregisterEventHotKey(hotKey)
        }
        hotKeys.removeAll()
        actions.removeAll()
    }

    private func installHandlerIfNeeded() {
        guard handler == nil else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, context in
                guard let event, let context else { return OSStatus(eventNotHandledErr) }
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                // Other hot keys of this app (KeyboardShortcuts) carry their own signature.
                guard status == noErr, hotKeyID.signature == HotKeyCenter.signature else {
                    return OSStatus(eventNotHandledErr)
                }
                let center = Unmanaged<HotKeyCenter>.fromOpaque(context).takeUnretainedValue()
                // Carbon delivers hot keys on the main thread.
                MainActor.assumeIsolated { center.fire(hotKeyID.id) }
                return noErr
            },
            1,
            &eventType,
            context,
            &handler
        )
    }

    private func fire(_ id: UInt32) {
        actions[id]?()
    }
}

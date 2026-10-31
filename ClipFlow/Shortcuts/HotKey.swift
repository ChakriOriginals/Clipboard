import Carbon.HIToolbox

enum HotKeyError: Error, Equatable {
    case invalidShortcut
    /// Usually `eventHotKeyExistsErr`: another app owns this combination.
    case registrationFailed(OSStatus)
}

/// A system-wide hotkey via Carbon `RegisterEventHotKey` (public API, no permission required).
@MainActor
final class HotKey {
    let id: UInt32
    private nonisolated(unsafe) var ref: EventHotKeyRef?

    private static var actions: [UInt32: () -> Void] = [:]
    private static var nextID: UInt32 = 1
    private static var handlerInstalled = false

    init(shortcut: Shortcut, action: @escaping () -> Void) throws {
        guard shortcut.isValid else { throw HotKeyError.invalidShortcut }
        Self.installHandlerIfNeeded()
        id = Self.nextID
        Self.nextID &+= 1
        let hotKeyID = EventHotKeyID(signature: OSType(0x4346_4C57), id: id) // 'CFLW'
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(shortcut.keyCode, shortcut.carbonModifiers, hotKeyID,
                                         GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else { throw HotKeyError.registrationFailed(status) }
        self.ref = ref
        Self.actions[id] = action
    }

    func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
        Self.actions[id] = nil
    }

    deinit {
        if let ref { UnregisterEventHotKey(ref) }
        let id = self.id
        Task { @MainActor in HotKey.actions[id] = nil }
    }

    static func dispatch(id: UInt32) {
        actions[id]?()
    }

    private static func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                           nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            guard status == noErr else { return status }
            let id = hotKeyID.id
            // Carbon delivers application-target events on the main thread.
            MainActor.assumeIsolated { HotKey.dispatch(id: id) }
            return noErr
        }, 1, &spec, nil, nil)
    }
}

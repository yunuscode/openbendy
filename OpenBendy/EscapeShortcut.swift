import Carbon

/// Registers Esc only while the effect runs, without an Accessibility event tap.
@MainActor
final class EscapeShortcut {
    private var key: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var action: (() -> Void)?
    func start(action: @escaping () -> Void) -> Bool {
        stop(); self.action = action
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            let shortcut = Unmanaged<EscapeShortcut>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { shortcut.action?() }
            return noErr
        }, 1, &event, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard installed == noErr else { return false }
        let id = EventHotKeyID(signature: 0x424E4459, id: 1)
        let registered = RegisterEventHotKey(UInt32(kVK_Escape), 0, id, GetApplicationEventTarget(), 0, &key)
        if registered != noErr { stop(); return false }
        return true
    }
    func stop() {
        if let key { UnregisterEventHotKey(key) }; key = nil
        if let handler { RemoveEventHandler(handler) }; handler = nil
        action = nil
    }
}

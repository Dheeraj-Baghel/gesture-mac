import AppKit
import Carbon

// Carbon registers a single explicit stop shortcut; unlike a keyboard event
// tap, this does not watch the user's typing or need Input Monitoring access.
final class EmergencyHotKey {
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    var onStop: (() -> Void)?
    @discardableResult
    func register() -> Bool {
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        let result = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let context = context else { return OSStatus(eventNotHandledErr) }
            let owner = Unmanaged<EmergencyHotKey>.fromOpaque(context).takeUnretainedValue()
            owner.onStop?()
            return noErr
        }, 1, &event, context, &handler)
        guard result == noErr else { return false }
        let id = EventHotKeyID(signature: 0x474D4143, id: 1)
        let status = RegisterEventHotKey(UInt32(kVK_ANSI_G), UInt32(cmdKey | optionKey | controlKey),
                                        id, GetApplicationEventTarget(), 0, &hotKey)
        return status == noErr
    }
    deinit {
        if let hotKey = hotKey { UnregisterEventHotKey(hotKey) }
        if let handler = handler { RemoveEventHandler(handler) }
    }
}

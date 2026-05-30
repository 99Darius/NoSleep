import Carbon
import AppKit

final class HotkeyManager {
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let onPress: () -> Void

    init(onPress: @escaping () -> Void) {
        self.onPress = onPress
    }

    /// Returns true on success; false if the combo is already taken.
    @discardableResult
    func register() -> Bool {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: OSType(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, ctx in
            let mgr = Unmanaged<HotkeyManager>.fromOpaque(ctx!).takeUnretainedValue()
            mgr.onPress()
            return noErr
        }, 1, &spec, selfPtr, &handler)

        let id = EventHotKeyID(signature: OSType(0x4E534C50), id: 1) // 'NSLP'
        let mods = UInt32(cmdKey | controlKey)
        let status = RegisterEventHotKey(UInt32(kVK_ANSI_Z), mods,
                                         id, GetApplicationEventTarget(), 0, &ref)
        return status == noErr
    }

    func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        if let handler { RemoveEventHandler(handler) }
        ref = nil; handler = nil
    }
}

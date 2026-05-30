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
        // Avoid orphaning a previously installed handler/hotkey on a double-register.
        if handler != nil || ref != nil { unregister() }

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: OSType(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let handlerStatus = InstallEventHandler(GetApplicationEventTarget(), { _, event, ctx in
            let mgr = Unmanaged<HotkeyManager>.fromOpaque(ctx!).takeUnretainedValue()
            mgr.onPress()
            return noErr
        }, 1, &spec, selfPtr, &handler)
        guard handlerStatus == noErr else {
            unregister()
            return false
        }

        let id = EventHotKeyID(signature: OSType(0x4E534C50), id: 1) // 'NSLP'
        let mods = UInt32(cmdKey | controlKey)
        let status = RegisterEventHotKey(UInt32(kVK_ANSI_Z), mods,
                                         id, GetApplicationEventTarget(), 0, &ref)
        guard status == noErr else {
            unregister()
            return false
        }
        return true
    }

    func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        if let handler { RemoveEventHandler(handler) }
        ref = nil; handler = nil
    }
}

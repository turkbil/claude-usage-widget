import AppKit
import Carbon.HIToolbox

/// Wraps Carbon's RegisterEventHotKey API to listen for a single global
/// keyboard shortcut. macOS provides no Swift-native equivalent.
final class HotKeyManager {

    static let shared = HotKeyManager()

    private var hotKeyRef:  EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var callback:   (() -> Void)?

    private init() {}

    /// Register or replace the active hotkey. Pass enabled=false to unregister.
    func apply(prefs: Preferences, onTrigger: @escaping () -> Void) {
        unregister()
        guard prefs.hotkeyEnabled else { return }
        self.callback = onTrigger

        // Install one shared event handler if not already.
        if handlerRef == nil {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                     eventKind: UInt32(kEventHotKeyPressed))
            let pointer = Unmanaged.passUnretained(self).toOpaque()
            InstallEventHandler(GetApplicationEventTarget(),
                                { _, _, userData -> OSStatus in
                                    guard let ud = userData else { return noErr }
                                    let m = Unmanaged<HotKeyManager>.fromOpaque(ud).takeUnretainedValue()
                                    DispatchQueue.main.async { m.callback?() }
                                    return noErr
                                },
                                1, &spec, pointer, &handlerRef)
        }

        // 'CUW1' = ClaudeUsageWidget hotkey #1
        let hotKeyID = EventHotKeyID(signature: signatureFourCC(), id: 1)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            prefs.hotkeyKeyCode,
            prefs.hotkeyModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0, &ref
        )
        if status == noErr { hotKeyRef = ref }
    }

    func unregister() {
        if let hk = hotKeyRef { UnregisterEventHotKey(hk); hotKeyRef = nil }
    }

    /// Human-readable label like "⌘⌥U".
    static func label(keyCode: UInt32, modifiers: UInt32) -> String {
        var out = ""
        if (modifiers & UInt32(controlKey)) != 0 { out += "⌃" }
        if (modifiers & UInt32(optionKey))  != 0 { out += "⌥" }
        if (modifiers & UInt32(shiftKey))   != 0 { out += "⇧" }
        if (modifiers & UInt32(cmdKey))     != 0 { out += "⌘" }
        out += keyLabel(for: keyCode)
        return out
    }

    private static func keyLabel(for keyCode: UInt32) -> String {
        // Common mappings; for the full table use UCKeyTranslate but this is enough for letters/numbers.
        let map: [UInt32: String] = [
            0x00:"A",0x0B:"B",0x08:"C",0x02:"D",0x0E:"E",0x03:"F",0x05:"G",0x04:"H",
            0x22:"I",0x26:"J",0x28:"K",0x25:"L",0x2E:"M",0x2D:"N",0x1F:"O",0x23:"P",
            0x0C:"Q",0x0F:"R",0x01:"S",0x11:"T",0x20:"U",0x09:"V",0x0D:"W",0x07:"X",
            0x10:"Y",0x06:"Z",
            0x12:"1",0x13:"2",0x14:"3",0x15:"4",0x17:"5",0x16:"6",0x1A:"7",0x1C:"8",
            0x19:"9",0x1D:"0",
            0x31:"Space", 0x24:"Return", 0x35:"Esc",
        ]
        return map[keyCode] ?? "·"
    }

    private func signatureFourCC() -> OSType {
        // 'CUW1' as a 4-byte signature
        var v: OSType = 0
        for c in "CUW1".utf8 { v = (v << 8) | OSType(c) }
        return v
    }
}

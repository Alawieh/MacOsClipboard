//
//  HotKeyService.swift
//  ClipBoard
//
//  A system-wide hot key (⌘⇧V) through Carbon, which needs no extra permission.
//

import Carbon.HIToolbox
import OSLog

/// Registers one global hot key and calls `onPress` on the main actor each time it is pressed,
/// whichever app is in front. While registered, the key combination is taken from every other app.
@MainActor
final class HotKeyService {
    private let onPress: @MainActor () -> Void
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    init(onPress: @escaping @MainActor () -> Void) {
        self.onPress = onPress
    }

    /// - Returns: false if the combination is already taken by another app or the handler failed.
    @discardableResult
    func register(keyCode: UInt32 = HOTKEY_KEY_CODE, modifiers: UInt32 = HOTKEY_MODIFIERS) -> Bool {
        unregister()
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        let handlerStatus = InstallEventHandler(GetApplicationEventTarget(), hotKeyEventHandler, 1, &eventType, context, &handlerRef)
        guard handlerStatus == noErr else {
            Log.hotKey.error("InstallEventHandler failed: \(handlerStatus)")
            return false
        }
        let hotKeyID = EventHotKeyID(signature: HOTKEY_SIGNATURE, id: 1)
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        guard status == noErr else {
            Log.hotKey.error("RegisterEventHotKey failed: \(status)")
            unregister()
            return false
        }
        return true
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
        hotKeyRef = nil
        handlerRef = nil
    }

    fileprivate func handlePress() {
        onPress()
    }
}

/// Carbon delivers hot key events on the main run loop.
private func hotKeyEventHandler(_ next: EventHandlerCallRef?, _ event: EventRef?, _ context: UnsafeMutableRawPointer?) -> OSStatus {
    guard let context else { return OSStatus(eventNotHandledErr) }
    let service = Unmanaged<HotKeyService>.fromOpaque(context).takeUnretainedValue()
    MainActor.assumeIsolated { service.handlePress() }
    return noErr
}

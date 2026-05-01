import Foundation
import Carbon.HIToolbox
import SwiftUI

// MARK: - Global hotkeys (Carbon)

final class HotkeyManager: ObservableObject, HotkeyRegistrable {
    @Published private(set) var lastError: String?

    private var eventHandler: EventHandlerRef?
    private var eventHandlerUserData: UnsafeMutableRawPointer?
    private var hotkeyRefs: [HotkeyID: EventHotKeyRef] = [:]
    private var callbacks: [HotkeyID: () -> Void] = [:]
    
    func register(id: HotkeyID, hotkey: Hotkey, callback: @escaping () -> Void) {
        guard hotkey.isValid else {
            reportError("Invalid hotkey for \(id.label). Use Cmd+Shift with F1-F12.")
            return
        }

        var hotKeyRef: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(UInt32(bitPattern: 0x53484B31)), id: id.rawValue) // 'SHK1'
        let status = RegisterEventHotKey(
            hotkey.keyCode,
            hotkey.carbonModifierMask,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        guard status == noErr, let hotKeyRef else {
            reportError("Could not register \(hotkey.displayName) for \(id.label) (Carbon status \(status)).")
            return
        }

        guard installHandlerIfNeeded() else {
            UnregisterEventHotKey(hotKeyRef)
            return
        }

        hotkeyRefs[id] = hotKeyRef
        callbacks[id] = callback
    }
    
    func unregisterAll() {
        for (_, ref) in hotkeyRefs { UnregisterEventHotKey(ref) }
        hotkeyRefs.removeAll()
        callbacks.removeAll()
        if let handler = eventHandler {
            RemoveEventHandler(handler)
            eventHandler = nil
        }
        if let eventHandlerUserData {
            Unmanaged<HotkeyManager>.fromOpaque(eventHandlerUserData).release()
            self.eventHandlerUserData = nil
        }
        clearError()
    }

    func clearError() {
        if Thread.isMainThread {
            lastError = nil
        } else {
            DispatchQueue.main.async { [weak self] in self?.lastError = nil }
        }
    }
    
    deinit { unregisterAll() }
    
    private func installHandlerIfNeeded() -> Bool {
        guard eventHandler == nil else { return true }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        let userData = UnsafeMutableRawPointer(Unmanaged.passRetained(self).toOpaque())
        var installedHandler: EventHandlerRef?
        let status = InstallEventHandler(GetApplicationEventTarget(), { (_, event, userData) -> OSStatus in
            var hkID = EventHotKeyID()
            let status = GetEventParameter(event,
                                           EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID),
                                           nil,
                                           MemoryLayout<EventHotKeyID>.size,
                                           nil,
                                           &hkID)
            if status == noErr, let userData {
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                if let id = HotkeyID(rawValue: hkID.id), let cb = manager.callbacks[id] { cb() }
            }
            return noErr
        }, 1, &eventType, userData, &installedHandler)

        guard status == noErr, let installedHandler else {
            Unmanaged<HotkeyManager>.fromOpaque(userData).release()
            reportError("Could not install the global hotkey handler (Carbon status \(status)).")
            return false
        }

        eventHandler = installedHandler
        eventHandlerUserData = userData
        return true
    }

    private func reportError(_ message: String) {
        print(message)
        if Thread.isMainThread {
            lastError = message
        } else {
            DispatchQueue.main.async { [weak self] in self?.lastError = message }
        }
    }
}

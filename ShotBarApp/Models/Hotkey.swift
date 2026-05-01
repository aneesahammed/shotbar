import Foundation
import Carbon.HIToolbox

// MARK: - Hotkey Model

struct Hotkey: Codable, Equatable, Identifiable {
    static let requiredModifierMask = UInt32(cmdKey | shiftKey)

    var keyCode: UInt32
    var modifierMask: UInt32

    var id: String { "kc-\(keyCode)-mods-\(modifierMask)" }

    init(keyCode: UInt32, modifierMask: UInt32 = Hotkey.requiredModifierMask) {
        self.keyCode = keyCode
        self.modifierMask = modifierMask
    }

    enum CodingKeys: String, CodingKey {
        case keyCode
        case modifierMask
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        keyCode = try container.decode(UInt32.self, forKey: .keyCode)
        modifierMask = try container.decodeIfPresent(UInt32.self, forKey: .modifierMask) ?? Hotkey.requiredModifierMask
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(keyCode, forKey: .keyCode)
        try container.encode(modifierMask, forKey: .modifierMask)
    }

    static let allFKeys: [Hotkey] = [
        Hotkey(keyCode: UInt32(kVK_F1)),  Hotkey(keyCode: UInt32(kVK_F2)),
        Hotkey(keyCode: UInt32(kVK_F3)),  Hotkey(keyCode: UInt32(kVK_F4)),
        Hotkey(keyCode: UInt32(kVK_F5)),  Hotkey(keyCode: UInt32(kVK_F6)),
        Hotkey(keyCode: UInt32(kVK_F7)),  Hotkey(keyCode: UInt32(kVK_F8)),
        Hotkey(keyCode: UInt32(kVK_F9)),  Hotkey(keyCode: UInt32(kVK_F10)),
        Hotkey(keyCode: UInt32(kVK_F11)), Hotkey(keyCode: UInt32(kVK_F12)),
    ]
    
    var keyName: String {
        switch Int(keyCode) {
        case kVK_F1: return "F1";  case kVK_F2: return "F2";  case kVK_F3: return "F3"
        case kVK_F4: return "F4";  case kVK_F5: return "F5";  case kVK_F6: return "F6"
        case kVK_F7: return "F7";  case kVK_F8: return "F8";  case kVK_F9: return "F9"
        case kVK_F10: return "F10"; case kVK_F11: return "F11"; case kVK_F12: return "F12"
        default: return "KeyCode \(keyCode)"
        }
    }

    var displayName: String {
        "Cmd+Shift+\(keyName)"
    }

    var carbonModifierMask: UInt32 {
        modifierMask
    }

    var isValid: Bool {
        Hotkey.allowedKeyCodes.contains(keyCode) && Hotkey.hasRequiredModifiers(modifierMask)
    }

    static func hasRequiredModifiers(_ modifierMask: UInt32) -> Bool {
        modifierMask == requiredModifierMask
    }

    private static let allowedKeyCodes = Set(allFKeys.map(\.keyCode))
}

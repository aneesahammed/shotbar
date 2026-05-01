import Foundation
import SwiftUI

// MARK: - Preferences Model

final class Preferences: ObservableObject, UserDefaultsSavable {
    @Published var selectionHotkey: Hotkey? { didSet { save() } }
    @Published var windowHotkey: Hotkey?    { didSet { save() } }
    @Published var screenHotkey: Hotkey?    { didSet { save() } }
    @Published var imageFormat: ImageFormat = .png { didSet { save() } }
    @Published var destination: Destination = .clipboard { didSet { save() } }
    @Published var soundEnabled: Bool = true { didSet { save() } }
    
    private let defaults = UserDefaults.standard
    
    init() {
        selectionHotkey = load(key: AppConstants.UserDefaultsKeys.selectionHotkey) ?? Hotkey(keyCode: AppConstants.defaultSelectionHotkey)
        windowHotkey    = load(key: AppConstants.UserDefaultsKeys.windowHotkey)    ?? Hotkey(keyCode: AppConstants.defaultWindowHotkey)
        screenHotkey    = load(key: AppConstants.UserDefaultsKeys.screenHotkey)    ?? Hotkey(keyCode: AppConstants.defaultScreenHotkey)
        if let raw: String = defaults.string(forKey: AppConstants.UserDefaultsKeys.imageFormat), let f = ImageFormat(rawValue: raw) { imageFormat = f }
        if let raw: String = defaults.string(forKey: AppConstants.UserDefaultsKeys.destination), let d = Destination(rawValue: raw) { destination = d }
        if defaults.object(forKey: AppConstants.UserDefaultsKeys.soundEnabled) != nil { soundEnabled = defaults.bool(forKey: AppConstants.UserDefaultsKeys.soundEnabled) }
    }
    
    func save() {
        save(selectionHotkey, key: AppConstants.UserDefaultsKeys.selectionHotkey)
        save(windowHotkey,    key: AppConstants.UserDefaultsKeys.windowHotkey)
        save(screenHotkey,    key: AppConstants.UserDefaultsKeys.screenHotkey)
        defaults.set(imageFormat.rawValue, forKey: AppConstants.UserDefaultsKeys.imageFormat)
        defaults.set(destination.rawValue, forKey: AppConstants.UserDefaultsKeys.destination)
        defaults.set(soundEnabled, forKey: AppConstants.UserDefaultsKeys.soundEnabled)
    }
    
    private func save(_ hk: Hotkey?, key: String) {
        if let hk, let data = try? JSONEncoder().encode(hk) {
            defaults.set(data, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
    
    private func load(key: String) -> Hotkey? {
        guard let data = defaults.data(forKey: key) else { return nil }
        guard let hotkey = try? JSONDecoder().decode(Hotkey.self, from: data),
              hotkey.isValid else {
            defaults.removeObject(forKey: key)
            return nil
        }
        return hotkey
    }
}

import Foundation
import SwiftUI

// MARK: - Preferences Model

final class Preferences: ObservableObject, UserDefaultsSavable {
    @Published var selectionHotkey: Hotkey? { didSet { persistIfLoaded() } }
    @Published var windowHotkey: Hotkey?    { didSet { persistIfLoaded() } }
    @Published var screenHotkey: Hotkey?    { didSet { persistIfLoaded() } }
    @Published var imageFormat: ImageFormat = .png { didSet { persistIfLoaded() } }
    @Published var destination: Destination = .clipboard { didSet { persistIfLoaded() } }
    @Published var soundEnabled: Bool = true { didSet { persistIfLoaded() } }
    @Published var previewEnabled: Bool = true { didSet { persistIfLoaded() } }
    @Published var previewDuration: TimeInterval = AppConstants.previewDefaultDuration { didSet { persistIfLoaded() } }
    @Published var previewCorner: PreviewCorner = .bottomRight { didSet { persistIfLoaded() } }
    @Published var previewScreenChoice: PreviewScreenChoice = .cursorScreen { didSet { persistIfLoaded() } }
    @Published var annotationDefaultColor: AnnotationColor = .red { didSet { persistIfLoaded() } }
    @Published var annotationDefaultStrokeWidth: CGFloat = 4 { didSet { persistIfLoaded() } }
    
    private let defaults: UserDefaults
    private var isLoading = true
    
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        selectionHotkey = load(key: AppConstants.UserDefaultsKeys.selectionHotkey) ?? Hotkey(keyCode: AppConstants.defaultSelectionHotkey)
        windowHotkey    = load(key: AppConstants.UserDefaultsKeys.windowHotkey)    ?? Hotkey(keyCode: AppConstants.defaultWindowHotkey)
        screenHotkey    = load(key: AppConstants.UserDefaultsKeys.screenHotkey)    ?? Hotkey(keyCode: AppConstants.defaultScreenHotkey)
        if let raw: String = defaults.string(forKey: AppConstants.UserDefaultsKeys.imageFormat), let f = ImageFormat(rawValue: raw) { imageFormat = f }
        if let raw: String = defaults.string(forKey: AppConstants.UserDefaultsKeys.destination), let d = Destination(rawValue: raw) { destination = d }
        if defaults.object(forKey: AppConstants.UserDefaultsKeys.soundEnabled) != nil { soundEnabled = defaults.bool(forKey: AppConstants.UserDefaultsKeys.soundEnabled) }
        if defaults.object(forKey: AppConstants.UserDefaultsKeys.previewEnabled) != nil { previewEnabled = defaults.bool(forKey: AppConstants.UserDefaultsKeys.previewEnabled) }
        if defaults.object(forKey: AppConstants.UserDefaultsKeys.previewDuration) != nil {
            previewDuration = min(
                AppConstants.previewMaxDuration,
                max(AppConstants.previewMinDuration, defaults.double(forKey: AppConstants.UserDefaultsKeys.previewDuration))
            )
        }
        if let raw = defaults.string(forKey: AppConstants.UserDefaultsKeys.previewCorner),
           let corner = PreviewCorner(rawValue: raw) {
            previewCorner = corner
        }
        if let raw = defaults.string(forKey: AppConstants.UserDefaultsKeys.previewScreenChoice),
           let choice = PreviewScreenChoice(rawValue: raw) {
            previewScreenChoice = choice
        }
        if let raw = defaults.string(forKey: AppConstants.UserDefaultsKeys.annotationDefaultColor),
           let color = AnnotationColor(rawValue: raw) {
            annotationDefaultColor = color
        }
        if defaults.object(forKey: AppConstants.UserDefaultsKeys.annotationDefaultStrokeWidth) != nil {
            annotationDefaultStrokeWidth = max(1, min(24, CGFloat(defaults.double(forKey: AppConstants.UserDefaultsKeys.annotationDefaultStrokeWidth))))
        }
        isLoading = false
    }

    private func persistIfLoaded() {
        guard !isLoading else { return }
        save()
    }
    
    func save() {
        save(selectionHotkey, key: AppConstants.UserDefaultsKeys.selectionHotkey)
        save(windowHotkey,    key: AppConstants.UserDefaultsKeys.windowHotkey)
        save(screenHotkey,    key: AppConstants.UserDefaultsKeys.screenHotkey)
        defaults.set(imageFormat.rawValue, forKey: AppConstants.UserDefaultsKeys.imageFormat)
        defaults.set(destination.rawValue, forKey: AppConstants.UserDefaultsKeys.destination)
        defaults.set(soundEnabled, forKey: AppConstants.UserDefaultsKeys.soundEnabled)
        defaults.set(previewEnabled, forKey: AppConstants.UserDefaultsKeys.previewEnabled)
        defaults.set(previewDuration, forKey: AppConstants.UserDefaultsKeys.previewDuration)
        defaults.set(previewCorner.rawValue, forKey: AppConstants.UserDefaultsKeys.previewCorner)
        defaults.set(previewScreenChoice.rawValue, forKey: AppConstants.UserDefaultsKeys.previewScreenChoice)
        defaults.set(annotationDefaultColor.rawValue, forKey: AppConstants.UserDefaultsKeys.annotationDefaultColor)
        defaults.set(Double(annotationDefaultStrokeWidth), forKey: AppConstants.UserDefaultsKeys.annotationDefaultStrokeWidth)
        defaults.synchronize()
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

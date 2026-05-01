import Foundation
import Combine

// MARK: - App Services (singletons to simplify wiring)

final class AppServices {
    static let shared = AppServices()
    
    let prefs: Preferences
    let hotkeys: HotkeyManager
    let shots: ScreenshotManager
    
    private var cs = Set<AnyCancellable>()
    
    private init() {
        let prefs = Preferences()
        self.prefs = prefs
        self.hotkeys = HotkeyManager()
        self.shots = ScreenshotManager(prefs: prefs)

        // Rebind hotkeys whenever prefs change.
        prefs.$selectionHotkey.merge(with: prefs.$windowHotkey, prefs.$screenHotkey)
            .dropFirst(3)
            .removeDuplicates()
            .debounce(for: .milliseconds(50), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.rebindHotkeys() }
            .store(in: &cs)
        
        // Initial setup
        shots.refreshSaveDirectory()
        rebindHotkeys()
    }
    
    func rebindHotkeys() {
        hotkeys.unregisterAll()
        if let hk = prefs.selectionHotkey { hotkeys.register(id: .selection, hotkey: hk) { [weak self] in self?.shots.captureSelection() } }
        if let hk = prefs.windowHotkey    { hotkeys.register(id: .window,    hotkey: hk) { [weak self] in
            self?.shots.storePreviousActiveApp()
            self?.shots.captureActiveWindow()
        } }
        if let hk = prefs.screenHotkey    { hotkeys.register(id: .screen,    hotkey: hk) { [weak self] in self?.shots.captureFullScreens() } }
    }
}

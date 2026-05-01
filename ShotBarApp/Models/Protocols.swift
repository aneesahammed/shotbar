import Foundation
import Combine

// MARK: - Common Protocols

/// Protocol for objects that can be saved to UserDefaults
protocol UserDefaultsSavable {
    func save()
}

/// Protocol for services that need to be initialized
protocol ServiceProtocol {
    func initialize()
    func cleanup()
}

/// Protocol for hotkey registration
protocol HotkeyRegistrable {
    func register(id: HotkeyID, hotkey: Hotkey, callback: @escaping () -> Void)
    func unregisterAll()
}

/// Protocol for screenshot capture operations
protocol ScreenshotCapturable {
    func captureSelection(bypassPreview: Bool)
    func captureActiveWindow(bypassPreview: Bool)
    func captureFullScreens(bypassPreview: Bool)
}

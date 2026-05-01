import Foundation
import Combine
import AppKit

// MARK: - App Services (singletons to simplify wiring)

@MainActor
final class AppServices {
    static let shared = AppServices()
    
    let prefs: Preferences
    let hotkeys: HotkeyManager
    let persistence: ImagePersistenceService
    let captureStore: CaptureStore
    let dragExporter: DragExportService
    let editor: EditorCoordinator
    let preview: PreviewCoordinator
    let shots: ScreenshotManager
    
    private var cs = Set<AnyCancellable>()
    
    private init() {
        let prefs = Preferences()
        self.prefs = prefs
        self.hotkeys = HotkeyManager()
        self.persistence = ImagePersistenceService(prefs: prefs)
        self.captureStore = CaptureStore()
        self.dragExporter = DragExportService()
        self.editor = EditorCoordinator(prefs: prefs, persistence: persistence, store: captureStore)
        self.preview = PreviewCoordinator(
            prefs: prefs,
            store: captureStore,
            persistence: persistence,
            editor: editor,
            dragExporter: dragExporter
        )
        self.shots = ScreenshotManager(
            prefs: prefs,
            persistence: persistence,
            captureStore: captureStore,
            previewCoordinator: preview
        )

        // Rebind hotkeys whenever prefs change.
        prefs.$selectionHotkey.merge(with: prefs.$windowHotkey, prefs.$screenHotkey)
            .dropFirst(3)
            .removeDuplicates()
            .debounce(for: .milliseconds(50), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.rebindHotkeys() }
            .store(in: &cs)
        
        // Initial setup
        dragExporter.cleanupOldDragFilesAsync()
        shots.refreshSaveDirectory()
        rebindHotkeys()
    }
    
    func rebindHotkeys() {
        hotkeys.unregisterAll()
        if let hk = prefs.selectionHotkey { hotkeys.register(id: .selection, hotkey: hk) { [weak self] in
            let bypassPreview = NSEvent.modifierFlags.contains(.option)
            self?.shots.captureSelection(bypassPreview: bypassPreview)
        } }
        if let hk = prefs.windowHotkey    { hotkeys.register(id: .window,    hotkey: hk) { [weak self] in
            let bypassPreview = NSEvent.modifierFlags.contains(.option)
            self?.shots.storePreviousActiveApp()
            self?.shots.captureActiveWindow(bypassPreview: bypassPreview)
        } }
        if let hk = prefs.screenHotkey    { hotkeys.register(id: .screen,    hotkey: hk) { [weak self] in
            let bypassPreview = NSEvent.modifierFlags.contains(.option)
            self?.shots.captureFullScreens(bypassPreview: bypassPreview)
        } }
    }
}

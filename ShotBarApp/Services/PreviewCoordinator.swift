import AppKit
import Combine

@MainActor
final class PreviewCoordinator: ObservableObject {
    @Published private(set) var activeBatch: CaptureBatch?

    private let prefs: Preferences
    private let store: CaptureStore
    private let persistence: ImagePersistenceService
    private let editor: EditorCoordinator
    private let dragExporter: DragExporting
    private var panel: FloatingPreviewPanel?
    private var cancellables = Set<AnyCancellable>()

    init(
        prefs: Preferences,
        store: CaptureStore,
        persistence: ImagePersistenceService,
        editor: EditorCoordinator,
        dragExporter: DragExporting
    ) {
        self.prefs = prefs
        self.store = store
        self.persistence = persistence
        self.editor = editor
        self.dragExporter = dragExporter

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in self?.repositionPanel() }
            .store(in: &cancellables)
    }

    func present(_ batch: CaptureBatch) {
        activeBatch = batch

        // The placeholder size is overridden once `setContent` measures the SwiftUI
        // hosting view's `fittingSize` and resizes the panel to fit. Positioning then
        // uses the post-measure size so corner placement is always accurate, regardless
        // of asset count, label length, or accessibility text scaling.
        let placeholder = NSSize(width: 380, height: 240)
        let panel = self.panel ?? FloatingPreviewPanel(size: placeholder)
        self.panel = panel
        panel.setContent(FloatingPreviewView(coordinator: self))

        let frame = frameForPanel(size: panel.frame.size, batch: batch)
        panel.show(at: frame, duration: prefs.previewDuration) { [weak self] in
            self?.activeBatch = nil
            self?.panel = nil
        }
    }

    func showLatest() {
        guard let latest = store.latestBatch else { return }
        present(latest)
    }

    func copy(_ asset: CaptureAsset) {
        Task {
            _ = await persistence.copy(asset)
        }
    }

    func save(_ asset: CaptureAsset) {
        guard var batch = activeBatch,
              let index = batch.assets.firstIndex(where: { $0.id == asset.id }),
              batch.assets[index].originalSavedURL == nil else { return }

        Task {
            var updated = batch.assets[index]
            let result = await persistence.save(
                updated,
                options: SaveOptions(
                    baseName: updated.baseName,
                    suffix: "",
                    format: prefs.imageFormat,
                    showToast: true,
                    playSound: false
                )
            )
            updated.initialResult = result
            if let url = result.savedURL {
                updated.originalSavedURL = url
            }
            batch.assets[index] = updated
            activeBatch = batch
            store.update(batch)
        }
    }

    func saveAll() {
        guard var batch = activeBatch else { return }
        Task {
            for index in batch.assets.indices {
                guard batch.assets[index].originalSavedURL == nil else { continue }
                var asset = batch.assets[index]
                let result = await persistence.save(
                    asset,
                    options: SaveOptions(
                        baseName: asset.baseName,
                        suffix: "",
                        format: prefs.imageFormat,
                        showToast: false,
                        playSound: false
                    )
                )
                asset.initialResult = result
                if let url = result.savedURL {
                    asset.originalSavedURL = url
                }
                batch.assets[index] = asset
            }
            activeBatch = batch
            store.update(batch)
            persistence.show(text: "Saved \(batch.assets.count) screenshots", kind: .success)
        }
    }

    func reveal(_ asset: CaptureAsset) {
        guard let url = asset.originalSavedURL else { return }
        persistence.reveal(url)
    }

    func edit(_ asset: CaptureAsset) {
        editor.open(asset)
    }

    func dragItemProvider(for asset: CaptureAsset) -> NSItemProvider {
        dragExporter.itemProvider(for: asset, format: prefs.imageFormat) { [weak self] error in
            self?.persistence.show(text: "Drag export failed: \(error.localizedDescription)", kind: .error)
        }
    }

    func discard() {
        guard let batch = activeBatch else {
            panel?.closePreview()
            return
        }
        store.discard(batchID: batch.id)
        panel?.closePreview()
    }

    private func repositionPanel() {
        guard let panel, let batch = activeBatch else { return }
        panel.setFrame(frameForPanel(size: panel.frame.size, batch: batch), display: true, animate: false)
    }

    private func frameForPanel(size: NSSize, batch: CaptureBatch) -> NSRect {
        PreviewPlacement.placement(
            panelSize: size,
            corner: prefs.previewCorner,
            screenChoice: prefs.previewScreenChoice,
            cursor: NSEvent.mouseLocation,
            screens: NSScreen.screens,
            originScreenID: batch.assets.first?.originScreenID
        )
    }
}

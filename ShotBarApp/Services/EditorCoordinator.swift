import AppKit

@MainActor
final class EditorCoordinator {
    private let prefs: Preferences
    private let persistence: ImagePersistenceService
    private let store: CaptureStore
    private var windows: [UUID: AnnotationEditorWindowController] = [:]

    init(prefs: Preferences, persistence: ImagePersistenceService, store: CaptureStore) {
        self.prefs = prefs
        self.persistence = persistence
        self.store = store
    }

    func open(_ asset: CaptureAsset) {
        if let existing = windows[asset.id] {
            existing.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        do {
            let baseImage = try ImageCodec.loadImage(from: asset.cacheURL)
            store.retainForEditing(asset)
            let model = AnnotationDocumentModel(asset: asset, baseImage: baseImage, prefs: prefs)
            let controller = AnnotationEditorWindowController(
                model: model,
                onSave: { [weak self] model in await self?.save(model) },
                onCopy: { [weak self] model in await self?.copy(model) },
                onClose: { [weak self] assetID in
                    guard let self else { return }
                    self.windows.removeValue(forKey: assetID)
                    self.store.releaseFromEditing(asset)
                }
            )
            windows[asset.id] = controller
            controller.showWindow(nil)
            NSApp.activate(ignoringOtherApps: true)
        } catch {
            persistence.show(text: "Could not open editor: \(error.localizedDescription)", kind: .error)
        }
    }

    func save(_ model: AnnotationDocumentModel) async {
        model.isRendering = true
        defer { model.isRendering = false }
        do {
            let image = try await AnnotationRenderer.render(document: model.document, baseImageURL: model.asset.cacheURL)
            let result = await persistence.saveRenderedImage(
                image,
                metadata: RenderedImageMetadata(pixelsPerPoint: model.asset.pixelsPerPoint),
                options: SaveOptions(
                    baseName: model.asset.baseName,
                    suffix: "(annotated)",
                    format: prefs.imageFormat,
                    showToast: true,
                    playSound: false
                )
            )
            if case .saved = result {
                model.isDirty = false
                model.lastMessage = "Saved annotated screenshot"
            }
        } catch {
            persistence.show(text: "Annotation save failed: \(error.localizedDescription)", kind: .error)
        }
    }

    func copy(_ model: AnnotationDocumentModel) async {
        model.isRendering = true
        defer { model.isRendering = false }
        do {
            let image = try await AnnotationRenderer.render(document: model.document, baseImageURL: model.asset.cacheURL)
            _ = await persistence.copyRenderedImage(
                image,
                metadata: RenderedImageMetadata(pixelsPerPoint: model.asset.pixelsPerPoint),
                showToast: true
            )
        } catch {
            persistence.show(text: "Annotation copy failed: \(error.localizedDescription)", kind: .error)
        }
    }
}

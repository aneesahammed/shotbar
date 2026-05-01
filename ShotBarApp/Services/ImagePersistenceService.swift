import AppKit
import Foundation

protocol ImagePersisting {
    func copy(_ asset: CaptureAsset) async -> PersistenceResult
    func save(_ asset: CaptureAsset, options: SaveOptions) async -> PersistenceResult
    func saveRenderedImage(_ image: CGImage, metadata: RenderedImageMetadata, options: SaveOptions) async -> PersistenceResult
    @MainActor func reveal(_ url: URL)
}

final class ImagePersistenceService: ImagePersisting {
    private let toast = Toast()
    private let prefs: Preferences
    private let fileManager: FileManager
    private let saveDirectoryOverride: URL?
    private let pasteboard: NSPasteboard

    init(
        prefs: Preferences,
        fileManager: FileManager = .default,
        saveDirectory: URL? = nil,
        pasteboard: NSPasteboard = .general
    ) {
        self.prefs = prefs
        self.fileManager = fileManager
        self.saveDirectoryOverride = saveDirectory
        self.pasteboard = pasteboard
    }

    var defaultSaveDirectory: URL {
        if let saveDirectoryOverride {
            try? fileManager.createDirectory(at: saveDirectoryOverride, withIntermediateDirectories: true, attributes: nil)
            return saveDirectoryOverride
        }
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        try? fileManager.createDirectory(at: documentsURL, withIntermediateDirectories: true, attributes: nil)
        return documentsURL
    }

    func copy(_ asset: CaptureAsset) async -> PersistenceResult {
        do {
            let image = try ImageCodec.loadImage(from: asset.cacheURL)
            return await copyRenderedImage(
                image,
                metadata: RenderedImageMetadata(pixelsPerPoint: asset.pixelsPerPoint),
                showToast: true
            )
        } catch {
            return await presentIfNeeded(.failed(userFacingSaveError(for: error)), showToast: true, playSound: false)
        }
    }

    func copyRenderedImage(_ image: CGImage, metadata: RenderedImageMetadata, showToast: Bool = true) async -> PersistenceResult {
        let dpi = 72.0 * Double(max(metadata.pixelsPerPoint, 1.0))
        guard let pngData = ImageCodec.pngData(from: image, dpi: dpi) else {
            return await presentIfNeeded(.failed("Could not encode screenshot for clipboard"), showToast: showToast, playSound: false)
        }

        let result = await MainActor.run {
            pasteboard.clearContents()
            guard pasteboard.setData(pngData, forType: .png) else {
                return PersistenceResult.failed("Could not copy screenshot to clipboard")
            }
            return .copied
        }
        return await presentIfNeeded(result, showToast: showToast, playSound: false)
    }

    func save(_ asset: CaptureAsset, options: SaveOptions) async -> PersistenceResult {
        do {
            let image = try ImageCodec.loadImage(from: asset.cacheURL)
            return await saveRenderedImage(
                image,
                metadata: RenderedImageMetadata(pixelsPerPoint: asset.pixelsPerPoint),
                options: options
            )
        } catch {
            return await presentIfNeeded(.failed(userFacingSaveError(for: error)), showToast: options.showToast, playSound: options.playSound)
        }
    }

    func saveRenderedImage(_ image: CGImage, metadata: RenderedImageMetadata, options: SaveOptions) async -> PersistenceResult {
        let result: PersistenceResult
        do {
            let url = try saveImageFile(image, metadata: metadata, options: options)
            result = .saved(url)
        } catch {
            result = .failed(userFacingSaveError(for: error))
        }
        return await presentIfNeeded(result, showToast: options.showToast, playSound: options.playSound)
    }

    @MainActor
    func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    @MainActor
    func revealSaveDirectory() {
        NSWorkspace.shared.activateFileViewerSelecting([defaultSaveDirectory])
    }

    @MainActor
    func show(text: String, kind: Toast.Kind = .info, duration: TimeInterval? = nil) {
        toast.show(text: text, kind: kind, duration: duration)
    }

    func nextAvailableURL(in directory: URL, baseName: String, extension ext: String) -> URL {
        FileNaming.nextAvailableURL(in: directory, baseName: baseName, extension: ext, fileManager: fileManager)
    }

    private func saveImageFile(_ image: CGImage, metadata: RenderedImageMetadata, options: SaveOptions) throws -> URL {
        let ext = options.format.fileExtension
        let directory = defaultSaveDirectory
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
        let baseName = options.suffix.isEmpty ? options.baseName : "\(options.baseName) \(options.suffix)"
        let url = nextAvailableURL(in: directory, baseName: baseName, extension: ext)
        let dpi = 72.0 * Double(max(metadata.pixelsPerPoint, 1.0))

        switch options.format {
        case .png:
            try ImageCodec.writePNG(image, to: url, dpi: dpi)
        case .jpg:
            try ImageCodec.writeJPG(image, to: url, quality: 1.0, dpi: dpi)
        }
        return url
    }

    @MainActor
    private func presentIfNeeded(_ result: PersistenceResult, showToast: Bool, playSound: Bool) -> PersistenceResult {
        guard showToast else {
            if playSound { playShutterSoundIfEnabled() }
            return result
        }

        switch result {
        case .copied:
            toast.show(text: "Screenshot copied to clipboard", kind: .success)
        case .saved(let url):
            toast.show(text: "Saved \(url.lastPathComponent)", kind: .success)
        case .failed(let message):
            toast.show(text: message, kind: .error)
        }
        if playSound { playShutterSoundIfEnabled() }
        return result
    }

    private func userFacingSaveError(for error: Error) -> String {
        let nsError = error as NSError
        if nsError.domain == "ShotBar" {
            return nsError.localizedDescription
        }
        return "Save failed. Check the save folder permissions."
    }

    private func playShutterSoundIfEnabled() {
        guard prefs.soundEnabled else { return }
        NSSound(named: NSSound.Name("Tink"))?.play()
    }
}

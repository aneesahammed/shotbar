import AppKit
import CoreGraphics
import UniformTypeIdentifiers
import XCTest
@testable import ShotBarApp

@MainActor
final class PreviewCoordinatorDragTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        root = nil
    }

    func testDragItemProviderUsesCurrentPreferredFormat() throws {
        let suiteName = "ShotBarAppTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let prefs = Preferences(defaults: defaults)
        prefs.imageFormat = .jpg
        let store = CaptureStore(fileManager: .default, cacheRoot: root.appendingPathComponent("Captures", isDirectory: true))
        let persistence = ImagePersistenceService(
            prefs: prefs,
            saveDirectory: root.appendingPathComponent("Saved", isDirectory: true),
            pasteboard: NSPasteboard(name: NSPasteboard.Name("ShotBarAppTests.\(UUID().uuidString)"))
        )
        let editor = EditorCoordinator(prefs: prefs, persistence: persistence, store: store)
        let dragExporter = RecordingDragExporter()
        let coordinator = PreviewCoordinator(
            prefs: prefs,
            store: store,
            persistence: persistence,
            editor: editor,
            dragExporter: dragExporter
        )
        let asset = try makeAsset(baseName: "Screenshot Preview Drag Selection")

        let provider = coordinator.dragItemProvider(for: asset)

        XCTAssertEqual(dragExporter.requestedAssetID, asset.id)
        XCTAssertEqual(dragExporter.requestedFormat, .jpg)
        XCTAssertEqual(provider.suggestedName, "recorded.jpg")
        XCTAssertTrue(provider.hasItemConformingToTypeIdentifier(UTType.jpeg.identifier))
    }

    private func makeAsset(baseName: String) throws -> CaptureAsset {
        let image = makeImage(width: 16, height: 12)
        let sourceURL = root.appendingPathComponent(UUID().uuidString).appendingPathExtension("png")
        try ImageCodec.writePNG(image, to: sourceURL, dpi: 144)
        return CaptureAsset(
            id: UUID(),
            cacheURL: sourceURL,
            thumbnail: image,
            kind: .selection,
            createdAt: Date(),
            baseName: baseName,
            pixelsPerPoint: 2,
            originScreenID: nil,
            pixelSize: CGSize(width: image.width, height: image.height),
            originalSavedURL: nil,
            initialResult: nil
        )
    }

    private func makeImage(width: Int, height: Int) -> CGImage {
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(red: 0.8, green: 0.3, blue: 0.2, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }
}

private final class RecordingDragExporter: DragExporting {
    private(set) var requestedAssetID: UUID?
    private(set) var requestedFormat: ImageFormat?

    func itemProvider(
        for asset: CaptureAsset,
        format: ImageFormat,
        onFailure: @escaping @MainActor (Error) -> Void
    ) -> NSItemProvider {
        requestedAssetID = asset.id
        requestedFormat = format

        let provider = NSItemProvider()
        provider.suggestedName = format == .jpg ? "recorded.jpg" : "recorded.png"
        provider.registerDataRepresentation(forTypeIdentifier: format.utType.identifier, visibility: .all) { completion in
            completion(Data([1, 2, 3]), nil)
            return nil
        }
        return provider
    }

    func exportFile(for asset: CaptureAsset, format: ImageFormat) throws -> URL {
        throw NSError(domain: "ShotBarTests", code: 1)
    }

    func cleanupOldDragFiles(olderThan retention: TimeInterval) {}
    func cleanupOldDragFilesAsync(olderThan retention: TimeInterval) {}
}

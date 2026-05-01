import AppKit
import CoreGraphics
import XCTest
@testable import ShotBarApp

final class ImagePersistenceServiceTests: XCTestCase {
    func testNextAvailableURLAddsCounterAfterAnnotatedCollision() throws {
        let suiteName = "ShotBarAppTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let service = ImagePersistenceService(prefs: Preferences(defaults: defaults))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let first = directory.appendingPathComponent("Screenshot Test (annotated)").appendingPathExtension("png")
        FileManager.default.createFile(atPath: first.path, contents: Data())

        let available = service.nextAvailableURL(in: directory, baseName: "Screenshot Test (annotated)", extension: "png")
        XCTAssertEqual(available.lastPathComponent, "Screenshot Test (annotated) (2).png")
    }

    func testSaveUsesInjectedDirectoryAndWritesConfiguredJPG() async throws {
        let suiteName = "ShotBarAppTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let service = ImagePersistenceService(
            prefs: Preferences(defaults: defaults),
            saveDirectory: directory,
            pasteboard: NSPasteboard(name: NSPasteboard.Name("ShotBarAppTests.\(UUID().uuidString)"))
        )
        let image = makeImage(width: 20, height: 14)

        let result = await service.saveRenderedImage(
            image,
            metadata: RenderedImageMetadata(pixelsPerPoint: 2),
            options: SaveOptions(
                baseName: "Screenshot/Test:Name",
                suffix: "",
                format: .jpg,
                showToast: false,
                playSound: false
            )
        )

        guard case .saved(let url) = result else {
            XCTFail("Expected save to succeed, got \(result)")
            return
        }
        XCTAssertEqual(url.deletingLastPathComponent(), directory)
        XCTAssertEqual(url.lastPathComponent, "Screenshot-Test-Name.jpg")
        let data = try Data(contentsOf: url)
        XCTAssertEqual(Array(data.prefix(2)), [0xFF, 0xD8])
        XCTAssertNoThrow(try ImageCodec.loadImage(from: url))
    }

    func testSaveAssetLoadsCacheAndWritesConfiguredPNG() async throws {
        let suiteName = "ShotBarAppTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let saveDirectory = root.appendingPathComponent("Saved", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let image = makeImage(width: 18, height: 12)
        let cacheURL = root.appendingPathComponent("source.png")
        try ImageCodec.writePNG(image, to: cacheURL, dpi: 144)
        let service = ImagePersistenceService(
            prefs: Preferences(defaults: defaults),
            saveDirectory: saveDirectory,
            pasteboard: NSPasteboard(name: NSPasteboard.Name("ShotBarAppTests.\(UUID().uuidString)"))
        )

        let result = await service.save(
            makeAsset(cacheURL: cacheURL, thumbnail: image, baseName: "Screenshot Asset Selection"),
            options: SaveOptions(
                baseName: "Screenshot Asset Selection",
                suffix: "",
                format: .png,
                showToast: false,
                playSound: false
            )
        )

        guard case .saved(let url) = result else {
            XCTFail("Expected asset save to succeed, got \(result)")
            return
        }
        XCTAssertEqual(url.lastPathComponent, "Screenshot Asset Selection.png")
        let data = try Data(contentsOf: url)
        XCTAssertEqual(Array(data.prefix(8)), [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    }

    func testCopyRenderedImageWritesPNGToInjectedPasteboard() async throws {
        let suiteName = "ShotBarAppTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let pasteboard = NSPasteboard(name: NSPasteboard.Name("ShotBarAppTests.\(UUID().uuidString)"))
        let service = ImagePersistenceService(
            prefs: Preferences(defaults: defaults),
            pasteboard: pasteboard
        )

        let result = await service.copyRenderedImage(
            makeImage(width: 12, height: 10),
            metadata: RenderedImageMetadata(pixelsPerPoint: 2),
            showToast: false
        )

        XCTAssertEqual(result, .copied)
        let data = try XCTUnwrap(pasteboard.data(forType: .png))
        XCTAssertEqual(Array(data.prefix(8)), [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    }

    private func makeAsset(cacheURL: URL, thumbnail: CGImage, baseName: String) -> CaptureAsset {
        CaptureAsset(
            id: UUID(),
            cacheURL: cacheURL,
            thumbnail: thumbnail,
            kind: .selection,
            createdAt: Date(),
            baseName: baseName,
            pixelsPerPoint: 2,
            originScreenID: nil,
            pixelSize: CGSize(width: thumbnail.width, height: thumbnail.height),
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
        context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.9, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }
}

import AppKit
import CoreGraphics
import UniformTypeIdentifiers
import XCTest
@testable import ShotBarApp

final class DragExportServiceTests: XCTestCase {
    private var root: URL!
    private var exportRoot: URL!

    override func setUpWithError() throws {
        let caches = try FileManager.default.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        root = caches.appendingPathComponent("DragExportServiceTests-\(UUID().uuidString)", isDirectory: true)
        exportRoot = root.appendingPathComponent("DragExports", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        root = nil
        exportRoot = nil
    }

    func testFastPathCreatesNamedExportInsteadOfReturningCacheURL() throws {
        let asset = try makeAsset(baseName: "Screenshot 2026-05-01 at 14.23.05 Selection")
        let service = DragExportService(exportRoot: exportRoot)

        let url = try service.exportFile(for: asset, format: .png)

        XCTAssertNotEqual(url, asset.cacheURL)
        XCTAssertEqual(url.lastPathComponent, "Screenshot 2026-05-01 at 14.23.05 Selection.png")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))

        try FileManager.default.removeItem(at: asset.cacheURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "Drag export must survive capture cache cleanup")
    }

    func testReencodePathWritesValidJPG() throws {
        let asset = try makeAsset(baseName: "Screenshot 2026-05-01 at 14.23.05 Window")
        let service = DragExportService(exportRoot: exportRoot)

        let url = try service.exportFile(for: asset, format: .jpg)

        XCTAssertEqual(url.lastPathComponent, "Screenshot 2026-05-01 at 14.23.05 Window.jpg")
        let data = try Data(contentsOf: url)
        XCTAssertEqual(Array(data.prefix(2)), [0xFF, 0xD8])
        XCTAssertNoThrow(try ImageCodec.loadImage(from: url))
    }

    func testExportFilenameCollisionsUseNumberedSuffixes() throws {
        let asset = try makeAsset(baseName: "Screenshot Same Second Selection")
        let service = DragExportService(exportRoot: exportRoot)

        let first = try service.exportFile(for: asset, format: .png)
        let second = try service.exportFile(for: asset, format: .png)

        XCTAssertEqual(first.lastPathComponent, "Screenshot Same Second Selection.png")
        XCTAssertEqual(second.lastPathComponent, "Screenshot Same Second Selection (2).png")
    }

    func testCleanupRemovesOldExportsAndStagingFilesOnly() throws {
        let service = DragExportService(exportRoot: exportRoot)
        let staging = exportRoot.appendingPathComponent(AppConstants.CacheDirectories.dragStaging, isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)

        let oldExport = exportRoot.appendingPathComponent("old.png")
        let newExport = exportRoot.appendingPathComponent("new.png")
        let oldStaged = staging.appendingPathComponent("old-stage.png")
        _ = FileManager.default.createFile(atPath: oldExport.path, contents: Data([1]))
        _ = FileManager.default.createFile(atPath: newExport.path, contents: Data([1]))
        _ = FileManager.default.createFile(atPath: oldStaged.path, contents: Data([1]))

        let oldDate = Date().addingTimeInterval(-7200)
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: oldExport.path)
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: oldStaged.path)

        service.cleanupOldDragFiles(olderThan: 3600)

        XCTAssertFalse(FileManager.default.fileExists(atPath: oldExport.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldStaged.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: newExport.path))
    }

    func testItemProviderLoadsAsyncFileRepresentationWithSuggestedName() throws {
        let asset = try makeAsset(baseName: "Screenshot Provider Selection")
        let service = DragExportService(exportRoot: exportRoot)
        let expectation = expectation(description: "load file representation")

        let provider = service.itemProvider(for: asset, format: .jpg) { error in
            XCTFail("Unexpected drag export failure: \(error.localizedDescription)")
        }

        XCTAssertEqual(provider.suggestedName, "Screenshot Provider Selection.jpg")
        XCTAssertTrue(provider.hasItemConformingToTypeIdentifier(UTType.jpeg.identifier))
        XCTAssertTrue(provider.hasItemConformingToTypeIdentifier(UTType.tiff.identifier))
        XCTAssertTrue(provider.hasItemConformingToTypeIdentifier(UTType.image.identifier))
        XCTAssertTrue(provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier))

        provider.loadFileRepresentation(forTypeIdentifier: UTType.jpeg.identifier) { url, error in
            defer { expectation.fulfill() }
            if let error {
                XCTFail("Expected provider to load file representation, got \(error)")
                return
            }
            guard let url else {
                XCTFail("Expected provider to return a file URL")
                return
            }
            do {
                _ = try ImageCodec.loadImage(from: url)
            } catch {
                XCTFail("Expected provider URL to contain a valid image, got \(error)")
            }
        }

        wait(for: [expectation], timeout: 5)
    }

    func testItemProviderLoadsImageDataRepresentationsForRichEditors() throws {
        let asset = try makeAsset(baseName: "Screenshot Rich Editor Selection")
        let service = DragExportService(exportRoot: exportRoot)
        let provider = service.itemProvider(for: asset, format: .jpg) { error in
            XCTFail("Unexpected drag export failure: \(error.localizedDescription)")
        }

        let jpegExpectation = expectation(description: "load jpeg data representation")
        provider.loadDataRepresentation(forTypeIdentifier: UTType.jpeg.identifier) { data, error in
            defer { jpegExpectation.fulfill() }
            if let error {
                XCTFail("Expected provider to load JPEG data, got \(error)")
                return
            }
            guard let data else {
                XCTFail("Expected provider to return JPEG data")
                return
            }
            XCTAssertEqual(Array(data.prefix(2)), [0xFF, 0xD8])
        }

        let tiffExpectation = expectation(description: "load tiff data representation")
        provider.loadDataRepresentation(forTypeIdentifier: UTType.tiff.identifier) { data, error in
            defer { tiffExpectation.fulfill() }
            if let error {
                XCTFail("Expected provider to load TIFF data, got \(error)")
                return
            }
            guard let data else {
                XCTFail("Expected provider to return TIFF data")
                return
            }
            XCTAssertNotNil(NSImage(data: data))
        }

        wait(for: [jpegExpectation, tiffExpectation], timeout: 5)
    }

    func testItemProviderLoadsPNGDataRepresentationForRichEditors() throws {
        let asset = try makeAsset(baseName: "Screenshot PNG Rich Editor Selection")
        let service = DragExportService(exportRoot: exportRoot)
        let provider = service.itemProvider(for: asset, format: .png) { error in
            XCTFail("Unexpected drag export failure: \(error.localizedDescription)")
        }
        let expectation = expectation(description: "load png data representation")

        provider.loadDataRepresentation(forTypeIdentifier: UTType.png.identifier) { data, error in
            defer { expectation.fulfill() }
            if let error {
                XCTFail("Expected provider to load PNG data, got \(error)")
                return
            }
            guard let data else {
                XCTFail("Expected provider to return PNG data")
                return
            }
            XCTAssertEqual(Array(data.prefix(8)), [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        }

        wait(for: [expectation], timeout: 5)
    }

    func testItemProviderLoadsFileURLRepresentationForURLOnlyConsumers() throws {
        let asset = try makeAsset(baseName: "Screenshot URL Consumer Selection")
        let service = DragExportService(exportRoot: exportRoot)
        let provider = service.itemProvider(for: asset, format: .png) { error in
            XCTFail("Unexpected drag export failure: \(error.localizedDescription)")
        }
        let expectation = expectation(description: "load file URL data representation")

        provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, error in
            defer { expectation.fulfill() }
            if let error {
                XCTFail("Expected provider to load file URL data, got \(error)")
                return
            }
            guard let data,
                  let url = URL(dataRepresentation: data, relativeTo: nil, isAbsolute: true) else {
                XCTFail("Expected provider to return a file URL data representation")
                return
            }

            XCTAssertEqual(url.lastPathComponent, "Screenshot URL Consumer Selection.png")
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        }

        wait(for: [expectation], timeout: 5)
    }

    func testProviderFallsBackToAsyncCopyWhenFastPathHardLinkingFails() throws {
        let asset = try makeAsset(baseName: "Screenshot Copy Fallback Selection")
        let service = DragExportService(
            exportRoot: exportRoot,
            linkFile: { _, _ in throw NSError(domain: "ShotBarTests", code: 1) }
        )
        let provider = service.itemProvider(for: asset, format: .png) { error in
            XCTFail("Unexpected drag export failure: \(error.localizedDescription)")
        }
        let expectation = expectation(description: "load copied fast-path export")

        provider.loadFileRepresentation(forTypeIdentifier: UTType.png.identifier) { url, error in
            defer { expectation.fulfill() }
            if let error {
                XCTFail("Expected provider to fall back to async copy, got \(error)")
                return
            }
            guard let url else {
                XCTFail("Expected provider to return a copied file URL")
                return
            }
            XCTAssertEqual(url.lastPathComponent, "Screenshot Copy Fallback Selection.png")
            do {
                _ = try ImageCodec.loadImage(from: url)
            } catch {
                XCTFail("Expected provider URL to contain a valid image, got \(error)")
            }
        }

        wait(for: [expectation], timeout: 5)
    }

    func testProviderFallsBackToAsyncCopyBeforeReencodeWhenStagingHardLinkFails() throws {
        let asset = try makeAsset(baseName: "Screenshot Reencode Copy Fallback Selection")
        let service = DragExportService(
            exportRoot: exportRoot,
            linkFile: { _, _ in throw NSError(domain: "ShotBarTests", code: 1) }
        )
        let provider = service.itemProvider(for: asset, format: .jpg) { error in
            XCTFail("Unexpected drag export failure: \(error.localizedDescription)")
        }
        let expectation = expectation(description: "load re-encoded export after copy fallback")

        provider.loadFileRepresentation(forTypeIdentifier: UTType.jpeg.identifier) { url, error in
            defer { expectation.fulfill() }
            if let error {
                XCTFail("Expected provider to copy before re-encode, got \(error)")
                return
            }
            guard let url else {
                XCTFail("Expected provider to return a re-encoded file URL")
                return
            }
            XCTAssertEqual(url.lastPathComponent, "Screenshot Reencode Copy Fallback Selection.jpg")
            do {
                let data = try Data(contentsOf: url)
                XCTAssertEqual(Array(data.prefix(2)), [0xFF, 0xD8])
                _ = try ImageCodec.loadImage(from: url)
            } catch {
                XCTFail("Expected provider URL to contain a valid JPG, got \(error)")
            }
        }

        wait(for: [expectation], timeout: 5)
    }

    func testPendingReencodeProvidersReserveDistinctNamesBeforeEitherLoads() throws {
        let firstAsset = try makeAsset(baseName: "Screenshot Same Second Selection", color: CGColor(red: 0.9, green: 0.1, blue: 0.1, alpha: 1))
        let secondAsset = try makeAsset(baseName: "Screenshot Same Second Selection", color: CGColor(red: 0.1, green: 0.8, blue: 0.2, alpha: 1))
        let service = DragExportService(exportRoot: exportRoot)
        let firstProvider = service.itemProvider(for: firstAsset, format: .jpg) { error in
            XCTFail("Unexpected first drag export failure: \(error.localizedDescription)")
        }
        let secondProvider = service.itemProvider(for: secondAsset, format: .jpg) { error in
            XCTFail("Unexpected second drag export failure: \(error.localizedDescription)")
        }

        XCTAssertEqual(firstProvider.suggestedName, "Screenshot Same Second Selection.jpg")
        XCTAssertEqual(secondProvider.suggestedName, "Screenshot Same Second Selection (2).jpg")

        let expectation = expectation(description: "load both re-encoded providers")
        expectation.expectedFulfillmentCount = 2
        var loadedNames: [String] = []
        let lock = NSLock()

        for provider in [firstProvider, secondProvider] {
            provider.loadFileRepresentation(forTypeIdentifier: UTType.jpeg.identifier) { url, error in
                defer { expectation.fulfill() }
                if let error {
                    XCTFail("Expected provider to load file representation, got \(error)")
                    return
                }
                guard let url else {
                    XCTFail("Expected provider to return a file URL")
                    return
                }
                lock.lock()
                loadedNames.append(url.lastPathComponent)
                lock.unlock()
            }
        }

        wait(for: [expectation], timeout: 5)
        XCTAssertEqual(Set(loadedNames), [
            "Screenshot Same Second Selection.jpg",
            "Screenshot Same Second Selection (2).jpg"
        ])
    }

    func testCleanupDoesNotDeleteActiveFastPathExportWithOldSourceModificationDate() throws {
        let asset = try makeAsset(baseName: "Screenshot Old Selection")
        let oldDate = Date().addingTimeInterval(-7200)
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: asset.cacheURL.path)
        let service = DragExportService(exportRoot: exportRoot)
        let provider = service.itemProvider(for: asset, format: .png) { error in
            XCTFail("Unexpected drag export failure: \(error.localizedDescription)")
        }

        service.cleanupOldDragFiles(olderThan: 3600)

        let expectation = expectation(description: "load active old-mtime fast path export")
        provider.loadFileRepresentation(forTypeIdentifier: UTType.png.identifier) { url, error in
            defer { expectation.fulfill() }
            if let error {
                XCTFail("Expected provider to load file representation after cleanup, got \(error)")
                return
            }
            guard let url else {
                XCTFail("Expected provider to return a file URL")
                return
            }
            XCTAssertEqual(url.lastPathComponent, "Screenshot Old Selection.png")
            do {
                _ = try ImageCodec.loadImage(from: url)
            } catch {
                XCTFail("Expected provider URL to contain a valid image, got \(error)")
            }
        }

        wait(for: [expectation], timeout: 5)
    }

    func testCleanupDoesNotDeleteFinishedFastPathExportWithOldSourceModificationDate() throws {
        let asset = try makeAsset(baseName: "Screenshot Finished Old Selection")
        let oldDate = Date().addingTimeInterval(-7200)
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: asset.cacheURL.path)
        let service = DragExportService(exportRoot: exportRoot)

        let url = try service.exportFile(for: asset, format: .png)
        service.cleanupOldDragFiles(olderThan: 3600)

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(url.lastPathComponent, "Screenshot Finished Old Selection.png")
    }

    func testCleanupDoesNotDeleteActiveReencodeStagingFileBeforeProviderLoad() throws {
        let asset = try makeAsset(baseName: "Screenshot Old Reencode Selection")
        let oldDate = Date().addingTimeInterval(-7200)
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: asset.cacheURL.path)
        let service = DragExportService(exportRoot: exportRoot)
        let provider = service.itemProvider(for: asset, format: .jpg) { error in
            XCTFail("Unexpected drag export failure: \(error.localizedDescription)")
        }

        service.cleanupOldDragFiles(olderThan: 3600)

        let expectation = expectation(description: "load active old-mtime reencode export")
        provider.loadFileRepresentation(forTypeIdentifier: UTType.jpeg.identifier) { url, error in
            defer { expectation.fulfill() }
            if let error {
                XCTFail("Expected provider to load file representation after cleanup, got \(error)")
                return
            }
            guard let url else {
                XCTFail("Expected provider to return a file URL")
                return
            }
            XCTAssertEqual(url.lastPathComponent, "Screenshot Old Reencode Selection.jpg")
            do {
                _ = try ImageCodec.loadImage(from: url)
            } catch {
                XCTFail("Expected provider URL to contain a valid image, got \(error)")
            }
        }

        wait(for: [expectation], timeout: 5)
    }

    private func makeAsset(
        baseName: String,
        color: CGColor = CGColor(red: 0.1, green: 0.4, blue: 0.8, alpha: 1)
    ) throws -> CaptureAsset {
        let image = makeImage(width: 16, height: 12, color: color)
        let sourceURL = root
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(AppConstants.FileExtensions.png)
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

    private func makeImage(width: Int, height: Int, color: CGColor) -> CGImage {
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(color)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }
}

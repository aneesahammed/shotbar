import XCTest
@testable import ShotBarApp

final class AnnotationCommandTests: XCTestCase {
    func testUndoRedoAndRedoInvalidation() throws {
        let asset = try makeAsset()
        let image = makeImage()
        let defaults = UserDefaults(suiteName: "ShotBarAppTests.\(UUID().uuidString)")!
        let prefs = Preferences(defaults: defaults)
        let model = AnnotationDocumentModel(asset: asset, baseImage: image, prefs: prefs)

        let style = AnnotationStyle(color: .red, strokeWidth: 4)
        let arrow = AnnotationLayer.arrow(ArrowLayer(start: .zero, end: CGPoint(x: 10, y: 10), style: style, headSize: 20))

        model.apply(.addLayer(arrow))
        XCTAssertEqual(model.document.layers.count, 1)
        XCTAssertTrue(model.canUndo)

        model.undo()
        XCTAssertTrue(model.document.layers.isEmpty)
        XCTAssertTrue(model.canRedo)

        model.redo()
        XCTAssertEqual(model.document.layers.count, 1)

        let crop = CGRect(x: 1, y: 1, width: 8, height: 8)
        model.undo()
        model.apply(.setCrop(before: nil, after: crop))
        XCTAssertFalse(model.canRedo)
        XCTAssertEqual(model.document.crop, crop)
    }

    func testHistoryDepthCap() {
        let history = AnnotationCommandHistory(depth: 2)
        let style = AnnotationStyle(color: .red, strokeWidth: 4)
        let one = AnnotationLayer.arrow(ArrowLayer(start: .zero, end: CGPoint(x: 1, y: 1), style: style, headSize: 10))
        let two = AnnotationLayer.arrow(ArrowLayer(start: .zero, end: CGPoint(x: 2, y: 2), style: style, headSize: 10))
        let three = AnnotationLayer.arrow(ArrowLayer(start: .zero, end: CGPoint(x: 3, y: 3), style: style, headSize: 10))

        history.record(.addLayer(one))
        history.record(.addLayer(two))
        history.record(.addLayer(three))

        XCTAssertEqual(history.undoStack.count, 2)
        XCTAssertEqual(history.undoStack.first, .addLayer(two))
    }

    func testUpdateLayerUndoRedoMovesTextAnnotation() throws {
        let asset = try makeAsset()
        let image = makeImage()
        let defaults = UserDefaults(suiteName: "ShotBarAppTests.\(UUID().uuidString)")!
        let prefs = Preferences(defaults: defaults)
        let model = AnnotationDocumentModel(asset: asset, baseImage: image, prefs: prefs)
        let style = AnnotationStyle(color: .red, strokeWidth: 4)
        let original = TextLayer(
            text: "Move me",
            rect: CGRect(x: 1, y: 1, width: 5, height: 3),
            style: style,
            fontSize: 18
        )
        var moved = original
        moved.rect.origin = CGPoint(x: 4, y: 5)

        model.apply(.addLayer(.text(original)))
        model.apply(.updateLayer(before: .text(original), after: .text(moved)))

        guard case .text(let movedLayer) = model.document.layers.first else {
            return XCTFail("Expected a text layer")
        }
        XCTAssertEqual(movedLayer.rect.origin, CGPoint(x: 4, y: 5))

        model.undo()
        guard case .text(let restoredLayer) = model.document.layers.first else {
            return XCTFail("Expected a text layer")
        }
        XCTAssertEqual(restoredLayer.rect.origin, CGPoint(x: 1, y: 1))

        model.redo()
        guard case .text(let redoneLayer) = model.document.layers.first else {
            return XCTFail("Expected a text layer")
        }
        XCTAssertEqual(redoneLayer.rect.origin, CGPoint(x: 4, y: 5))
    }

    private func makeAsset() throws -> CaptureAsset {
        CaptureAsset(
            id: UUID(),
            cacheURL: URL(fileURLWithPath: "/tmp/test.png"),
            thumbnail: makeImage(),
            kind: .selection,
            createdAt: Date(),
            baseName: "Screenshot Test Selection",
            pixelsPerPoint: 1,
            originScreenID: nil,
            pixelSize: CGSize(width: 10, height: 10),
            originalSavedURL: nil,
            initialResult: nil
        )
    }

    private func makeImage() -> CGImage {
        let context = CGContext(
            data: nil,
            width: 10,
            height: 10,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 10, height: 10))
        return context.makeImage()!
    }
}

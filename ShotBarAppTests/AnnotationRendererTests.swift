import XCTest
@testable import ShotBarApp

final class AnnotationRendererTests: XCTestCase {
    func testRendererAppliesCropLast() throws {
        let base = makeImage(width: 20, height: 20)
        let style = AnnotationStyle(color: .red, strokeWidth: 2)
        let document = AnnotationDocument(
            basePixelSize: CGSize(width: 20, height: 20),
            pixelsPerPoint: 1,
            layers: [
                .arrow(ArrowLayer(start: CGPoint(x: 2, y: 2), end: CGPoint(x: 18, y: 18), style: style, headSize: 6))
            ],
            crop: CGRect(x: 5, y: 5, width: 10, height: 8)
        )

        let rendered = try AnnotationRenderer.render(document: document, baseImage: base)
        XCTAssertEqual(rendered.width, 10)
        XCTAssertEqual(rendered.height, 8)
    }

    /// Arrows shorter than `max(strokeWidth * 2, 8)` are silently no-oped by the geometry
    /// helper. The renderer must produce an image identical to the base (allowing for
    /// color-space round-trip) — no crash, no partial render.
    func testShortArrowProducesNoChangeFromBase() throws {
        let base = makeImage(width: 40, height: 40)
        let style = AnnotationStyle(color: .red, strokeWidth: 8)
        // Length 4pt with stroke 8 → below minimum of 16 → no-op.
        let document = AnnotationDocument(
            basePixelSize: CGSize(width: 40, height: 40),
            pixelsPerPoint: 1,
            layers: [
                .arrow(ArrowLayer(start: CGPoint(x: 20, y: 20), end: CGPoint(x: 24, y: 20), style: style, headSize: 0))
            ]
        )

        let rendered = try AnnotationRenderer.render(document: document, baseImage: base)
        XCTAssertEqual(rendered.width, 40)
        XCTAssertEqual(rendered.height, 40)
        // Sample center pixel — should still be white (the base color), not red.
        let center = samplePixel(in: rendered, x: 20, y: 20)
        XCTAssertGreaterThan(center.red, 0.95, "Short-arrow render should leave base pixels untouched")
        XCTAssertLessThan(center.green + center.blue, 2.5, "Pixel should not have picked up red")
    }

    /// A long arrow must produce visible non-base pixels along its path. Property
    /// assertion (non-zero red ink, non-zero halo darkness) avoids brittle golden images.
    func testLongArrowProducesColoredAndHaloPixels() throws {
        let base = makeImage(width: 100, height: 100)
        let style = AnnotationStyle(color: .red, strokeWidth: 8)
        let document = AnnotationDocument(
            basePixelSize: CGSize(width: 100, height: 100),
            pixelsPerPoint: 1,
            layers: [
                .arrow(ArrowLayer(start: CGPoint(x: 10, y: 50), end: CGPoint(x: 90, y: 50), style: style, headSize: 0))
            ]
        )

        let rendered = try AnnotationRenderer.render(document: document, baseImage: base)

        // Sample the line midpoint — should be saturated red (the colored shaft pass).
        let midShaft = samplePixel(in: rendered, x: 40, y: 50)
        XCTAssertGreaterThan(midShaft.red, 0.6, "Mid-shaft pixel should be predominantly red")
        XCTAssertLessThan(midShaft.green, 0.4, "Mid-shaft pixel should not be white")

        // Sample within the halo-only band: stroke 8 means the colored shaft occupies
        // y=46..54 (half-width 4 from the y=50 centerline). The halo extends another
        // (stroke + 3) / 2 - stroke / 2 = 1.5pt, so the halo-only band on each side is
        // y=54..55.5. y=55 sits squarely in that band and reads halo darkness, not the
        // opaque colored shaft.
        let haloEdge = samplePixel(in: rendered, x: 40, y: 55)
        XCTAssertLessThan(haloEdge.red, 0.95, "Halo region should be darker than the white base")
    }

    /// Each color in the palette must render. Smoke test that catches missing nsColor cases.
    func testAllPaletteColorsRender() throws {
        let base = makeImage(width: 60, height: 60)
        for color in AnnotationColor.allCases {
            let style = AnnotationStyle(color: color, strokeWidth: 6)
            let document = AnnotationDocument(
                basePixelSize: CGSize(width: 60, height: 60),
                pixelsPerPoint: 1,
                layers: [
                    .arrow(ArrowLayer(start: CGPoint(x: 5, y: 30), end: CGPoint(x: 55, y: 30), style: style, headSize: 0))
                ]
            )
            XCTAssertNoThrow(try AnnotationRenderer.render(document: document, baseImage: base),
                             "Renderer should handle color \(color.rawValue)")
        }
    }

    // MARK: - Helpers

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
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    /// Reads a single normalized RGBA pixel from a CGImage. Coordinates are in image
    /// pixels with origin at the *top-left* (matching how a user reads the image).
    private func samplePixel(in image: CGImage, x: Int, y: Int) -> (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        let width = 1
        let height = 1
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = CGContext(
            data: &pixel,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        // Translate the source image so the desired (x, y) lands at (0, 0) of our 1x1 buffer.
        // Note: CGImage drawing places origin at bottom-left, hence height-y-1.
        let drawRect = CGRect(x: -x, y: -(image.height - y - 1), width: image.width, height: image.height)
        context.draw(image, in: drawRect)
        return (
            red: CGFloat(pixel[0]) / 255,
            green: CGFloat(pixel[1]) / 255,
            blue: CGFloat(pixel[2]) / 255,
            alpha: CGFloat(pixel[3]) / 255
        )
    }
}

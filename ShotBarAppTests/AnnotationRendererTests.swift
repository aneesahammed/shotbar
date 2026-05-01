import XCTest
import CoreGraphics
import ImageIO
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
    /// color-space round-trip): no crash, no partial render.
    func testShortArrowProducesNoChangeFromBase() throws {
        let base = makeImage(width: 40, height: 40)
        let style = AnnotationStyle(color: .red, strokeWidth: 8)
        // Length 4pt with stroke 8: below minimum of 16, so no-op.
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
        // Sample center pixel: should still be white (the base color), not red.
        let center = samplePixel(in: rendered, x: 20, y: 20)
        XCTAssertGreaterThan(center.red, 0.95, "Short-arrow render should leave base pixels untouched")
        XCTAssertLessThan(center.green + center.blue, 2.5, "Pixel should not have picked up red")
    }

    /// A long arrow must produce visible non-base pixels along its path. Property
    /// assertions cover the bright fill and the darker same-color edge/shadow.
    func testLongArrowProducesColoredAndShadowPixels() throws {
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

        // The SVG-style block body is deliberately thick; the centerline must be filled.
        let midShaft = samplePixel(in: rendered, x: 40, y: 50)
        XCTAssertGreaterThan(midShaft.red, 0.6, "Mid-body pixel should be predominantly red")
        XCTAssertLessThan(midShaft.green, 0.4, "Mid-body pixel should not be white")

        // Sample outside the fill where the offset shadow should darken the white base.
        let shadowEdge = samplePixel(in: rendered, x: 60, y: 67)
        XCTAssertLessThan(shadowEdge.red, 0.99, "Shadow region should be darker than the white base")
        XCTAssertLessThan(shadowEdge.green, 0.99, "Shadow region should be darker than the white base")
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

    // MARK: - Visual fixtures

    /// Renders Skitch-style arrows at small/medium/large stroke widths and saves the
    /// output as PNGs to a sandbox-permitted temporary directory. This is not a
    /// pass/fail test; it's a way to produce visual evidence of the renderer for
    /// human inspection. The directory path is logged via `print` so you can
    /// `open <path>` after running. The XCTest target inherits the host app's
    /// sandbox, which blocks `/tmp`, so we use `NSTemporaryDirectory()` instead.
    func testGenerateSkitchArrowFixtures() throws {
        // Sandbox-persistent location inside the test target's container. After the
        // test runs, you can `open` the path printed at the end to inspect the PNGs.
        let caches = try FileManager.default.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = caches.appendingPathComponent("skitch-arrow-fixtures", isDirectory: true)
        try? FileManager.default.removeItem(at: dir)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // Surface path via test attachment so it appears in the xcresult bundle.
        let attachment = XCTAttachment(string: dir.path)
        attachment.lifetime = .keepAlways
        attachment.name = "fixture-directory"
        add(attachment)

        // Light backdrop so dark outline + drop shadow read clearly.
        let canvas = CGSize(width: 900, height: 440)
        let strokes: [CGFloat] = [4, 8, 12, 16, 24]
        let colors: [AnnotationColor] = [.red, .yellow, .blue, .green, .pink, .orange, .black]

        for color in colors {
            for stroke in strokes {
                let style = AnnotationStyle(color: color, strokeWidth: stroke)
                let document = AnnotationDocument(
                    basePixelSize: canvas,
                    pixelsPerPoint: 1,
                    layers: [
                        // Diagonal-ish drag, plenty of length so head dimensions don't clamp.
                        .arrow(ArrowLayer(
                            start: CGPoint(x: 100, y: 280),
                            end: CGPoint(x: 800, y: 160),
                            style: style,
                            headSize: 0
                        ))
                    ]
                )
                let rendered = try AnnotationRenderer.render(
                    document: document,
                    baseImage: makeBackground(width: Int(canvas.width), height: Int(canvas.height))
                )
                let filename = "arrow_\(color.rawValue)_stroke\(Int(stroke)).png"
                try writePNG(rendered, to: dir.appendingPathComponent(filename))
            }
        }

        let referenceLikeDoc = AnnotationDocument(
            basePixelSize: canvas,
            pixelsPerPoint: 1,
            layers: [
                .arrow(ArrowLayer(
                    start: CGPoint(x: 100, y: 220),
                    end: CGPoint(x: 800, y: 220),
                    style: AnnotationStyle(color: .pink, strokeWidth: 24),
                    headSize: 0
                ))
            ]
        )
        let referenceLike = try AnnotationRenderer.render(
            document: referenceLikeDoc,
            baseImage: makeBackground(width: Int(canvas.width), height: Int(canvas.height))
        )
        try writePNG(referenceLike, to: dir.appendingPathComponent("reference_like_pink_stroke24.png"))

        // Also render a "comparison strip" that lays the same color across every stroke
        // width on a single canvas so you can scan the whole gradient at once.
        let stripCanvas = CGSize(width: 900, height: 1500)
        var layers: [AnnotationLayer] = []
        for (i, stroke) in strokes.enumerated() {
            let y = 160 + CGFloat(i) * 290
            let style = AnnotationStyle(color: .red, strokeWidth: stroke)
            layers.append(.arrow(ArrowLayer(
                start: CGPoint(x: 100, y: y),
                end: CGPoint(x: 800, y: y),
                style: style,
                headSize: 0
            )))
        }
        let stripDoc = AnnotationDocument(basePixelSize: stripCanvas, pixelsPerPoint: 1, layers: layers)
        let strip = try AnnotationRenderer.render(
            document: stripDoc,
            baseImage: makeBackground(width: Int(stripCanvas.width), height: Int(stripCanvas.height))
        )
        try writePNG(strip, to: dir.appendingPathComponent("comparison_strip_red.png"))

        print("Skitch arrow fixtures written to \(dir.path)")
    }

    private func makeBackground(width: Int, height: Int) -> CGImage {
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        // Pale grey backdrop: outline + shadow against pure white can wash out.
        context.setFillColor(CGColor(red: 0.94, green: 0.94, blue: 0.94, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    private func writePNG(_ image: CGImage, to url: URL) throws {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
            throw NSError(domain: "ShotBarTests", code: -1, userInfo: [NSLocalizedDescriptionKey: "create destination failed"])
        }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else {
            throw NSError(domain: "ShotBarTests", code: -2, userInfo: [NSLocalizedDescriptionKey: "PNG finalize failed"])
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

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
}

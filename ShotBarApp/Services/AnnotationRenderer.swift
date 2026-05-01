import AppKit
import CoreImage
import CoreText

enum AnnotationRenderer {
    static func render(document: AnnotationDocument, baseImageURL: URL) async throws -> CGImage {
        try await Task.detached(priority: .userInitiated) {
            let baseImage = try ImageCodec.loadImage(from: baseImageURL)
            return try render(document: document, baseImage: baseImage)
        }.value
    }

    static func render(document: AnnotationDocument, baseImage: CGImage) throws -> CGImage {
        let width = max(1, Int(document.basePixelSize.width))
        let height = max(1, Int(document.basePixelSize.height))
        let colorSpace = baseImage.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw NSError(domain: "ShotBar", code: -50, userInfo: [NSLocalizedDescriptionKey: "Could not create annotation renderer"])
        }

        let fullRect = CGRect(x: 0, y: 0, width: width, height: height)
        context.interpolationQuality = .high
        context.draw(baseImage, in: fullRect)

        for layer in document.layers {
            switch layer {
            case .arrow(let arrow):
                drawArrow(arrow, in: context, canvasHeight: CGFloat(height))
            case .text(let text):
                drawText(text, in: context, canvasHeight: CGFloat(height))
            case .blur(let blur):
                applyBlur(blur, in: context, canvasSize: CGSize(width: width, height: height))
            }
        }

        guard var rendered = context.makeImage() else {
            throw NSError(domain: "ShotBar", code: -51, userInfo: [NSLocalizedDescriptionKey: "Could not render annotations"])
        }

        if let crop = document.crop?.standardized, !crop.isEmpty {
            let bounded = crop.intersection(CGRect(origin: .zero, size: CGSize(width: width, height: height)))
            let cgCrop = CGRect(
                x: bounded.minX,
                y: CGFloat(height) - bounded.maxY,
                width: bounded.width,
                height: bounded.height
            ).integral
            if let cropped = rendered.cropping(to: cgCrop) {
                rendered = cropped
            }
        }

        return rendered
    }

    /// SVG-style block annotation arrow: sharp tip, oversized head, concave shoulders,
    /// triangular shaft, pointed tail, same-color stroke, and soft offset shadow.
    private static func drawArrow(_ layer: ArrowLayer, in context: CGContext, canvasHeight: CGFloat) {
        let start = CGPoint(x: layer.start.x, y: canvasHeight - layer.start.y)
        let end = CGPoint(x: layer.end.x, y: canvasHeight - layer.end.y)
        let stroke = max(layer.style.strokeWidth, 1)
        guard let geom = ArrowGeometry(start: start, end: end, strokeWidth: stroke) else { return }

        let path = arrowBodyPath(geom)
        let fillColor = layer.style.color.arrowFillNSColor.cgColor
        let strokeColor = layer.style.color.arrowStrokeNSColor.cgColor

        // PASS 1: SVG-style offset blur shadow under the entire silhouette.
        context.saveGState()
        context.setShadow(
            offset: CGSize(width: geom.shadowOffset, height: -geom.shadowOffset),
            blur: geom.shadowBlur,
            color: NSColor.black.withAlphaComponent(0.24).cgColor
        )
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        context.addPath(path)
        context.setFillColor(fillColor)
        context.setStrokeColor(strokeColor)
        context.setLineWidth(geom.outlineWidth)
        context.setLineJoin(.round)
        context.setLineCap(.round)
        context.drawPath(using: .fillStroke)
        context.endTransparencyLayer()
        context.restoreGState()

        // PASS 2: bright flat fill, like the supplied SVG.
        context.saveGState()
        context.addPath(path)
        context.setFillColor(fillColor)
        context.fillPath()
        context.restoreGState()

        // PASS 3: darker same-color stroke, not a black comic outline.
        context.saveGState()
        context.addPath(path)
        context.setStrokeColor(strokeColor)
        context.setLineWidth(geom.outlineWidth)
        context.setLineJoin(.round)
        context.setLineCap(.round)
        context.strokePath()
        context.restoreGState()
    }

    /// Builds the closed SVG-style silhouette: sharp tip, concave shoulders, triangular shaft, pointed tail.
    private static func arrowBodyPath(_ geom: ArrowGeometry) -> CGPath {
        let path = CGMutablePath()
        let headHalf = geom.headWidth / 2
        let shoulderHalf = geom.shaftShoulderWidth / 2

        path.move(to: geom.point(axis: geom.tipEdgeAxis, normal: -geom.tipEdgeHalfWidth))
        path.addLine(to: geom.point(axis: geom.headLength, normal: -headHalf))
        path.addQuadCurve(
            to: geom.point(axis: geom.shoulderAxis, normal: -headHalf * 0.89),
            control: geom.point(axis: geom.shoulderControlAxis, normal: -headHalf * 1.06)
        )
        path.addLine(to: geom.point(axis: geom.notchAxis, normal: -shoulderHalf))
        path.addLine(to: geom.point(axis: geom.length, normal: 0))
        path.addLine(to: geom.point(axis: geom.notchAxis, normal: shoulderHalf))
        path.addLine(to: geom.point(axis: geom.shoulderAxis, normal: headHalf * 0.89))
        path.addQuadCurve(
            to: geom.point(axis: geom.headLength, normal: headHalf),
            control: geom.point(axis: geom.shoulderControlAxis, normal: headHalf * 1.06)
        )
        path.addLine(to: geom.point(axis: geom.tipEdgeAxis, normal: geom.tipEdgeHalfWidth))
        path.addLine(to: geom.tip)
        path.addLine(to: geom.point(axis: geom.tipEdgeAxis, normal: -geom.tipEdgeHalfWidth))
        path.closeSubpath()
        return path
    }

    private static func drawText(_ layer: TextLayer, in context: CGContext, canvasHeight: CGFloat) {
        guard !layer.text.isEmpty else { return }
        let rect = layer.rect.standardized
        guard rect.width > 0, rect.height > 0 else { return }

        context.saveGState()
        context.textMatrix = .identity
        let font = CTFontCreateWithName("HelveticaNeue-Bold" as CFString, layer.fontSize, nil)
        var lineBreak = CTLineBreakMode.byWordWrapping
        let paragraph = CTParagraphStyleCreate(
            [
                CTParagraphStyleSetting(
                    spec: .lineBreakMode,
                    valueSize: MemoryLayout<CTLineBreakMode>.size,
                    value: &lineBreak
                )
            ],
            1
        )
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: layer.style.color.nsColor,
            .paragraphStyle: paragraph
        ]
        let attributed = NSAttributedString(string: layer.text, attributes: attributes)

        let path = CGMutablePath()
        path.addRect(
            CGRect(
                x: rect.minX,
                y: canvasHeight - rect.maxY,
                width: rect.width,
                height: rect.height
            )
        )
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let frame = CTFramesetterCreateFrame(
            framesetter,
            CFRange(location: 0, length: attributed.length),
            path,
            nil
        )
        CTFrameDraw(frame, context)
        context.restoreGState()
    }

    private static func applyBlur(_ layer: BlurLayer, in context: CGContext, canvasSize: CGSize) {
        guard let current = context.makeImage() else { return }
        let rect = layer.rect.standardized.intersection(CGRect(origin: .zero, size: canvasSize))
        guard !rect.isEmpty else { return }

        let cgRect = CGRect(
            x: rect.minX,
            y: canvasSize.height - rect.maxY,
            width: rect.width,
            height: rect.height
        ).integral

        let ciImage = CIImage(cgImage: current)
        let output: CIImage?
        switch layer.mode {
        case .blur:
            output = ciImage
                .clampedToExtent()
                .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: max(layer.radius, 1)])
                .cropped(to: cgRect)
        case .pixelate:
            output = ciImage
                .applyingFilter("CIPixellate", parameters: [
                    kCIInputScaleKey: max(layer.pixelScale, 4),
                    kCIInputCenterKey: CIVector(x: cgRect.midX, y: cgRect.midY)
                ])
                .cropped(to: cgRect)
        }

        let ciContext = CIContext(options: nil)
        guard let output,
              let processed = ciContext.createCGImage(output, from: cgRect) else { return }

        context.saveGState()
        context.clip(to: cgRect)
        context.draw(processed, in: cgRect)
        context.restoreGState()
    }
}

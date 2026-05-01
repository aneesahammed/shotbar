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

    /// Skitch-style arrow: dark halo + crisp colored fill + single composited drop shadow.
    ///
    /// Pass 1 wraps the halo silhouette in a transparency layer so the entire arrow shape
    /// casts ONE drop shadow, not three stacked shadow blobs that would muddy the edges.
    /// Passes 2 and 3 then paint the colored shaft and head crisply on top with no shadow.
    private static func drawArrow(_ layer: ArrowLayer, in context: CGContext, canvasHeight: CGFloat) {
        let start = CGPoint(x: layer.start.x, y: canvasHeight - layer.start.y)
        let end = CGPoint(x: layer.end.x, y: canvasHeight - layer.end.y)
        let stroke = max(layer.style.strokeWidth, 1)
        guard let geom = ArrowGeometry(start: start, end: end, strokeWidth: stroke) else { return }

        let color = layer.style.color.nsColor.cgColor
        // 0.80 alpha is dark enough to read against busy photo backgrounds without going
        // fully opaque (which would look like a stencil instead of a tasteful halo).
        let halo = NSColor.black.withAlphaComponent(0.80).cgColor
        let haloStroke = stroke + 3

        // PASS 1 — halo silhouette + single composited drop shadow.
        // Default CGContext y-axis is up, so offset.height = -2 puts the shadow visually below.
        context.saveGState()
        context.setShadow(
            offset: CGSize(width: 0, height: -2),
            blur: 4,
            color: NSColor.black.withAlphaComponent(0.5).cgColor
        )
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        drawArrowSilhouette(geom: geom, lineWidth: haloStroke, color: halo, in: context)
        context.endTransparencyLayer()
        context.restoreGState()

        // PASS 2 — colored shaft (no shadow; lives entirely on top of the halo).
        context.saveGState()
        context.setStrokeColor(color)
        context.setLineWidth(stroke)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.move(to: geom.start)
        context.addLine(to: geom.shaftEnd)
        context.strokePath()
        context.restoreGState()

        // PASS 3 — colored arrowhead fill.
        context.saveGState()
        context.setFillColor(color)
        context.move(to: geom.tip)
        context.addLine(to: geom.leftBase)
        context.addLine(to: geom.rightBase)
        context.closePath()
        context.fillPath()
        context.restoreGState()
    }

    /// Renders the unified arrow silhouette (thick stroked shaft + filled triangle) as a
    /// single shape. Wraps its own state save/restore so callers don't have to.
    private static func drawArrowSilhouette(
        geom: ArrowGeometry,
        lineWidth: CGFloat,
        color: CGColor,
        in context: CGContext
    ) {
        context.saveGState()
        context.setStrokeColor(color)
        context.setFillColor(color)
        context.setLineWidth(lineWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.move(to: geom.start)
        context.addLine(to: geom.shaftEnd)
        context.strokePath()
        context.move(to: geom.tip)
        context.addLine(to: geom.leftBase)
        context.addLine(to: geom.rightBase)
        context.closePath()
        context.fillPath()
        context.restoreGState()
    }

    private static func drawText(_ layer: TextLayer, in context: CGContext, canvasHeight: CGFloat) {
        guard !layer.text.isEmpty else { return }
        context.saveGState()
        context.textMatrix = .identity
        let font = CTFontCreateWithName("HelveticaNeue-Bold" as CFString, layer.fontSize, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: layer.style.color.nsColor
        ]
        let attributed = NSAttributedString(string: layer.text, attributes: attributes)
        let line = CTLineCreateWithAttributedString(attributed)
        context.textPosition = CGPoint(
            x: layer.rect.minX,
            y: canvasHeight - layer.rect.minY - layer.fontSize
        )
        CTLineDraw(line, context)
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

        guard let output else { return }
        let ciContext = CIContext(options: nil)
        context.saveGState()
        context.clip(to: cgRect)
        ciContext.draw(output, in: cgRect, from: cgRect)
        context.restoreGState()
    }
}

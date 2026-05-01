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

    private static func drawArrow(_ layer: ArrowLayer, in context: CGContext, canvasHeight: CGFloat) {
        let start = CGPoint(x: layer.start.x, y: canvasHeight - layer.start.y)
        let end = CGPoint(x: layer.end.x, y: canvasHeight - layer.end.y)
        let color = layer.style.color.nsColor.cgColor
        let stroke = max(layer.style.strokeWidth, 1)

        context.saveGState()
        context.setStrokeColor(color)
        context.setFillColor(color)
        context.setLineWidth(stroke)
        context.setLineCap(.round)
        context.move(to: start)
        context.addLine(to: end)
        context.strokePath()

        let angle = atan2(end.y - start.y, end.x - start.x)
        let head = max(layer.headSize, stroke * 4)
        let left = CGPoint(
            x: end.x - head * cos(angle - .pi / 6),
            y: end.y - head * sin(angle - .pi / 6)
        )
        let right = CGPoint(
            x: end.x - head * cos(angle + .pi / 6),
            y: end.y - head * sin(angle + .pi / 6)
        )
        context.move(to: end)
        context.addLine(to: left)
        context.addLine(to: right)
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

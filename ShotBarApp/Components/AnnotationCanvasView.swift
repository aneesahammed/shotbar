import SwiftUI
import AppKit

struct AnnotationCanvasView: NSViewRepresentable {
    @ObservedObject var model: AnnotationDocumentModel

    func makeNSView(context: Context) -> AnnotationCanvasNSView {
        AnnotationCanvasNSView(model: model)
    }

    func updateNSView(_ nsView: AnnotationCanvasNSView, context: Context) {
        nsView.model = model
        nsView.needsDisplay = true
    }
}

final class AnnotationCanvasNSView: NSView {
    var model: AnnotationDocumentModel {
        didSet { needsDisplay = true }
    }

    private var zoomScale: CGFloat = 1
    private var panOffset: CGPoint = .zero
    private var dragStartPixel: CGPoint?
    private var dragCurrentPixel: CGPoint?
    private weak var activeTextView: CommitTextView?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    init(model: AnnotationDocumentModel) {
        self.model = model
        super.init(frame: .zero)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.underPageBackgroundColor.setFill()
        bounds.fill()

        let rect = imageRect()
        NSColor.black.withAlphaComponent(0.12).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4).fill()

        NSImage(cgImage: model.baseImage, size: model.document.basePixelSize).draw(in: rect)

        for layer in model.document.layers {
            draw(layer, in: rect)
        }

        if let crop = model.document.crop {
            drawCrop(crop, imageRect: rect, committed: true)
        }

        if let dragStartPixel, let dragCurrentPixel {
            drawInProgress(start: dragStartPixel, end: dragCurrentPixel, imageRect: rect)
        }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)
        guard let pixel = pixelPoint(fromViewPoint: point) else { return }

        if model.selectedTool == .text {
            beginTextEdit(at: point, pixel: pixel)
            return
        }

        dragStartPixel = pixel
        dragCurrentPixel = pixel
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard dragStartPixel != nil else { return }
        let point = convert(event.locationInWindow, from: nil)
        dragCurrentPixel = pixelPoint(fromViewPoint: point)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            dragStartPixel = nil
            dragCurrentPixel = nil
            needsDisplay = true
        }
        guard let start = dragStartPixel,
              let end = dragCurrentPixel else { return }
        let rect = normalizedRect(start, end).intersection(CGRect(origin: .zero, size: model.document.basePixelSize))
        guard distance(start, end) > 4 || model.selectedTool == .crop else { return }

        switch model.selectedTool {
        case .arrow:
            let style = AnnotationStyle(color: model.selectedColor, strokeWidth: model.strokeWidth)
            let layer = AnnotationLayer.arrow(ArrowLayer(start: start, end: end, style: style, headSize: model.strokeWidth * 5))
            model.apply(.addLayer(layer))
        case .blur:
            guard rect.width > 6, rect.height > 6 else { return }
            let layer = AnnotationLayer.blur(BlurLayer(rect: rect, mode: model.blurMode, radius: 12, pixelScale: 14))
            model.apply(.addLayer(layer))
        case .crop:
            guard rect.width > 10, rect.height > 10 else { return }
            model.apply(.setCrop(before: model.document.crop, after: rect))
        case .text:
            break
        }
    }

    override func scrollWheel(with event: NSEvent) {
        panOffset.x -= event.scrollingDeltaX
        panOffset.y -= event.scrollingDeltaY
        needsDisplay = true
    }

    override func magnify(with event: NSEvent) {
        zoomScale = min(6, max(0.2, zoomScale * (1 + event.magnification)))
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "0" {
            zoomScale = 1
            panOffset = .zero
            needsDisplay = true
            return
        }
        super.keyDown(with: event)
    }

    private func beginTextEdit(at viewPoint: CGPoint, pixel: CGPoint) {
        activeTextView?.removeFromSuperview()

        let frame = CGRect(x: viewPoint.x, y: viewPoint.y, width: 220, height: 36)
        let textView = CommitTextView(frame: frame)
        textView.font = .systemFont(ofSize: 18, weight: .semibold)
        textView.textColor = model.selectedColor.nsColor
        textView.backgroundColor = .textBackgroundColor
        textView.drawsBackground = true
        textView.isRichText = false
        textView.onCommit = { [weak self, weak textView] text in
            guard let self, let textView else { return }
            self.commitText(text, frame: textView.frame)
            textView.removeFromSuperview()
        }
        textView.onCancel = { [weak textView] in
            textView?.removeFromSuperview()
        }
        addSubview(textView)
        window?.makeFirstResponder(textView)
        activeTextView = textView
    }

    private func commitText(_ text: String, frame: CGRect) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let pixelRect = pixelRect(fromViewRect: frame)
            .intersection(CGRect(origin: .zero, size: model.document.basePixelSize))
        let style = AnnotationStyle(color: model.selectedColor, strokeWidth: model.strokeWidth)
        let layer = AnnotationLayer.text(TextLayer(text: trimmed, rect: pixelRect, style: style, fontSize: max(18, model.strokeWidth * 5)))
        model.apply(.addLayer(layer))
        needsDisplay = true
    }

    private func draw(_ layer: AnnotationLayer, in imageRect: CGRect) {
        switch layer {
        case .arrow(let arrow):
            drawArrow(arrow, imageRect: imageRect)
        case .text(let text):
            drawText(text, imageRect: imageRect)
        case .blur(let blur):
            drawBlurPlaceholder(blur, imageRect: imageRect)
        }
    }

    private func drawInProgress(start: CGPoint, end: CGPoint, imageRect: CGRect) {
        switch model.selectedTool {
        case .arrow:
            let style = AnnotationStyle(color: model.selectedColor, strokeWidth: model.strokeWidth)
            drawArrow(ArrowLayer(start: start, end: end, style: style, headSize: model.strokeWidth * 5), imageRect: imageRect)
        case .blur:
            drawBlurPlaceholder(BlurLayer(rect: normalizedRect(start, end), mode: model.blurMode, radius: 12, pixelScale: 14), imageRect: imageRect)
        case .crop:
            drawCrop(normalizedRect(start, end), imageRect: imageRect, committed: false)
        case .text:
            break
        }
    }

    private func drawArrow(_ layer: ArrowLayer, imageRect: CGRect) {
        let start = viewPoint(fromPixelPoint: layer.start, imageRect: imageRect)
        let end = viewPoint(fromPixelPoint: layer.end, imageRect: imageRect)
        let path = NSBezierPath()
        path.move(to: start)
        path.line(to: end)
        path.lineWidth = max(layer.style.strokeWidth, 1)
        layer.style.color.nsColor.setStroke()
        path.lineCapStyle = .round
        path.stroke()

        let angle = atan2(end.y - start.y, end.x - start.x)
        let head = max(layer.headSize * imageRect.width / model.document.basePixelSize.width, 8)
        let left = CGPoint(x: end.x - head * cos(angle - .pi / 6), y: end.y - head * sin(angle - .pi / 6))
        let right = CGPoint(x: end.x - head * cos(angle + .pi / 6), y: end.y - head * sin(angle + .pi / 6))
        let headPath = NSBezierPath()
        headPath.move(to: end)
        headPath.line(to: left)
        headPath.line(to: right)
        headPath.close()
        layer.style.color.nsColor.setFill()
        headPath.fill()
    }

    private func drawText(_ layer: TextLayer, imageRect: CGRect) {
        let rect = viewRect(fromPixelRect: layer.rect, imageRect: imageRect)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: max(10, layer.fontSize * imageRect.width / model.document.basePixelSize.width), weight: .semibold),
            .foregroundColor: layer.style.color.nsColor
        ]
        NSAttributedString(string: layer.text, attributes: attrs).draw(in: rect)
    }

    private func drawBlurPlaceholder(_ layer: BlurLayer, imageRect: CGRect) {
        let rect = viewRect(fromPixelRect: layer.rect, imageRect: imageRect)
        NSColor.controlAccentColor.withAlphaComponent(0.18).setFill()
        NSBezierPath(rect: rect).fill()
        NSColor.controlAccentColor.setStroke()
        let path = NSBezierPath(rect: rect)
        var dashes: [CGFloat] = [5, 4]
        path.setLineDash(&dashes, count: dashes.count, phase: 0)
        path.lineWidth = 1.5
        path.stroke()
    }

    private func drawCrop(_ crop: CGRect, imageRect: CGRect, committed: Bool) {
        let rect = viewRect(fromPixelRect: crop, imageRect: imageRect)
        (committed ? NSColor.systemYellow : NSColor.white).setStroke()
        let path = NSBezierPath(rect: rect)
        var dashes: [CGFloat] = [6, 4]
        path.setLineDash(&dashes, count: dashes.count, phase: 0)
        path.lineWidth = committed ? 2 : 1.5
        path.stroke()
    }

    private func imageRect() -> CGRect {
        let size = model.document.basePixelSize
        guard size.width > 0, size.height > 0, bounds.width > 0, bounds.height > 0 else { return .zero }
        let fit = min(bounds.width / size.width, bounds.height / size.height) * zoomScale
        let scaled = CGSize(width: size.width * fit, height: size.height * fit)
        return CGRect(
            x: (bounds.width - scaled.width) / 2 + panOffset.x,
            y: (bounds.height - scaled.height) / 2 + panOffset.y,
            width: scaled.width,
            height: scaled.height
        )
    }

    private func pixelPoint(fromViewPoint point: CGPoint) -> CGPoint? {
        let rect = imageRect()
        guard rect.contains(point) else { return nil }
        let x = (point.x - rect.minX) / rect.width * model.document.basePixelSize.width
        let y = (point.y - rect.minY) / rect.height * model.document.basePixelSize.height
        return CGPoint(
            x: min(max(x, 0), model.document.basePixelSize.width),
            y: min(max(y, 0), model.document.basePixelSize.height)
        )
    }

    private func pixelRect(fromViewRect viewRect: CGRect) -> CGRect {
        let rect = imageRect()
        guard rect.width > 0, rect.height > 0 else { return .zero }
        return CGRect(
            x: (viewRect.minX - rect.minX) / rect.width * model.document.basePixelSize.width,
            y: (viewRect.minY - rect.minY) / rect.height * model.document.basePixelSize.height,
            width: viewRect.width / rect.width * model.document.basePixelSize.width,
            height: viewRect.height / rect.height * model.document.basePixelSize.height
        )
    }

    private func viewPoint(fromPixelPoint point: CGPoint, imageRect: CGRect) -> CGPoint {
        CGPoint(
            x: imageRect.minX + point.x / model.document.basePixelSize.width * imageRect.width,
            y: imageRect.minY + point.y / model.document.basePixelSize.height * imageRect.height
        )
    }

    private func viewRect(fromPixelRect rect: CGRect, imageRect: CGRect) -> CGRect {
        CGRect(
            x: imageRect.minX + rect.minX / model.document.basePixelSize.width * imageRect.width,
            y: imageRect.minY + rect.minY / model.document.basePixelSize.height * imageRect.height,
            width: rect.width / model.document.basePixelSize.width * imageRect.width,
            height: rect.height / model.document.basePixelSize.height * imageRect.height
        )
    }

    private func normalizedRect(_ a: CGPoint, _ b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }
}

private final class CommitTextView: NSTextView {
    var onCommit: ((String) -> Void)?
    var onCancel: (() -> Void)?
    private var didFinish = false

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            didFinish = true
            onCancel?()
            return
        }
        if event.keyCode == 36 && !event.modifierFlags.contains(.shift) {
            didFinish = true
            onCommit?(string)
            return
        }
        super.keyDown(with: event)
    }

    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        if result, !didFinish {
            didFinish = true
            onCommit?(string)
        }
        return result
    }
}

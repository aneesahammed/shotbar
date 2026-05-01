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
    private var selectedLayerID: UUID?
    private var textMoveDrag: TextMoveDrag?
    private var textResizeDrag: TextResizeDrag?

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
            if let selected = selectedTextLayer(),
               let handle = resizeHandle(at: point, for: selected) {
                textResizeDrag = TextResizeDrag(original: selected, current: selected, handle: handle)
                needsDisplay = true
                return
            }

            if let layer = topmostTextLayer(at: pixel) {
                selectedLayerID = layer.id
                textMoveDrag = TextMoveDrag(
                    original: layer,
                    current: layer,
                    grabOffset: CGPoint(x: pixel.x - layer.rect.minX, y: pixel.y - layer.rect.minY)
                )
                needsDisplay = true
                return
            }
            selectedLayerID = nil
            beginTextEdit(at: point, pixel: pixel)
            return
        }

        selectedLayerID = nil
        dragStartPixel = pixel
        dragCurrentPixel = pixel
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        if textResizeDrag != nil {
            let point = convert(event.locationInWindow, from: nil)
            resizeActiveText(to: point)
            return
        }

        if textMoveDrag != nil {
            let point = convert(event.locationInWindow, from: nil)
            moveActiveText(to: point)
            return
        }

        guard dragStartPixel != nil else { return }
        let point = convert(event.locationInWindow, from: nil)
        dragCurrentPixel = pixelPoint(fromViewPoint: point)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if textResizeDrag != nil {
            finishTextResize()
            return
        }

        if textMoveDrag != nil {
            finishTextMove()
            return
        }

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
            // Use ArrowGeometry as the single source of truth for "is this drag a renderable
            // arrow?" The mouse-up `distance > 4` gate above is looser than the renderer's
            // `max(stroke*2, 8)` reject threshold, so without this check a 5-7pt drag at
            // stroke 8 would commit a layer that both renderers silently no-op, leaving an
            // invisible entry in undo history.
            guard ArrowGeometry(start: start, end: end, strokeWidth: model.strokeWidth) != nil else { return }
            let style = AnnotationStyle(color: model.selectedColor, strokeWidth: model.strokeWidth)
            let layer = AnnotationLayer.arrow(ArrowLayer(start: start, end: end, style: style, headSize: 0))
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
        if event.modifierFlags.contains(.command),
           event.charactersIgnoringModifiers?.lowercased() == "z" {
            if event.modifierFlags.contains(.shift) {
                model.redo()
            } else {
                model.undo()
            }
            needsDisplay = true
            return
        }

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

        let imageFrame = imageRect()
        let frame = CGRect(
            x: viewPoint.x,
            y: viewPoint.y,
            width: min(260, max(120, imageFrame.maxX - viewPoint.x)),
            height: max(32, model.currentTextFontSize + 8)
        )
        let textView = CommitTextView(frame: frame)
        textView.font = .systemFont(ofSize: model.currentTextFontSize, weight: .semibold)
        textView.textColor = model.selectedColor.nsColor
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.textContainer?.containerSize = CGSize(width: frame.width, height: .greatestFiniteMagnitude)
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.minSize = frame.size
        textView.maxSize = CGSize(width: max(frame.width, imageFrame.maxX - viewPoint.x), height: .greatestFiniteMagnitude)
        textView.onTextChanged = { [weak self, weak textView] in
            guard let self, let textView else { return }
            self.resizeTextEditor(textView)
        }
        textView.onCommit = { [weak self, weak textView] text in
            guard let self, let textView else { return }
            self.commitText(
                text,
                frame: textView.frame,
                viewFontSize: textView.font?.pointSize ?? self.model.currentTextFontSize
            )
            textView.removeFromSuperview()
        }
        textView.onCancel = { [weak textView] in
            textView?.removeFromSuperview()
        }
        addSubview(textView)
        window?.makeFirstResponder(textView)
        activeTextView = textView
        resizeTextEditor(textView)
    }

    private func commitText(_ text: String, frame: CGRect, viewFontSize: CGFloat) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let pixelRect = pixelRect(fromViewRect: frame)
            .intersection(CGRect(origin: .zero, size: model.document.basePixelSize))
        let style = AnnotationStyle(color: model.selectedColor, strokeWidth: model.strokeWidth)
        let layer = AnnotationLayer.text(TextLayer(
            text: trimmed,
            rect: pixelRect,
            style: style,
            fontSize: pixelFontSize(fromViewFontSize: viewFontSize)
        ))
        model.apply(.addLayer(layer))
        selectedLayerID = layer.id
        needsDisplay = true
    }

    private func resizeTextEditor(_ textView: CommitTextView) {
        guard let font = textView.font else { return }
        let imageFrame = imageRect()
        let availableWidth = max(120, imageFrame.maxX - textView.frame.minX)
        let availableHeight = max(32, imageFrame.maxY - textView.frame.minY)
        let minWidth: CGFloat = 120
        let text = textView.string.isEmpty ? "Text" : textView.string
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        let measured = (text as NSString).boundingRect(
            with: CGSize(width: availableWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [
                .font: font,
                .paragraphStyle: paragraph
            ]
        )
        let lineHeight = ceil(font.ascender - font.descender + font.leading)
        let size = CGSize(
            width: min(availableWidth, max(minWidth, ceil(measured.width) + 4)),
            height: min(availableHeight, max(lineHeight + 4, ceil(measured.height) + 4))
        )
        textView.frame.size = size
        textView.textContainer?.containerSize = CGSize(width: size.width, height: .greatestFiniteMagnitude)
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

    /// SVG-style block annotation arrow rendered into the live editor canvas.
    /// Mirrors `AnnotationRenderer.drawArrow`: sharp tip, oversized head, concave
    /// shoulders, triangular shaft, pointed tail, same-color stroke, and soft shadow.
    private func drawArrow(_ layer: ArrowLayer, imageRect: CGRect) {
        let start = viewPoint(fromPixelPoint: layer.start, imageRect: imageRect)
        let end = viewPoint(fromPixelPoint: layer.end, imageRect: imageRect)
        let imageScale = imageRect.width / model.document.basePixelSize.width
        let displayStroke = max(layer.style.strokeWidth * imageScale, 1)
        guard let geom = ArrowGeometry(start: start, end: end, strokeWidth: displayStroke) else { return }

        let path = arrowBodyPath(geom)
        let fillColor = layer.style.color.arrowFillNSColor
        let strokeColor = layer.style.color.arrowStrokeNSColor

        guard let cgContext = NSGraphicsContext.current?.cgContext else { return }

        // PASS 1: SVG-style offset blur shadow under the entire silhouette.
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowOffset = NSSize(width: geom.shadowOffset, height: geom.shadowOffset)
        shadow.shadowBlurRadius = geom.shadowBlur
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.24)
        shadow.set()
        cgContext.beginTransparencyLayer(auxiliaryInfo: nil)
        fillColor.setFill()
        strokeColor.setStroke()
        path.lineWidth = geom.outlineWidth
        path.lineJoinStyle = .round
        path.lineCapStyle = .round
        path.fill()
        path.stroke()
        cgContext.endTransparencyLayer()
        NSGraphicsContext.restoreGraphicsState()

        // PASS 2: bright flat fill, like the supplied SVG.
        NSGraphicsContext.saveGraphicsState()
        fillColor.setFill()
        path.fill()
        NSGraphicsContext.restoreGraphicsState()

        // PASS 3: darker same-color stroke, not a black comic outline.
        NSGraphicsContext.saveGraphicsState()
        strokeColor.setStroke()
        path.lineWidth = geom.outlineWidth
        path.lineJoinStyle = .round
        path.lineCapStyle = .round
        path.stroke()
        NSGraphicsContext.restoreGraphicsState()
    }

    /// Closed SVG-style silhouette: sharp tip, concave shoulders, triangular shaft, pointed tail.
    private func arrowBodyPath(_ geom: ArrowGeometry) -> NSBezierPath {
        let path = NSBezierPath()
        let headHalf = geom.headWidth / 2
        let shoulderHalf = geom.shaftShoulderWidth / 2

        path.move(to: geom.point(axis: geom.tipEdgeAxis, normal: -geom.tipEdgeHalfWidth))
        path.line(to: geom.point(axis: geom.headLength, normal: -headHalf))
        path.addQuadCurve(
            to: geom.point(axis: geom.shoulderAxis, normal: -headHalf * 0.89),
            control: geom.point(axis: geom.shoulderControlAxis, normal: -headHalf * 1.06)
        )
        path.line(to: geom.point(axis: geom.notchAxis, normal: -shoulderHalf))
        path.line(to: geom.point(axis: geom.length, normal: 0))
        path.line(to: geom.point(axis: geom.notchAxis, normal: shoulderHalf))
        path.line(to: geom.point(axis: geom.shoulderAxis, normal: headHalf * 0.89))
        path.addQuadCurve(
            to: geom.point(axis: geom.headLength, normal: headHalf),
            control: geom.point(axis: geom.shoulderControlAxis, normal: headHalf * 1.06)
        )
        path.line(to: geom.point(axis: geom.tipEdgeAxis, normal: geom.tipEdgeHalfWidth))
        path.line(to: geom.tip)
        path.line(to: geom.point(axis: geom.tipEdgeAxis, normal: -geom.tipEdgeHalfWidth))
        path.close()
        return path
    }

    private func drawText(_ layer: TextLayer, imageRect: CGRect) {
        let rect = viewRect(fromPixelRect: layer.rect, imageRect: imageRect)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: max(10, layer.fontSize * imageRect.width / model.document.basePixelSize.width), weight: .semibold),
            .foregroundColor: layer.style.color.nsColor
        ]
        NSAttributedString(string: layer.text, attributes: attrs).draw(in: rect)

        if selectedLayerID == layer.id {
            drawTextSelection(rect)
        }
    }

    private func drawTextSelection(_ rect: CGRect) {
        let path = NSBezierPath(rect: rect.insetBy(dx: -4, dy: -3))
        var dashes: [CGFloat] = [5, 3]
        NSColor.controlAccentColor.setStroke()
        path.lineWidth = 1.5
        path.setLineDash(&dashes, count: dashes.count, phase: 0)
        path.stroke()

        for handleRect in resizeHandleRects(for: rect).values {
            let handle = NSBezierPath(roundedRect: handleRect, xRadius: 2, yRadius: 2)
            NSColor.controlAccentColor.setFill()
            handle.fill()
            NSColor.white.withAlphaComponent(0.95).setStroke()
            handle.lineWidth = 1
            handle.stroke()
        }
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

    private func clampedPixelPoint(fromViewPoint point: CGPoint) -> CGPoint? {
        let rect = imageRect()
        guard rect.width > 0, rect.height > 0 else { return nil }
        let x = (point.x - rect.minX) / rect.width * model.document.basePixelSize.width
        let y = (point.y - rect.minY) / rect.height * model.document.basePixelSize.height
        return CGPoint(
            x: min(max(x, 0), model.document.basePixelSize.width),
            y: min(max(y, 0), model.document.basePixelSize.height)
        )
    }

    private func imageDisplayScale() -> CGFloat {
        imageRect().width / max(model.document.basePixelSize.width, 1)
    }

    private func pixelFontSize(fromViewFontSize viewFontSize: CGFloat) -> CGFloat {
        viewFontSize / max(imageDisplayScale(), 0.001)
    }

    private func viewFontSize(fromPixelFontSize pixelFontSize: CGFloat) -> CGFloat {
        pixelFontSize * imageDisplayScale()
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

    private func selectedTextLayer() -> TextLayer? {
        guard let selectedLayerID else { return nil }
        for layer in model.document.layers {
            guard case .text(let text) = layer, text.id == selectedLayerID else { continue }
            return text
        }
        return nil
    }

    private func topmostTextLayer(at pixel: CGPoint) -> TextLayer? {
        let imageScale = imageRect().width / max(model.document.basePixelSize.width, 1)
        let hitPadding = max(2, 6 / max(imageScale, 0.001))
        for layer in model.document.layers.reversed() {
            guard case .text(let text) = layer else { continue }
            if text.rect.standardized.insetBy(dx: -hitPadding, dy: -hitPadding).contains(pixel) {
                return text
            }
        }
        return nil
    }

    private func moveActiveText(to viewPoint: CGPoint) {
        guard var drag = textMoveDrag,
              let pixel = clampedPixelPoint(fromViewPoint: viewPoint) else { return }

        var updated = drag.current
        updated.rect = boundedTextRect(
            updated.rect,
            origin: CGPoint(
                x: pixel.x - drag.grabOffset.x,
                y: pixel.y - drag.grabOffset.y
            )
        )
        drag.current = updated
        textMoveDrag = drag
        model.replaceLayerForPreview(.text(updated))
        needsDisplay = true
    }

    private func finishTextMove() {
        guard let drag = textMoveDrag else { return }
        defer {
            textMoveDrag = nil
            needsDisplay = true
        }

        guard drag.original.rect != drag.current.rect else { return }
        model.apply(.updateLayer(before: .text(drag.original), after: .text(drag.current)))
    }

    private func resizeActiveText(to viewPoint: CGPoint) {
        guard var drag = textResizeDrag,
              let pixel = clampedPixelPoint(fromViewPoint: viewPoint) else { return }

        let updated = resizedTextLayer(drag.original, to: pixel, handle: drag.handle)
        drag.current = updated
        textResizeDrag = drag
        model.replaceLayerForPreview(.text(updated))
        needsDisplay = true
    }

    private func finishTextResize() {
        guard let drag = textResizeDrag else { return }
        defer {
            textResizeDrag = nil
            needsDisplay = true
        }

        guard drag.original.rect != drag.current.rect || drag.original.fontSize != drag.current.fontSize else { return }
        model.apply(.updateLayer(before: .text(drag.original), after: .text(drag.current)))
    }

    private func resizedTextLayer(_ original: TextLayer, to pixel: CGPoint, handle: TextResizeHandle) -> TextLayer {
        let bounds = CGRect(origin: .zero, size: model.document.basePixelSize)
        let originalRect = original.rect.standardized
        let minViewSize = CGSize(width: 42, height: 22)
        let scale = max(imageDisplayScale(), 0.001)
        let minSize = CGSize(width: minViewSize.width / scale, height: minViewSize.height / scale)
        let clamped = CGPoint(
            x: min(max(pixel.x, bounds.minX), bounds.maxX),
            y: min(max(pixel.y, bounds.minY), bounds.maxY)
        )

        var rect: CGRect
        switch handle {
        case .topLeft:
            let x = min(max(clamped.x, bounds.minX), originalRect.maxX - minSize.width)
            let y = min(max(clamped.y, bounds.minY), originalRect.maxY - minSize.height)
            rect = CGRect(x: x, y: y, width: originalRect.maxX - x, height: originalRect.maxY - y)
        case .topRight:
            let maxX = max(min(clamped.x, bounds.maxX), originalRect.minX + minSize.width)
            let y = min(max(clamped.y, bounds.minY), originalRect.maxY - minSize.height)
            rect = CGRect(x: originalRect.minX, y: y, width: maxX - originalRect.minX, height: originalRect.maxY - y)
        case .bottomLeft:
            let x = min(max(clamped.x, bounds.minX), originalRect.maxX - minSize.width)
            let maxY = max(min(clamped.y, bounds.maxY), originalRect.minY + minSize.height)
            rect = CGRect(x: x, y: originalRect.minY, width: originalRect.maxX - x, height: maxY - originalRect.minY)
        case .bottomRight:
            let maxX = max(min(clamped.x, bounds.maxX), originalRect.minX + minSize.width)
            let maxY = max(min(clamped.y, bounds.maxY), originalRect.minY + minSize.height)
            rect = CGRect(x: originalRect.minX, y: originalRect.minY, width: maxX - originalRect.minX, height: maxY - originalRect.minY)
        }

        var updated = original
        updated.rect = rect.integral
        let originalDisplayHeight = max(originalRect.height * scale, minViewSize.height)
        let newDisplayHeight = max(rect.height * scale, minViewSize.height)
        let viewFontSize = viewFontSize(fromPixelFontSize: original.fontSize)
        let scaledViewFontSize = min(180, max(8, viewFontSize * (newDisplayHeight / originalDisplayHeight)))
        updated.fontSize = pixelFontSize(fromViewFontSize: scaledViewFontSize)
        return updated
    }

    private func boundedTextRect(_ rect: CGRect, origin: CGPoint) -> CGRect {
        let size = model.document.basePixelSize
        let standardized = rect.standardized
        return CGRect(
            x: min(max(origin.x, 0), max(0, size.width - standardized.width)),
            y: min(max(origin.y, 0), max(0, size.height - standardized.height)),
            width: standardized.width,
            height: standardized.height
        )
    }

    private func resizeHandle(at point: CGPoint, for text: TextLayer) -> TextResizeHandle? {
        let viewRect = viewRect(fromPixelRect: text.rect, imageRect: imageRect())
        let handles = resizeHandleRects(for: viewRect)
        return TextResizeHandle.allCases.first { handle in
            handles[handle]?.insetBy(dx: -4, dy: -4).contains(point) == true
        }
    }

    private func resizeHandleRects(for rect: CGRect) -> [TextResizeHandle: CGRect] {
        let size: CGFloat = 8
        let half = size / 2
        return [
            .topLeft: CGRect(x: rect.minX - half, y: rect.minY - half, width: size, height: size),
            .topRight: CGRect(x: rect.maxX - half, y: rect.minY - half, width: size, height: size),
            .bottomLeft: CGRect(x: rect.minX - half, y: rect.maxY - half, width: size, height: size),
            .bottomRight: CGRect(x: rect.maxX - half, y: rect.maxY - half, width: size, height: size)
        ]
    }
}

private struct TextMoveDrag {
    var original: TextLayer
    var current: TextLayer
    var grabOffset: CGPoint
}

private struct TextResizeDrag {
    var original: TextLayer
    var current: TextLayer
    var handle: TextResizeHandle
}

private enum TextResizeHandle: CaseIterable {
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight
}

private extension NSBezierPath {
    func addQuadCurve(to end: CGPoint, control: CGPoint) {
        let start = currentPoint
        let controlPoint1 = CGPoint(
            x: start.x + (control.x - start.x) * 2 / 3,
            y: start.y + (control.y - start.y) * 2 / 3
        )
        let controlPoint2 = CGPoint(
            x: end.x + (control.x - end.x) * 2 / 3,
            y: end.y + (control.y - end.y) * 2 / 3
        )
        curve(to: end, controlPoint1: controlPoint1, controlPoint2: controlPoint2)
    }
}

private final class CommitTextView: NSTextView {
    var onCommit: ((String) -> Void)?
    var onCancel: (() -> Void)?
    var onTextChanged: (() -> Void)?
    private var didFinish = false

    override func didChangeText() {
        super.didChangeText()
        onTextChanged?()
    }

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command),
           event.charactersIgnoringModifiers?.lowercased() == "z" {
            if event.modifierFlags.contains(.shift) {
                undoManager?.redo()
            } else {
                undoManager?.undo()
            }
            return
        }

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

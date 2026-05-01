import CoreGraphics

struct BlurTool: AnnotationTool {
    let kind: AnnotationToolKind = .blur

    func command(start: CGPoint, end: CGPoint, model: AnnotationDocumentModel) -> AnnotationCommand? {
        let rect = CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(start.x - end.x), height: abs(start.y - end.y))
        guard rect.width > 6, rect.height > 6 else { return nil }
        return .addLayer(.blur(BlurLayer(
            rect: rect,
            mode: model.blurMode,
            radius: model.currentBlurRadius,
            pixelScale: model.currentPixelScale
        )))
    }
}

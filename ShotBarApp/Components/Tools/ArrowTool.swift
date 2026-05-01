import CoreGraphics

struct ArrowTool: AnnotationTool {
    let kind: AnnotationToolKind = .arrow

    func command(start: CGPoint, end: CGPoint, model: AnnotationDocumentModel) -> AnnotationCommand? {
        guard hypot(start.x - end.x, start.y - end.y) > 4 else { return nil }
        let style = AnnotationStyle(color: model.selectedColor, strokeWidth: model.strokeWidth)
        return .addLayer(.arrow(ArrowLayer(start: start, end: end, style: style, headSize: model.strokeWidth * 5)))
    }
}

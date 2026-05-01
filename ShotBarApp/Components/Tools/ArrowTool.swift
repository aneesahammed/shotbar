import CoreGraphics

struct ArrowTool: AnnotationTool {
    let kind: AnnotationToolKind = .arrow

    func command(start: CGPoint, end: CGPoint, model: AnnotationDocumentModel) -> AnnotationCommand? {
        // ArrowGeometry is the single source of truth for "renderable arrow"; if it can't
        // build a geometry from these inputs, neither renderer will draw anything, so we
        // must not commit a layer (avoids invisible entries in undo history).
        guard ArrowGeometry(start: start, end: end, strokeWidth: model.strokeWidth) != nil else { return nil }
        let style = AnnotationStyle(color: model.selectedColor, strokeWidth: model.strokeWidth)
        // headSize is deprecated and ignored at render time; see ArrowLayer.headSize.
        return .addLayer(.arrow(ArrowLayer(start: start, end: end, style: style, headSize: 0)))
    }
}

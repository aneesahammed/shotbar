import CoreGraphics

struct CropTool: AnnotationTool {
    let kind: AnnotationToolKind = .crop

    func command(start: CGPoint, end: CGPoint, model: AnnotationDocumentModel) -> AnnotationCommand? {
        let rect = CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(start.x - end.x), height: abs(start.y - end.y))
        guard rect.width > 10, rect.height > 10 else { return nil }
        return .setCrop(before: model.document.crop, after: rect)
    }
}

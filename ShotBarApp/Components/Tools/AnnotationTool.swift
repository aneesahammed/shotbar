import CoreGraphics

protocol AnnotationTool {
    var kind: AnnotationToolKind { get }
    func command(start: CGPoint, end: CGPoint, model: AnnotationDocumentModel) -> AnnotationCommand?
}

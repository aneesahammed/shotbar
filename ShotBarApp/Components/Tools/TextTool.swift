import CoreGraphics

struct TextTool {
    static func command(text: String, rect: CGRect, model: AnnotationDocumentModel) -> AnnotationCommand? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let style = AnnotationStyle(color: model.selectedColor, strokeWidth: model.strokeWidth)
        return .addLayer(.text(TextLayer(text: trimmed, rect: rect, style: style, fontSize: model.currentTextFontSize)))
    }
}

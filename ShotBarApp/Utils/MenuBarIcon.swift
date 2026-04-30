import AppKit

/// Generates the ShotBar menu bar template icon as a vector drawing.
/// The icon adapts automatically to light/dark mode via `isTemplate = true`.
enum MenuBarIcon {
    /// Returns a template NSImage sized appropriately for the menu bar.
    /// macOS typically renders menu bar icons at 18x18 points.
    static func makeTemplateIcon(size: CGFloat = 18) -> NSImage {
        let imageSize = NSSize(width: size, height: size)
        let image = NSImage(size: imageSize)
        image.lockFocus()

        // Template images ignore the actual color in the menu bar.
        let strokeColor = NSColor.labelColor
        strokeColor.setStroke()
        strokeColor.setFill()

        let scale = size / 18.0
        let lineWidth: CGFloat = 1.7 * scale
        let inset: CGFloat = 3.2 * scale
        let rect = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
        let bracketLength: CGFloat = 4.3 * scale

        let bracketPath = NSBezierPath()
        bracketPath.lineWidth = lineWidth
        bracketPath.lineCapStyle = .round
        bracketPath.lineJoinStyle = .round

        bracketPath.move(to: NSPoint(x: rect.minX, y: rect.maxY - bracketLength))
        bracketPath.line(to: NSPoint(x: rect.minX, y: rect.maxY))
        bracketPath.line(to: NSPoint(x: rect.minX + bracketLength, y: rect.maxY))

        bracketPath.move(to: NSPoint(x: rect.maxX - bracketLength, y: rect.maxY))
        bracketPath.line(to: NSPoint(x: rect.maxX, y: rect.maxY))
        bracketPath.line(to: NSPoint(x: rect.maxX, y: rect.maxY - bracketLength))

        bracketPath.move(to: NSPoint(x: rect.minX, y: rect.minY + bracketLength))
        bracketPath.line(to: NSPoint(x: rect.minX, y: rect.minY))
        bracketPath.line(to: NSPoint(x: rect.minX + bracketLength, y: rect.minY))

        bracketPath.move(to: NSPoint(x: rect.maxX - bracketLength, y: rect.minY))
        bracketPath.line(to: NSPoint(x: rect.maxX, y: rect.minY))
        bracketPath.line(to: NSPoint(x: rect.maxX, y: rect.minY + bracketLength))
        bracketPath.stroke()

        let dotDiameter: CGFloat = 3.1 * scale
        let dotRect = NSRect(
            x: rect.midX - dotDiameter / 2,
            y: rect.midY - dotDiameter / 2,
            width: dotDiameter,
            height: dotDiameter
        )
        let dotPath = NSBezierPath(ovalIn: dotRect)
        dotPath.fill()

        image.unlockFocus()
        image.isTemplate = true
        return image
    }
}

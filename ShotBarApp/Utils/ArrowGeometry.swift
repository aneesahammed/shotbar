import CoreGraphics

/// Pure-math description of the SVG-style block annotation arrow.
///
/// The arrow is a single closed shape with a sharp triangular start, huge triangular
/// head, concave shoulders, and triangular shaft. This intentionally
/// tracks the reference SVG silhouette instead of a thin line with an arrow marker.
///
/// Coordinate-space contract: `start`, `end`, and `strokeWidth` are all in the
/// consumer's drawing space. This type never flips, scales, or transforms; callers
/// are responsible for mapping pixel-space layer data into their renderer's
/// coordinate system before invoking the initializer.
///
/// The initializer is failable: drags shorter than `max(strokeWidth * 2, 8)` return
/// `nil` so renderers can early-return cleanly on partial gestures or accidental clicks.
struct ArrowGeometry {
    /// Original drag start (= layer's `start` in drawing space). This is the sharp tail point.
    let start: CGPoint
    /// Arrowhead tip (= layer's `end` in drawing space).
    let tip: CGPoint

    let length: CGFloat
    let axisX: CGFloat
    let axisY: CGFloat
    let normalX: CGFloat
    let normalY: CGFloat

    let headLength: CGFloat
    let headWidth: CGFloat
    let shaftShoulderWidth: CGFloat
    let tipEdgeAxis: CGFloat
    let tipEdgeHalfWidth: CGFloat
    let notchAxis: CGFloat
    let shoulderAxis: CGFloat
    let shoulderControlAxis: CGFloat
    let outlineWidth: CGFloat
    let shadowOffset: CGFloat
    let shadowBlur: CGFloat

    init?(start: CGPoint, end: CGPoint, strokeWidth: CGFloat) {
        let stroke = max(strokeWidth, 1)
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = hypot(dx, dy)

        guard length >= max(stroke * 2, 8) else { return nil }

        // The reference shape has roughly these proportions:
        // head length is near full head width, and the shaft sides run straight
        // from the concave shoulders into a sharp triangular tail point.
        let headWidth = min(max(stroke * 12.0, stroke + 28), length * 0.50)
        let headLength = min(headWidth * 0.98, length * 0.46)
        let shaftShoulderWidth = min(max(stroke * 4.9, headWidth * 0.46), headWidth * 0.58)
        let tipEdgeAxis = headLength * 0.035
        let tipEdgeHalfWidth = headWidth * 0.035
        let notchAxis = headLength * 0.90
        let shoulderAxis = headLength * 1.03
        let shoulderControlAxis = headLength * 1.06
        let outlineWidth = min(max(2, headWidth * 0.025), 8)
        let shadowOffset = min(max(4, shaftShoulderWidth * 0.12), 10)
        let shadowBlur = min(max(6, shaftShoulderWidth * 0.13), 12)

        // Axis points from the arrowhead back to the tapered tail. Renderers build the
        // path in tip-relative coordinates so the head can stay stable while the far
        // end collapses to the drag-start tail point.
        let axisX = -dx / length
        let axisY = -dy / length
        let normalX = -axisY
        let normalY = axisX

        self.start = start
        self.tip = end
        self.length = length
        self.axisX = axisX
        self.axisY = axisY
        self.normalX = normalX
        self.normalY = normalY
        self.headLength = headLength
        self.headWidth = headWidth
        self.shaftShoulderWidth = shaftShoulderWidth
        self.tipEdgeAxis = tipEdgeAxis
        self.tipEdgeHalfWidth = tipEdgeHalfWidth
        self.notchAxis = notchAxis
        self.shoulderAxis = shoulderAxis
        self.shoulderControlAxis = shoulderControlAxis
        self.outlineWidth = outlineWidth
        self.shadowOffset = shadowOffset
        self.shadowBlur = shadowBlur
    }

    func point(axis: CGFloat, normal: CGFloat) -> CGPoint {
        CGPoint(
            x: tip.x + axisX * axis + normalX * normal,
            y: tip.y + axisY * axis + normalY * normal
        )
    }
}

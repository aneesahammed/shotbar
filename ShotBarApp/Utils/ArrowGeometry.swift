import CoreGraphics

/// Pure-math description of a Skitch-style arrow shape.
///
/// Coordinate-space contract: `start`, `end`, and `strokeWidth` are all in the consumer's
/// drawing space. This type never flips, scales, or transforms — callers are responsible
/// for mapping pixel-space layer data into their renderer's coordinate system before
/// invoking the initializer.
///
/// The initializer is failable: drags shorter than `max(strokeWidth * 2, 8)` return `nil`
/// so renderers can early-return cleanly on partial gestures or accidental clicks.
struct ArrowGeometry {
    /// Shaft origin (= layer's `start` in drawing space).
    let start: CGPoint
    /// Where the colored shaft stroke terminates. Coincides with the head's flat back
    /// so the line cap hides under the triangle's base.
    let shaftEnd: CGPoint
    /// Arrowhead tip (= layer's `end` in drawing space).
    let tip: CGPoint
    /// Left base corner of the head triangle.
    let leftBase: CGPoint
    /// Right base corner of the head triangle.
    let rightBase: CGPoint
    /// Final clamped head length (≤ `strokeWidth * 4` and ≤ `length * 0.55`).
    let headLength: CGFloat
    /// Final clamped head width (≤ `strokeWidth * 3` and ≤ `length * 0.45`).
    let headWidth: CGFloat

    init?(start: CGPoint, end: CGPoint, strokeWidth: CGFloat) {
        let stroke = max(strokeWidth, 1)
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = hypot(dx, dy)

        guard length >= max(stroke * 2, 8) else { return nil }

        let ux = dx / length
        let uy = dy / length
        let px = -uy
        let py = ux

        let headLength = min(stroke * 4, length * 0.55)
        let headWidth = min(stroke * 3, length * 0.45)
        let halfWidth = headWidth / 2

        let baseCenter = CGPoint(
            x: end.x - ux * headLength,
            y: end.y - uy * headLength
        )

        self.start = start
        self.tip = end
        self.shaftEnd = baseCenter
        self.leftBase = CGPoint(
            x: baseCenter.x + px * halfWidth,
            y: baseCenter.y + py * halfWidth
        )
        self.rightBase = CGPoint(
            x: baseCenter.x - px * halfWidth,
            y: baseCenter.y - py * halfWidth
        )
        self.headLength = headLength
        self.headWidth = headWidth
    }
}

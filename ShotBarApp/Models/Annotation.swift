import Foundation
import CoreGraphics

struct AnnotationDocument: Codable, Equatable {
    var basePixelSize: CGSize
    var pixelsPerPoint: CGFloat
    var layers: [AnnotationLayer] = []
    var crop: CGRect?
}

enum AnnotationLayer: Codable, Equatable, Identifiable {
    case arrow(ArrowLayer)
    case text(TextLayer)
    case blur(BlurLayer)

    var id: UUID {
        switch self {
        case .arrow(let layer): return layer.id
        case .text(let layer): return layer.id
        case .blur(let layer): return layer.id
        }
    }

    var bounds: CGRect {
        switch self {
        case .arrow(let layer):
            // Pad for the Skitch silhouette's footprint:
            //   - headWidth is intentionally huge (about stroke * 12 before length clamps)
            //   - the tail collapses to a sharp point at the start point
            //   - outline + shadow extend outside the filled silhouette
            let padding = layer.style.strokeWidth * 7 + 24
            return CGRect(
                x: min(layer.start.x, layer.end.x),
                y: min(layer.start.y, layer.end.y),
                width: abs(layer.start.x - layer.end.x),
                height: abs(layer.start.y - layer.end.y)
            ).insetBy(dx: -padding, dy: -padding)
        case .text(let layer):
            return layer.rect
        case .blur(let layer):
            return layer.rect
        }
    }
}

struct AnnotationStyle: Codable, Equatable {
    var color: AnnotationColor
    var strokeWidth: CGFloat
}

struct ArrowLayer: Codable, Equatable {
    var id = UUID()
    var start: CGPoint
    var end: CGPoint
    var style: AnnotationStyle
    /// Deprecated. Head dimensions are now derived from `style.strokeWidth` at render time
    /// via `ArrowGeometry`. Field is retained for `Codable` compatibility with previously
    /// persisted documents and ignored by both renderers.
    var headSize: CGFloat
}

struct TextLayer: Codable, Equatable {
    var id = UUID()
    var text: String
    var rect: CGRect
    var style: AnnotationStyle
    var fontSize: CGFloat
}

struct BlurLayer: Codable, Equatable {
    var id = UUID()
    var rect: CGRect
    var mode: AnnotationBlurMode
    var radius: CGFloat
    var pixelScale: CGFloat
}

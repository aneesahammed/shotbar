import SwiftUI
import AppKit

extension AnnotationColor {
    var nsColor: NSColor {
        switch self {
        case .red: return .systemRed
        case .yellow: return .systemYellow
        case .green: return .systemGreen
        case .blue: return .systemBlue
        case .pink: return .systemPink
        case .orange: return .systemOrange
        case .white: return .white
        case .black: return .black
        }
    }

    var swiftUIColor: Color {
        Color(nsColor: nsColor)
    }

    var arrowFillNSColor: NSColor {
        switch self {
        case .red: return NSColor(calibratedRed: 1.00, green: 0.16, blue: 0.16, alpha: 1)
        case .yellow: return NSColor(calibratedRed: 1.00, green: 0.84, blue: 0.04, alpha: 1)
        case .green: return NSColor(calibratedRed: 0.18, green: 0.82, blue: 0.35, alpha: 1)
        case .blue: return NSColor(calibratedRed: 0.04, green: 0.52, blue: 1.00, alpha: 1)
        case .pink: return NSColor(calibratedRed: 1.00, green: 0.17, blue: 0.47, alpha: 1)
        case .orange: return NSColor(calibratedRed: 1.00, green: 0.56, blue: 0.17, alpha: 1)
        case .white: return .white
        case .black: return .black
        }
    }

    var arrowStrokeNSColor: NSColor {
        switch self {
        case .red: return NSColor(calibratedRed: 0.88, green: 0.09, blue: 0.09, alpha: 1)
        case .yellow: return NSColor(calibratedRed: 0.90, green: 0.64, blue: 0.00, alpha: 1)
        case .green: return NSColor(calibratedRed: 0.09, green: 0.62, blue: 0.21, alpha: 1)
        case .blue: return NSColor(calibratedRed: 0.00, green: 0.34, blue: 0.86, alpha: 1)
        case .pink: return NSColor(calibratedRed: 0.94, green: 0.09, blue: 0.41, alpha: 1)
        case .orange: return NSColor(calibratedRed: 0.88, green: 0.36, blue: 0.05, alpha: 1)
        case .white: return NSColor(calibratedWhite: 0.78, alpha: 1)
        case .black: return NSColor(calibratedWhite: 0.08, alpha: 1)
        }
    }
}

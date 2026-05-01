import SwiftUI
import AppKit

extension AnnotationColor {
    var nsColor: NSColor {
        switch self {
        case .red: return .systemRed
        case .yellow: return .systemYellow
        case .green: return .systemGreen
        case .blue: return .systemBlue
        case .white: return .white
        case .black: return .black
        }
    }

    var swiftUIColor: Color {
        Color(nsColor: nsColor)
    }
}

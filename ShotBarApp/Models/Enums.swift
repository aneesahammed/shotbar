import Foundation
import CoreGraphics

// MARK: - App Enums

enum ImageFormat: String, Codable, CaseIterable, Identifiable { 
    case png, jpg
    var id: String { rawValue.uppercased() } 
}

enum Destination: String, Codable, CaseIterable, Identifiable { 
    case file, clipboard
    var id: String { rawValue } 
}

enum PreviewCorner: String, Codable, CaseIterable, Identifiable {
    case topLeft, topRight, bottomLeft, bottomRight
    var id: String { rawValue }

    var label: String {
        switch self {
        case .topLeft: return "Top Left"
        case .topRight: return "Top Right"
        case .bottomLeft: return "Bottom Left"
        case .bottomRight: return "Bottom Right"
        }
    }
}

enum PreviewScreenChoice: String, Codable, CaseIterable, Identifiable {
    case cursorScreen, captureScreen
    var id: String { rawValue }

    var label: String {
        switch self {
        case .cursorScreen: return "Cursor Screen"
        case .captureScreen: return "Capture Screen"
        }
    }
}

enum CaptureKind: String, Codable, CaseIterable, Identifiable {
    case selection = "Selection"
    case window = "Window"
    case screen = "Screen"
    case display = "Display"

    var id: String { rawValue }
}

enum AnnotationToolKind: String, Codable, CaseIterable, Identifiable {
    case arrow, text, blur, crop
    var id: String { rawValue }

    var label: String {
        switch self {
        case .arrow: return "Arrow"
        case .text: return "Text"
        case .blur: return "Blur"
        case .crop: return "Crop"
        }
    }

    var symbolName: String {
        switch self {
        case .arrow: return "arrow.up.right"
        case .text: return "textformat"
        case .blur: return "checkerboard.rectangle"
        case .crop: return "crop"
        }
    }
}

enum AnnotationColor: String, Codable, CaseIterable, Identifiable {
    case red, yellow, green, blue, white, black
    var id: String { rawValue }

    var label: String {
        rawValue.prefix(1).uppercased() + rawValue.dropFirst()
    }
}

enum AnnotationBlurMode: String, Codable, CaseIterable, Identifiable {
    case blur, pixelate
    var id: String { rawValue }

    var label: String {
        switch self {
        case .blur: return "Blur"
        case .pixelate: return "Pixelate"
        }
    }
}

enum HotkeyID: UInt32 { 
    case selection = 1, window = 2, screen = 3 

    var label: String {
        switch self {
        case .selection: return "Selection"
        case .window: return "Active Window"
        case .screen: return "Full Screen"
        }
    }
}

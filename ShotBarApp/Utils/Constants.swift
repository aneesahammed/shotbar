import Foundation
import Carbon.HIToolbox
import CoreGraphics

// MARK: - App Constants

struct AppConstants {
    // UI Constants
    static let menuMinWidth: CGFloat = 360
    static let preferencesWidth: CGFloat = 420
    static let menuPadding: CGFloat = 6
    static let previewMinDuration: TimeInterval = 2
    static let previewMaxDuration: TimeInterval = 15
    static let previewDefaultDuration: TimeInterval = 5
    static let previewThumbnailMaxSide: CGFloat = 240
    static let previewCornerInset: CGFloat = 16
    static let previewNotchExtraInset: CGFloat = 8
    static let editorMinSize = CGSize(width: 800, height: 600)
    static let editorUndoDepth = 50
    
    // Default Hotkeys
    static let defaultSelectionHotkey = UInt32(kVK_F1)
    static let defaultWindowHotkey = UInt32(kVK_F2)
    static let defaultScreenHotkey = UInt32(kVK_F3)
    
    // UserDefaults Keys
    struct UserDefaultsKeys {
        static let selectionHotkey = "selectionHotkey"
        static let windowHotkey = "windowHotkey"
        static let screenHotkey = "screenHotkey"
        static let imageFormat = "imageFormat"
        static let destination = "destination"
        static let soundEnabled = "soundEnabled"
        static let previewEnabled = "previewEnabled"
        static let previewDuration = "previewDuration"
        static let previewCorner = "previewCorner"
        static let previewScreenChoice = "previewScreenChoice"
        static let annotationDefaultColor = "annotationDefaultColor"
        static let annotationDefaultStrokeWidth = "annotationDefaultStrokeWidth"
    }
    
    // File Extensions
    struct FileExtensions {
        static let png = "png"
        static let jpg = "jpg"
    }
}

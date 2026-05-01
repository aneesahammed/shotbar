import Foundation
import CoreGraphics
import Combine

enum AnnotationCommand: Codable, Equatable {
    case addLayer(AnnotationLayer)
    case removeLayer(AnnotationLayer)
    case updateLayer(before: AnnotationLayer, after: AnnotationLayer)
    case setCrop(before: CGRect?, after: CGRect?)
}

final class AnnotationCommandHistory {
    private(set) var undoStack: [AnnotationCommand] = []
    private(set) var redoStack: [AnnotationCommand] = []
    private let depth: Int

    init(depth: Int = AppConstants.editorUndoDepth) {
        self.depth = depth
    }

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    func record(_ command: AnnotationCommand) {
        undoStack.append(command)
        if undoStack.count > depth {
            undoStack.removeFirst()
        }
        redoStack.removeAll()
    }

    func popUndo() -> AnnotationCommand? {
        guard let command = undoStack.popLast() else { return nil }
        redoStack.append(command)
        return command
    }

    func popRedo() -> AnnotationCommand? {
        guard let command = redoStack.popLast() else { return nil }
        undoStack.append(command)
        return command
    }
}

final class AnnotationDocumentModel: ObservableObject {
    @Published var document: AnnotationDocument
    @Published var selectedTool: AnnotationToolKind = .arrow
    @Published var selectedColor: AnnotationColor
    @Published var strokeWidth: CGFloat
    @Published var blurMode: AnnotationBlurMode = .blur
    @Published var isDirty = false
    @Published var isRendering = false
    @Published var lastMessage: String?

    let asset: CaptureAsset
    let baseImage: CGImage
    let history = AnnotationCommandHistory()

    init(asset: CaptureAsset, baseImage: CGImage, prefs: Preferences) {
        self.asset = asset
        self.baseImage = baseImage
        self.selectedColor = prefs.annotationDefaultColor
        self.strokeWidth = prefs.annotationDefaultStrokeWidth
        self.document = AnnotationDocument(
            basePixelSize: asset.pixelSize,
            pixelsPerPoint: asset.pixelsPerPoint
        )
    }

    var canUndo: Bool { history.canUndo }
    var canRedo: Bool { history.canRedo }
    var currentTextFontSize: CGFloat { max(18, strokeWidth * 5) }

    func apply(_ command: AnnotationCommand) {
        apply(command, direction: .forward)
        history.record(command)
        isDirty = true
    }

    func undo() {
        guard let command = history.popUndo() else { return }
        apply(command, direction: .reverse)
        isDirty = true
    }

    func redo() {
        guard let command = history.popRedo() else { return }
        apply(command, direction: .forward)
        isDirty = true
    }

    private enum Direction {
        case forward, reverse
    }

    private func apply(_ command: AnnotationCommand, direction: Direction) {
        objectWillChange.send()
        switch (command, direction) {
        case (.addLayer(let layer), .forward), (.removeLayer(let layer), .reverse):
            document.layers.append(layer)
        case (.addLayer(let layer), .reverse), (.removeLayer(let layer), .forward):
            document.layers.removeAll { $0.id == layer.id }
        case (.updateLayer(_, let after), .forward), (.updateLayer(let after, _), .reverse):
            guard let index = document.layers.firstIndex(where: { $0.id == after.id }) else { return }
            document.layers[index] = after
        case (.setCrop(_, let after), .forward), (.setCrop(let after, _), .reverse):
            document.crop = after
        }
    }
}

import AppKit
import SwiftUI

@MainActor
final class AnnotationEditorWindowController: NSWindowController, NSWindowDelegate {
    private let model: AnnotationDocumentModel
    private let onSave: (AnnotationDocumentModel) async -> Void
    private let onCopy: (AnnotationDocumentModel) async -> Void
    private let onClose: (UUID) -> Void
    private var isClosingAfterDecision = false

    init(
        model: AnnotationDocumentModel,
        onSave: @escaping (AnnotationDocumentModel) async -> Void,
        onCopy: @escaping (AnnotationDocumentModel) async -> Void,
        onClose: @escaping (UUID) -> Void
    ) {
        self.model = model
        self.onSave = onSave
        self.onCopy = onCopy
        self.onClose = onClose

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: AppConstants.editorMinSize.width, height: AppConstants.editorMinSize.height),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Annotate Screenshot"
        window.minSize = AppConstants.editorMinSize
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("ShotBarAnnotationEditor")

        super.init(window: window)
        window.delegate = self
        window.contentView = NSHostingView(
            rootView: AnnotationEditorView(
                model: model,
                onSave: { [weak self] in
                    guard let self else { return }
                    await self.onSave(self.model)
                },
                onCopy: { [weak self] in
                    guard let self else { return }
                    await self.onCopy(self.model)
                },
                onCancel: { [weak self] in
                    self?.window?.performClose(nil)
                }
            )
        )
        window.center()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard model.isDirty, !isClosingAfterDecision else { return true }

        let alert = NSAlert()
        alert.messageText = "Discard annotation changes?"
        alert.informativeText = "Save the annotated screenshot, discard your edits, or continue editing."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Discard")
        alert.addButton(withTitle: "Cancel")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            Task { [weak self] in
                guard let self else { return }
                await self.onSave(self.model)
                if !self.model.isDirty {
                    self.isClosingAfterDecision = true
                    self.window?.close()
                }
            }
            return false
        case .alertSecondButtonReturn:
            isClosingAfterDecision = true
            return true
        default:
            return false
        }
    }

    func windowWillClose(_ notification: Notification) {
        onClose(model.asset.id)
    }
}

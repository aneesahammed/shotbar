import AppKit
import SwiftUI

final class FloatingPreviewPanel: NSPanel {
    private var dismissWorkItem: DispatchWorkItem?
    private var onDismiss: (() -> Void)?
    private let trackingView = PreviewTrackingView()
    private var duration: TimeInterval = AppConstants.previewDefaultDuration

    init(size: NSSize) {
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        level = .statusBar
        hasShadow = true
        collectionBehavior = [.transient, .ignoresCycle, .canJoinAllSpaces]
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
    }

    func setContent<Content: View>(_ view: Content) {
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(origin: .zero, size: frame.size)

        trackingView.subviews.forEach { $0.removeFromSuperview() }
        trackingView.frame = hosting.frame
        trackingView.autoresizingMask = [.width, .height]
        trackingView.onMouseEntered = { [weak self] in self?.pauseDismissal() }
        trackingView.onMouseExited = { [weak self] in self?.scheduleDismissal() }
        trackingView.addSubview(hosting)
        contentView = trackingView
    }

    func show(at frame: NSRect, duration: TimeInterval, onDismiss: @escaping () -> Void) {
        self.duration = duration
        self.onDismiss = onDismiss
        setFrame(frame, display: true)
        alphaValue = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 1 : 0
        orderFrontRegardless()
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            scheduleDismissal()
        } else {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                animator().alphaValue = 1
            } completionHandler: {
                self.scheduleDismissal()
            }
        }
    }

    func closePreview() {
        dismissWorkItem?.cancel()
        dismissWorkItem = nil
        orderOut(nil)
        onDismiss?()
    }

    private func pauseDismissal() {
        dismissWorkItem?.cancel()
        dismissWorkItem = nil
    }

    private func scheduleDismissal() {
        dismissWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                self.closePreview()
                return
            }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.16
                self.animator().alphaValue = 0
            } completionHandler: {
                self.closePreview()
            }
        }
        dismissWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: item)
    }
}

private final class PreviewTrackingView: NSView {
    var onMouseEntered: (() -> Void)?
    var onMouseExited: (() -> Void)?
    private var trackingAreaRef: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaRef {
            removeTrackingArea(trackingAreaRef)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        trackingAreaRef = area
        addTrackingArea(area)
    }

    override func mouseEntered(with event: NSEvent) {
        onMouseEntered?()
    }

    override func mouseExited(with event: NSEvent) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.onMouseExited?()
        }
    }
}

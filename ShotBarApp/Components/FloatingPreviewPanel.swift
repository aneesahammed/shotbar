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

    /// Hosts a SwiftUI view, measures its natural size with width pinned to the configured
    /// upper bound, clamps the measurement to the current screen's visible frame, and
    /// resizes the panel to match. This is what keeps the action row from clipping when
    /// SwiftUI's `VStack` wants more height than the panel's hardcoded `contentRect`.
    func setContent<Content: View>(_ view: Content) {
        let hosting = NSHostingView(rootView: view)

        // Constrain width before measuring; `fittingSize` without a constrained frame
        // returns SwiftUI's ideal size, which can disagree with the eventual panel width.
        // The generous height (10000) leaves SwiftUI room to lay out fully so we can read
        // the natural height back.
        hosting.frame = NSRect(x: 0, y: 0, width: Self.maxWidth, height: 10_000)
        hosting.layoutSubtreeIfNeeded()

        let fitting = hosting.fittingSize
        let clamped = clampToScreen(fitting)
        let finalSize = NSSize(
            width: max(clamped.width, Self.minWidth),
            height: max(clamped.height, Self.minHeight)
        )

        setFrame(NSRect(origin: frame.origin, size: finalSize), display: false)

        trackingView.subviews.forEach { $0.removeFromSuperview() }
        trackingView.frame = NSRect(origin: .zero, size: finalSize)
        trackingView.autoresizingMask = [.width, .height]
        trackingView.onMouseEntered = { [weak self] in self?.pauseDismissal() }
        trackingView.onMouseExited = { [weak self] in self?.scheduleDismissal() }

        hosting.frame = trackingView.bounds
        hosting.autoresizingMask = [.width, .height]
        trackingView.addSubview(hosting)
        contentView = trackingView
    }

    /// Caps the measured size to the active screen's visible frame so the panel never
    /// renders larger than the area available to it (relevant for accessibility-scaled
    /// text on small displays).
    private func clampToScreen(_ size: NSSize) -> NSSize {
        let screen = screenForPanel()
        guard let visible = screen?.visibleFrame else { return size }
        let margin: CGFloat = 16
        return NSSize(
            width: min(size.width, max(Self.minWidth, visible.width - margin * 2)),
            height: min(size.height, max(Self.minHeight, visible.height - margin * 2))
        )
    }

    private func screenForPanel() -> NSScreen? {
        // First-present panels have origin == .zero (set by `init(contentRect:)`); the
        // origin-lookup would then misidentify the active screen on multi-display layouts
        // where global (0,0) lives on a non-primary display (e.g. a left-of-primary
        // arrangement). Prefer NSScreen.main in that case; only fall through to
        // origin-lookup once the panel has been positioned at least once.
        if frame.origin == .zero {
            return NSScreen.main ?? NSScreen.screens.first
        }
        return NSScreen.screens.first(where: { $0.frame.contains(frame.origin) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }

    private static let minWidth: CGFloat = 340
    private static let maxWidth: CGFloat = 380
    private static let minHeight: CGFloat = 120

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

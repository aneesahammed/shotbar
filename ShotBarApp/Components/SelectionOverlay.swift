import AppKit
import QuartzCore

// MARK: - Selection overlay (drag rectangle) — returns rect + screen

final class SelectionOverlay: NSWindow, NSWindowDelegate {
    private var startPoint: CGPoint = .zero
    private var currentPoint: CGPoint = .zero
    private var shapeLayer = CAShapeLayer()
    private var onComplete: ((CGRect?, NSScreen?) -> Void)?
    
    private static var activeOverlays: [SelectionOverlay] = []

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    
    static func present(onComplete: @escaping (CGRect?, NSScreen?) -> Void) {
        activeOverlays = NSScreen.screens.map { screen in
            let w = SelectionOverlay(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false, screen: screen)
            w.onComplete = onComplete
            return w
        }
        activeOverlays.forEach { $0.makeKeyAndOrderFront(nil) }
        NSCursor.crosshair.set()
    }
    
    convenience init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing bufferingType: NSWindow.BackingStoreType, defer flag: Bool, screen: NSScreen) {
        self.init(contentRect: contentRect, styleMask: style, backing: bufferingType, defer: flag)
        isOpaque = false
        backgroundColor = NSColor.black.withAlphaComponent(0.15)
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true
        level = .screenSaver
        collectionBehavior = [.transient, .ignoresCycle]
        delegate = self
        
        let v = SelectionOverlayContentView(frame: contentRect)
        v.wantsLayer = true
        v.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.15).cgColor
        
        shapeLayer.fillRule = .evenOdd
        shapeLayer.fillColor = NSColor.black.withAlphaComponent(0.15).cgColor
        shapeLayer.strokeColor = NSColor.white.withAlphaComponent(0.9).cgColor
        shapeLayer.lineWidth = 2
        // Make the selection rectangle use dotted lines
        shapeLayer.lineDashPattern = [6, 4] // 6 points dash, 4 points gap
        v.layer?.addSublayer(shapeLayer)
        
        contentView = v
    }
    
    override func mouseDown(with event: NSEvent) {
        startPoint = NSEvent.mouseLocation
        currentPoint = startPoint
        updateSelectionPath()
    }
    
    override func mouseDragged(with event: NSEvent) {
        currentPoint = NSEvent.mouseLocation
        updateSelectionPath()
    }
    
    override func mouseUp(with event: NSEvent) {
        currentPoint = NSEvent.mouseLocation
        let rect = normalizedRect(startPoint: startPoint, endPoint: currentPoint)
        cleanup(andCompleteWith: rect.width > 4 && rect.height > 4 ? rect : nil)
    }
    
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Esc
            cleanup(andCompleteWith: nil)
        }
    }
    
    private func updateSelectionPath() {
        guard let contentView = self.contentView else { return }
        
        let rectScreen = normalizedRect(startPoint: startPoint, endPoint: currentPoint)
        
        // Convert from SCREEN → WINDOW space, then use view bounds for the outer path
        let rectWin = self.convertFromScreen(rectScreen)
        let outer = NSBezierPath(rect: contentView.bounds).cgPath
        let inner = NSBezierPath(rect: rectWin).cgPath
        
        let combined = CGMutablePath()
        combined.addPath(outer)
        combined.addPath(inner)
        shapeLayer.path = combined
    }
    
    private func normalizedRect(startPoint: CGPoint, endPoint: CGPoint) -> CGRect {
        let x = min(startPoint.x, endPoint.x)
        let y = min(startPoint.y, endPoint.y)
        let w = abs(startPoint.x - endPoint.x)
        let h = abs(startPoint.y - endPoint.y)
        return CGRect(x: x, y: y, width: w, height: h)
    }
    
    private func cleanup(andCompleteWith rect: CGRect?) {
        let s = self.screen
        SelectionOverlay.activeOverlays.forEach { $0.orderOut(nil) }
        SelectionOverlay.activeOverlays.removeAll()
        onComplete?(rect, s)
        onComplete = nil
    }
}

private final class SelectionOverlayContentView: NSView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}

// MARK: - NSBezierPath Extension

private extension NSBezierPath {
    var cgPath: CGPath {
        let path = CGMutablePath()
        var points = [NSPoint](repeating: .zero, count: 3)
        for i in 0..<elementCount {
            switch element(at: i, associatedPoints: &points) {
            case .moveTo: path.move(to: points[0])
            case .lineTo: path.addLine(to: points[0])
            case .curveTo: path.addCurve(to: points[2], control1: points[0], control2: points[1])
            case .closePath: path.closeSubpath()
            @unknown default: break
            }
        }
        return path
    }
}

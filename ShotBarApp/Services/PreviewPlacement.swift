import AppKit

enum PreviewPlacement {
    static func placement(
        panelSize: CGSize,
        corner: PreviewCorner,
        screenChoice: PreviewScreenChoice,
        cursor: CGPoint,
        screens: [NSScreen],
        originScreenID: CGDirectDisplayID?
    ) -> NSRect {
        let screen = selectedScreen(
            screenChoice: screenChoice,
            cursor: cursor,
            screens: screens,
            originScreenID: originScreenID
        ) ?? NSScreen.main

        let frame = screen?.visibleFrame ?? NSRect(origin: .zero, size: panelSize)
        let inset = AppConstants.previewCornerInset
        let topInset = inset + topNotchInset(for: screen, corner: corner)

        let x: CGFloat
        switch corner {
        case .topLeft, .bottomLeft:
            x = frame.minX + inset
        case .topRight, .bottomRight:
            x = frame.maxX - panelSize.width - inset
        }

        let y: CGFloat
        switch corner {
        case .topLeft, .topRight:
            y = frame.maxY - panelSize.height - topInset
        case .bottomLeft, .bottomRight:
            y = frame.minY + inset
        }

        let proposed = NSRect(origin: CGPoint(x: x, y: y), size: panelSize)
        return clamp(proposed, to: frame.insetBy(dx: 4, dy: 4))
    }

    private static func selectedScreen(
        screenChoice: PreviewScreenChoice,
        cursor: CGPoint,
        screens: [NSScreen],
        originScreenID: CGDirectDisplayID?
    ) -> NSScreen? {
        switch screenChoice {
        case .cursorScreen:
            return screens.first(where: { $0.frame.contains(cursor) }) ?? NSScreen.main
        case .captureScreen:
            if let originScreenID {
                return screens.first { screenID($0) == originScreenID } ?? screens.first(where: { $0.frame.contains(cursor) }) ?? NSScreen.main
            }
            return screens.first(where: { $0.frame.contains(cursor) }) ?? NSScreen.main
        }
    }

    private static func topNotchInset(for screen: NSScreen?, corner: PreviewCorner) -> CGFloat {
        guard corner == .topLeft || corner == .topRight else { return 0 }
        guard let screen, screen.safeAreaInsets.top > 0 else { return 0 }
        return AppConstants.previewNotchExtraInset
    }

    private static func clamp(_ rect: NSRect, to bounds: NSRect) -> NSRect {
        var origin = rect.origin
        origin.x = min(max(origin.x, bounds.minX), max(bounds.minX, bounds.maxX - rect.width))
        origin.y = min(max(origin.y, bounds.minY), max(bounds.minY, bounds.maxY - rect.height))
        return NSRect(origin: origin, size: rect.size)
    }

    private static func screenID(_ screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber).map {
            CGDirectDisplayID($0.uint32Value)
        }
    }
}

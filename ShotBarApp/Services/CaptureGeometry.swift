import CoreGraphics

enum CaptureGeometry {
    static func pixelsPerPoint(
        pointSize: CGSize,
        displayModePixelSize: CGSize?,
        legacyDisplayPixelSize: CGSize,
        backingScaleFactor: CGFloat,
        preferredScale: CGFloat? = nil
    ) -> CGSize {
        CGSize(
            width: pixelScale(
                pointExtent: pointSize.width,
                displayModePixelExtent: displayModePixelSize?.width,
                legacyDisplayPixelExtent: legacyDisplayPixelSize.width,
                backingScaleFactor: backingScaleFactor,
                preferredScale: preferredScale
            ),
            height: pixelScale(
                pointExtent: pointSize.height,
                displayModePixelExtent: displayModePixelSize?.height,
                legacyDisplayPixelExtent: legacyDisplayPixelSize.height,
                backingScaleFactor: backingScaleFactor,
                preferredScale: preferredScale
            )
        )
    }

    static func outputPixelSize(
        pointSize: CGSize,
        displayModePixelSize: CGSize?,
        legacyDisplayPixelSize: CGSize,
        backingScaleFactor: CGFloat,
        preferredScale: CGFloat? = nil
    ) -> CGSize {
        let scale = pixelsPerPoint(
            pointSize: pointSize,
            displayModePixelSize: displayModePixelSize,
            legacyDisplayPixelSize: legacyDisplayPixelSize,
            backingScaleFactor: backingScaleFactor,
            preferredScale: preferredScale
        )

        return CGSize(
            width: max(1, round(pointSize.width * scale.width)),
            height: max(1, round(pointSize.height * scale.height))
        )
    }

    static func cropRect(selection: CGRect, screenFrame: CGRect, scaleX: CGFloat, scaleY: CGFloat) -> CGRect {
        let localX = selection.minX - screenFrame.minX
        let localYFromBottom = selection.minY - screenFrame.minY
        let localYFromTop = screenFrame.height - localYFromBottom - selection.height

        return CGRect(
            x: round(localX * scaleX),
            y: round(localYFromTop * scaleY),
            width: round(selection.width * scaleX),
            height: round(selection.height * scaleY)
        )
    }

    static func clampedCropRect(
        selection: CGRect,
        screenFrame: CGRect,
        scaleX: CGFloat,
        scaleY: CGFloat,
        displayPixelSize: CGSize
    ) -> CGRect {
        let rawRect = cropRect(
            selection: selection,
            screenFrame: screenFrame,
            scaleX: scaleX,
            scaleY: scaleY
        )
        let bounds = CGRect(origin: .zero, size: displayPixelSize)
        return rawRect.intersection(bounds)
    }

    static func displayModePixelSize(for displayID: CGDirectDisplayID) -> CGSize? {
        guard let mode = CGDisplayCopyDisplayMode(displayID) else { return nil }
        let width = CGFloat(mode.pixelWidth)
        let height = CGFloat(mode.pixelHeight)
        guard width > 0, height > 0 else { return nil }
        return CGSize(width: width, height: height)
    }

    static func legacyDisplayPixelSize(for displayID: CGDirectDisplayID) -> CGSize {
        CGSize(
            width: CGFloat(CGDisplayPixelsWide(displayID)),
            height: CGFloat(CGDisplayPixelsHigh(displayID))
        )
    }

    private static func pixelScale(
        pointExtent: CGFloat,
        displayModePixelExtent: CGFloat?,
        legacyDisplayPixelExtent: CGFloat,
        backingScaleFactor: CGFloat,
        preferredScale: CGFloat?
    ) -> CGFloat {
        guard pointExtent > 0 else { return max(backingScaleFactor, 1) }

        var candidates = [CGFloat]()

        if let preferredScale, preferredScale.isFinite, preferredScale > 0 {
            candidates.append(preferredScale)
        }
        if let displayModePixelExtent, displayModePixelExtent.isFinite, displayModePixelExtent > 0 {
            candidates.append(displayModePixelExtent / pointExtent)
        }
        if legacyDisplayPixelExtent.isFinite, legacyDisplayPixelExtent > 0 {
            candidates.append(legacyDisplayPixelExtent / pointExtent)
        }
        if backingScaleFactor.isFinite, backingScaleFactor > 0 {
            candidates.append(backingScaleFactor)
        }

        return max(candidates.max() ?? 1, 1)
    }
}

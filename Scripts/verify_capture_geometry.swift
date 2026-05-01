import CoreGraphics
import Foundation

@main
struct CaptureGeometryVerifier {
    static func main() {
        let pointSize = CGSize(width: 2048, height: 1152)
        let legacyDisplayPixels = CGSize(width: 2048, height: 1152)
        let displayModePixels = CGSize(width: 4096, height: 2304)

        let size = CaptureGeometry.outputPixelSize(
            pointSize: pointSize,
            displayModePixelSize: displayModePixels,
            legacyDisplayPixelSize: legacyDisplayPixels,
            backingScaleFactor: 2
        )

        expect(size.width == 4096, "expected HiDPI width to use display mode pixel width, got \(size.width)")
        expect(size.height == 2304, "expected HiDPI height to use display mode pixel height, got \(size.height)")

        let crop = CaptureGeometry.cropRect(
            selection: CGRect(x: 120, y: 100, width: 400, height: 250),
            screenFrame: CGRect(x: 0, y: 0, width: 2048, height: 1152),
            scaleX: 2,
            scaleY: 2
        )

        expect(crop == CGRect(x: 240, y: 1604, width: 800, height: 500), "unexpected crop rect: \(String(describing: crop))")

        let secondaryCrop = CaptureGeometry.cropRect(
            selection: CGRect(x: 2200, y: -50, width: 300, height: 200),
            screenFrame: CGRect(x: 2048, y: -97, width: 1920, height: 1080),
            scaleX: 2,
            scaleY: 2
        )

        expect(secondaryCrop == CGRect(x: 304, y: 1666, width: 600, height: 400), "unexpected secondary-display crop rect: \(String(describing: secondaryCrop))")

        let clampedLeftEdgeCrop = CaptureGeometry.clampedCropRect(
            selection: CGRect(x: 2047.75, y: -50, width: 300, height: 200),
            screenFrame: CGRect(x: 2048, y: -97, width: 1920, height: 1080),
            scaleX: 2,
            scaleY: 2,
            displayPixelSize: CGSize(width: 3840, height: 2160)
        )

        expect(clampedLeftEdgeCrop == CGRect(x: 0, y: 1666, width: 599, height: 400), "unexpected clamped left-edge crop: \(String(describing: clampedLeftEdgeCrop))")

        let clampedRightEdgeCrop = CaptureGeometry.clampedCropRect(
            selection: CGRect(x: 2048 + 1800, y: -50, width: 121, height: 200),
            screenFrame: CGRect(x: 2048, y: -97, width: 1920, height: 1080),
            scaleX: 2,
            scaleY: 2,
            displayPixelSize: CGSize(width: 3840, height: 2160)
        )

        expect(clampedRightEdgeCrop == CGRect(x: 3600, y: 1666, width: 240, height: 400), "unexpected clamped right-edge crop: \(String(describing: clampedRightEdgeCrop))")

        print("capture geometry checks passed")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            FileHandle.standardError.write("FAIL: \(message)\n".data(using: .utf8)!)
            exit(1)
        }
    }
}

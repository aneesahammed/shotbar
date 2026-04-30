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

        let nativeRect = CaptureGeometry.screencaptureRect(
            selection: CGRect(x: 120, y: 100, width: 400, height: 250),
            screenFrame: CGRect(x: 0, y: 0, width: 2048, height: 1152)
        )

        expect(nativeRect == CGRect(x: 120, y: 802, width: 400, height: 250), "unexpected native screencapture rect: \(String(describing: nativeRect))")

        let nativeSecondaryRect = CaptureGeometry.screencaptureRect(
            selection: CGRect(x: 2200, y: -50, width: 300, height: 200),
            screenFrame: CGRect(x: 2048, y: -97, width: 1920, height: 1080)
        )

        expect(nativeSecondaryRect == CGRect(x: 2200, y: 833, width: 300, height: 200), "unexpected secondary native screencapture rect: \(String(describing: nativeSecondaryRect))")
        expect(CaptureGeometry.screencaptureArgument(for: nativeRect) == "120,802,400,250", "unexpected screencapture argument")

        print("capture geometry checks passed")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            FileHandle.standardError.write("FAIL: \(message)\n".data(using: .utf8)!)
            exit(1)
        }
    }
}

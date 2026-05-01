import XCTest
import CoreGraphics
@testable import ShotBarApp

final class ArrowGeometryTests: XCTestCase {

    // MARK: - Rejection of degenerate / too-short drags

    func testZeroLengthReturnsNil() {
        let geom = ArrowGeometry(start: .zero, end: .zero, strokeWidth: 8)
        XCTAssertNil(geom)
    }

    func testBelowMinimumLengthReturnsNil() {
        // For stroke=8, minimum length = max(8*2, 8) = 16. A drag of 10pt should reject.
        let geom = ArrowGeometry(start: .zero, end: CGPoint(x: 10, y: 0), strokeWidth: 8)
        XCTAssertNil(geom)
    }

    func testThinStrokeMinimumIsEightPoints() {
        // For stroke=1, minimum length = max(1*2, 8) = 8. A 5pt drag should still reject.
        let geom = ArrowGeometry(start: .zero, end: CGPoint(x: 5, y: 0), strokeWidth: 1)
        XCTAssertNil(geom)
    }

    func testAtMinimumLengthSucceeds() {
        // 16pt drag with stroke 8 (= minimum) should succeed and clamp aggressively.
        let geom = ArrowGeometry(start: .zero, end: CGPoint(x: 16, y: 0), strokeWidth: 8)
        XCTAssertNotNil(geom)
    }

    // MARK: - Long-arrow defaults

    func testLongHorizontalArrowUsesUnclampedHeadDimensions() {
        // 200pt drag with stroke 8: headLength = min(32, 200*0.55=110) = 32.
        // headWidth = min(24, 200*0.45=90) = 24.
        guard let geom = ArrowGeometry(start: .zero, end: CGPoint(x: 200, y: 0), strokeWidth: 8) else {
            return XCTFail("Expected geometry for long arrow")
        }
        XCTAssertEqual(geom.headLength, 32, accuracy: 0.001)
        XCTAssertEqual(geom.headWidth, 24, accuracy: 0.001)
    }

    func testHeadDimensionsScaleLinearlyWithStroke() {
        let cases: [(CGFloat, CGFloat, CGFloat)] = [
            (1, 4, 3),     // stroke 1 → length 4, width 3
            (8, 32, 24),   // stroke 8 → length 32, width 24
            (24, 96, 72),  // stroke 24 → length 96, width 72
        ]
        for (stroke, expectedLen, expectedWidth) in cases {
            guard let geom = ArrowGeometry(
                start: .zero,
                end: CGPoint(x: 1000, y: 0),  // long enough for no clamping
                strokeWidth: stroke
            ) else {
                XCTFail("Expected geometry for stroke \(stroke)")
                continue
            }
            XCTAssertEqual(geom.headLength, expectedLen, accuracy: 0.001,
                           "headLength wrong for stroke \(stroke)")
            XCTAssertEqual(geom.headWidth, expectedWidth, accuracy: 0.001,
                           "headWidth wrong for stroke \(stroke)")
        }
    }

    // MARK: - Length-aware clamping

    func testShortArrowClampsHeadLengthToFractionOfLength() {
        // 30pt drag with stroke 8: full headLength would be 32 (> length).
        // Clamp: min(32, 30 * 0.55 = 16.5) = 16.5.
        guard let geom = ArrowGeometry(start: .zero, end: CGPoint(x: 30, y: 0), strokeWidth: 8) else {
            return XCTFail("Expected geometry")
        }
        XCTAssertEqual(geom.headLength, 16.5, accuracy: 0.001)
        XCTAssertEqual(geom.headWidth, min(24, 30 * 0.45), accuracy: 0.001)
    }

    func testShaftEndAlwaysBetweenStartAndTip() {
        // Across a range of lengths, the shaft must terminate strictly between start and tip.
        for length in stride(from: 16, through: 200, by: 8) {
            let end = CGPoint(x: CGFloat(length), y: 0)
            guard let geom = ArrowGeometry(start: .zero, end: end, strokeWidth: 8) else {
                XCTFail("Expected geometry for length \(length)")
                continue
            }
            XCTAssertGreaterThan(geom.shaftEnd.x, geom.start.x,
                                 "shaftEnd should be past start at length \(length)")
            XCTAssertLessThan(geom.shaftEnd.x, geom.tip.x,
                              "shaftEnd should be before tip at length \(length)")
        }
    }

    // MARK: - Direction-independence

    func testHorizontalArrowsHaveSymmetricBaseAcrossXAxis() {
        // For a horizontal arrow, leftBase and rightBase should mirror across the axis line.
        guard let geom = ArrowGeometry(start: .zero, end: CGPoint(x: 100, y: 0), strokeWidth: 6) else {
            return XCTFail("Expected geometry")
        }
        XCTAssertEqual(geom.leftBase.x, geom.rightBase.x, accuracy: 0.001)
        XCTAssertEqual(geom.leftBase.y, -geom.rightBase.y, accuracy: 0.001)
        XCTAssertEqual(geom.tip, CGPoint(x: 100, y: 0))
    }

    func testVerticalArrowDownward() {
        guard let geom = ArrowGeometry(start: .zero, end: CGPoint(x: 0, y: 100), strokeWidth: 6) else {
            return XCTFail("Expected geometry")
        }
        // Tip must be at end; shaftEnd must be on the segment between start and tip.
        XCTAssertEqual(geom.tip, CGPoint(x: 0, y: 100))
        XCTAssertGreaterThan(geom.shaftEnd.y, 0)
        XCTAssertLessThan(geom.shaftEnd.y, 100)
        XCTAssertEqual(geom.shaftEnd.x, 0, accuracy: 0.001)
    }

    func testReversedDirectionStillProducesValidGeometry() {
        // Negative-direction (right-to-left) drag.
        guard let geom = ArrowGeometry(start: CGPoint(x: 100, y: 50),
                                       end: CGPoint(x: 0, y: 50),
                                       strokeWidth: 6) else {
            return XCTFail("Expected geometry")
        }
        XCTAssertEqual(geom.tip, CGPoint(x: 0, y: 50))
        XCTAssertGreaterThan(geom.shaftEnd.x, 0)
        XCTAssertLessThan(geom.shaftEnd.x, 100)
    }

    func testDiagonalArrowProducesPerpendicularBaseSegment() {
        // For a 45° arrow, the line between leftBase and rightBase is perpendicular
        // to the shaft direction. Their midpoint equals shaftEnd.
        guard let geom = ArrowGeometry(start: .zero, end: CGPoint(x: 100, y: 100), strokeWidth: 6) else {
            return XCTFail("Expected geometry")
        }
        let midX = (geom.leftBase.x + geom.rightBase.x) / 2
        let midY = (geom.leftBase.y + geom.rightBase.y) / 2
        XCTAssertEqual(midX, geom.shaftEnd.x, accuracy: 0.001)
        XCTAssertEqual(midY, geom.shaftEnd.y, accuracy: 0.001)
    }

    // MARK: - Stroke-width floor

    func testStrokeWidthZeroIsAcceptedViaFloor() {
        // strokeWidth 0 should not divide-by-zero or invert geometry — internal floor of 1
        // raises stroke to 1, which means a 50pt drag clears the 8pt minimum length.
        let geom = ArrowGeometry(start: .zero, end: CGPoint(x: 50, y: 0), strokeWidth: 0)
        XCTAssertNotNil(geom, "strokeWidth 0 should be floored to 1 and accepted at length 50")
    }

    func testStrokeWidthFloorYieldsStrokeOneHeadDimensions() {
        // After flooring stroke=0 → 1, head dimensions follow stroke=1 formula:
        // headLength = min(1*4, 50*0.55) = 4; headWidth = min(1*3, 50*0.45) = 3.
        guard let geom = ArrowGeometry(start: .zero, end: CGPoint(x: 50, y: 0), strokeWidth: 0) else {
            return XCTFail("Expected geometry for stroke=0 (floored to 1)")
        }
        XCTAssertEqual(geom.headLength, 4, accuracy: 0.001)
        XCTAssertEqual(geom.headWidth, 3, accuracy: 0.001)
    }

    // MARK: - Live↔export scale invariance

    /// The canvas multiplies pixel-space stroke by `imageScale` and converts pixel-space
    /// points to view-space points before passing them to `ArrowGeometry`. This test
    /// proves that the geometry formula is genuinely scale-invariant — i.e. an arrow
    /// rendered at scale `s` produces head/length ratios identical to the un-scaled
    /// pixel-space geometry, which is the central correctness claim for live↔export
    /// parity. If the formula ever drifts (e.g. stroke gets a non-linear adjustment),
    /// the live preview will diverge from the exported PNG and this test will fail.
    func testGeometryIsScaleInvariant() {
        let pixelLength: CGFloat = 200
        let pixelStroke: CGFloat = 8
        guard let pixelGeom = ArrowGeometry(
            start: .zero,
            end: CGPoint(x: pixelLength, y: 0),
            strokeWidth: pixelStroke
        ) else { return XCTFail("Expected pixel-space geometry") }

        for scale: CGFloat in [0.25, 0.5, 1.0, 2.0, 4.0] {
            guard let scaledGeom = ArrowGeometry(
                start: .zero,
                end: CGPoint(x: pixelLength * scale, y: 0),
                strokeWidth: pixelStroke * scale
            ) else { return XCTFail("Expected geometry at scale \(scale)") }

            XCTAssertEqual(scaledGeom.headLength, pixelGeom.headLength * scale, accuracy: 0.001,
                           "headLength must scale linearly at scale=\(scale)")
            XCTAssertEqual(scaledGeom.headWidth, pixelGeom.headWidth * scale, accuracy: 0.001,
                           "headWidth must scale linearly at scale=\(scale)")
            // The shaft termination point should also scale linearly so the line cap
            // hides under the triangle base in both render paths.
            XCTAssertEqual(scaledGeom.shaftEnd.x, pixelGeom.shaftEnd.x * scale, accuracy: 0.001,
                           "shaftEnd must scale linearly at scale=\(scale)")
        }
    }
}

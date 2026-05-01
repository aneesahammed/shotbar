import XCTest
import CoreGraphics
@testable import ShotBarApp

final class ArrowGeometryTests: XCTestCase {

    func testZeroLengthReturnsNil() {
        XCTAssertNil(ArrowGeometry(start: .zero, end: .zero, strokeWidth: 8))
    }

    func testBelowMinimumLengthReturnsNil() {
        XCTAssertNil(ArrowGeometry(start: .zero, end: CGPoint(x: 10, y: 0), strokeWidth: 8))
    }

    func testAtMinimumLengthSucceeds() {
        XCTAssertNotNil(ArrowGeometry(start: .zero, end: CGPoint(x: 16, y: 0), strokeWidth: 8))
    }

    func testLongArrowUsesSvgBlockArrowProportions() {
        guard let geom = ArrowGeometry(start: .zero, end: CGPoint(x: 800, y: 0), strokeWidth: 8) else {
            return XCTFail("Expected geometry")
        }

        XCTAssertEqual(geom.headWidth, 96, accuracy: 0.001)
        XCTAssertEqual(geom.headLength, 94.08, accuracy: 0.001)
        XCTAssertEqual(geom.shaftShoulderWidth, 44.16, accuracy: 0.001)
        XCTAssertEqual(geom.outlineWidth, 2.4, accuracy: 0.001)
        XCTAssertEqual(geom.shadowOffset, 5.2992, accuracy: 0.001)
        XCTAssertEqual(geom.shadowBlur, 6, accuracy: 0.001)
    }

    func testLargeStrokeScalesTheWholeBlockArrow() {
        guard let geom = ArrowGeometry(start: .zero, end: CGPoint(x: 1000, y: 0), strokeWidth: 24) else {
            return XCTFail("Expected geometry")
        }

        XCTAssertEqual(geom.headWidth, 288, accuracy: 0.001)
        XCTAssertEqual(geom.headLength, 282.24, accuracy: 0.001)
        XCTAssertEqual(geom.shaftShoulderWidth, 132.48, accuracy: 0.001)
        XCTAssertEqual(geom.outlineWidth, 7.2, accuracy: 0.001)
        XCTAssertEqual(geom.shadowOffset, 10, accuracy: 0.001)
        XCTAssertEqual(geom.shadowBlur, 12, accuracy: 0.001)
    }

    func testShortArrowClampsToLengthButKeepsBlockShape() {
        guard let geom = ArrowGeometry(start: .zero, end: CGPoint(x: 60, y: 0), strokeWidth: 12) else {
            return XCTFail("Expected geometry")
        }

        XCTAssertEqual(geom.headWidth, 30, accuracy: 0.001)
        XCTAssertEqual(geom.headLength, 27.6, accuracy: 0.001)
        XCTAssertLessThan(geom.headLength, geom.length)
        XCTAssertLessThan(geom.shaftShoulderWidth, geom.headWidth)
    }

    func testPointMappingAnchorsTipAndTail() {
        let start = CGPoint(x: 20, y: 40)
        let end = CGPoint(x: 220, y: 40)
        guard let geom = ArrowGeometry(start: start, end: end, strokeWidth: 10) else {
            return XCTFail("Expected geometry")
        }

        XCTAssertEqual(geom.point(axis: 0, normal: 0).x, end.x, accuracy: 0.001)
        XCTAssertEqual(geom.point(axis: 0, normal: 0).y, end.y, accuracy: 0.001)
        XCTAssertEqual(geom.point(axis: geom.length, normal: 0).x, start.x, accuracy: 0.001)
        XCTAssertEqual(geom.point(axis: geom.length, normal: 0).y, start.y, accuracy: 0.001)
    }

    func testTailPointIsExactlyAtDragStart() {
        let start = CGPoint(x: 20, y: 40)
        let end = CGPoint(x: 220, y: 40)
        guard let geom = ArrowGeometry(start: start, end: end, strokeWidth: 10) else {
            return XCTFail("Expected geometry")
        }

        let tailTip = geom.point(axis: geom.length, normal: 0)

        XCTAssertEqual(tailTip.x, start.x, accuracy: 0.001)
        XCTAssertEqual(tailTip.y, start.y, accuracy: 0.001)
        XCTAssertEqual(geom.point(axis: geom.length, normal: -geom.shaftShoulderWidth / 2).x, start.x, accuracy: 0.001)
        XCTAssertEqual(geom.point(axis: geom.length, normal: geom.shaftShoulderWidth / 2).x, start.x, accuracy: 0.001)
    }

    func testSymmetricOffsetsStayPerpendicularToAxis() {
        guard let geom = ArrowGeometry(start: .zero, end: CGPoint(x: 100, y: 100), strokeWidth: 10) else {
            return XCTFail("Expected geometry")
        }

        let axis = geom.headLength
        let half = geom.headWidth / 2
        let upper = geom.point(axis: axis, normal: -half)
        let lower = geom.point(axis: axis, normal: half)
        let midpoint = CGPoint(x: (upper.x + lower.x) / 2, y: (upper.y + lower.y) / 2)
        let center = geom.point(axis: axis, normal: 0)

        XCTAssertEqual(midpoint.x, center.x, accuracy: 0.001)
        XCTAssertEqual(midpoint.y, center.y, accuracy: 0.001)
        XCTAssertEqual(hypot(upper.x - lower.x, upper.y - lower.y), geom.headWidth, accuracy: 0.001)
    }

    func testStrokeWidthZeroIsAcceptedViaFloor() {
        XCTAssertNotNil(ArrowGeometry(start: .zero, end: CGPoint(x: 50, y: 0), strokeWidth: 0))
    }

    func testTypicalDimensionsScaleLinearly() {
        let pixelLength: CGFloat = 300
        let pixelStroke: CGFloat = 8
        guard let pixelGeom = ArrowGeometry(
            start: .zero,
            end: CGPoint(x: pixelLength, y: 0),
            strokeWidth: pixelStroke
        ) else { return XCTFail("Expected pixel-space geometry") }

        for scale: CGFloat in [0.5, 1.0, 2.0, 4.0] {
            guard let scaledGeom = ArrowGeometry(
                start: .zero,
                end: CGPoint(x: pixelLength * scale, y: 0),
                strokeWidth: pixelStroke * scale
            ) else { return XCTFail("Expected geometry at scale \(scale)") }

            XCTAssertEqual(scaledGeom.headWidth, pixelGeom.headWidth * scale, accuracy: 0.001)
            XCTAssertEqual(scaledGeom.headLength, pixelGeom.headLength * scale, accuracy: 0.001)
            XCTAssertEqual(scaledGeom.shaftShoulderWidth, pixelGeom.shaftShoulderWidth * scale, accuracy: 0.001)
        }
    }
}

import AppKit
import XCTest
@testable import ShotBarApp

@MainActor
final class SelectionOverlayTests: XCTestCase {
    func testSelectionOverlayCanBecomeKeyWithoutBecomingMain() {
        let overlay = SelectionOverlay(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
            styleMask: .borderless,
            backing: .buffered,
            defer: true
        )

        XCTAssertTrue(overlay.canBecomeKey)
        XCTAssertFalse(overlay.canBecomeMain)
    }
}

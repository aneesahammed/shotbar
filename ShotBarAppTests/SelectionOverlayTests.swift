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

    func testSelectionOverlayAcceptsFirstMouseForImmediateDrag() throws {
        let screen = try XCTUnwrap(NSScreen.screens.first)
        let overlay = SelectionOverlay(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
            styleMask: .borderless,
            backing: .buffered,
            defer: true,
            screen: screen
        )

        XCTAssertTrue(overlay.contentView?.acceptsFirstMouse(for: nil) ?? false)
    }
}

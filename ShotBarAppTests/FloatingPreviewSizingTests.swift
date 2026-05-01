import XCTest
import SwiftUI
import AppKit
@testable import ShotBarApp

/// Verifies that `FloatingPreviewPanel.setContent(_:)` measures the SwiftUI content's
/// `fittingSize` and resizes the panel to match — the bug that caused the action-button
/// row to clip in the previous version where the panel used a hardcoded 174/184 height.
@MainActor
final class FloatingPreviewSizingTests: XCTestCase {

    func testPanelResizesToContentHeight() throws {
        // Use a target height that fits comfortably under any plausible Mac display
        // (the screen-frame clamp would silently shrink the panel otherwise and turn
        // this assertion into a flake).
        let targetHeight: CGFloat = 320
        try requireScreenAtLeast(height: targetHeight + 40)

        let panel = FloatingPreviewPanel(size: NSSize(width: 380, height: 240))
        defer { panel.close() }

        let tallContent = FixedSizeView(width: 340, height: targetHeight, color: .red)
        panel.setContent(tallContent)

        XCTAssertEqual(panel.frame.size.height, targetHeight, accuracy: 1.0,
                       "Panel should resize to match SwiftUI content height")
        XCTAssertEqual(panel.frame.size.width, 340, accuracy: 1.0,
                       "Panel should resize to match SwiftUI content width")
    }

    func testPanelEnforcesMinimumHeight() {
        let panel = FloatingPreviewPanel(size: NSSize(width: 380, height: 240))
        defer { panel.close() }

        // Tiny content — under the 120pt safety floor.
        let tinyContent = FixedSizeView(width: 100, height: 40, color: .blue)
        panel.setContent(tinyContent)

        XCTAssertGreaterThanOrEqual(panel.frame.size.height, 120,
                                    "Panel should enforce minimum height floor")
        XCTAssertGreaterThanOrEqual(panel.frame.size.width, 340,
                                    "Panel should enforce minimum width floor")
    }

    func testPanelClampsToScreenVisibleFrame() throws {
        guard let visible = NSScreen.main?.visibleFrame else {
            throw XCTSkip("Test requires a main screen")
        }

        let panel = FloatingPreviewPanel(size: NSSize(width: 380, height: 240))
        defer { panel.close() }

        // Content larger than any plausible screen.
        let oversizedContent = FixedSizeView(width: 5000, height: 5000, color: .green)
        panel.setContent(oversizedContent)

        // Margins are 16pt on each side per FloatingPreviewPanel.clampToScreen.
        let maxAllowedHeight = visible.height - 32
        let maxAllowedWidth = visible.width - 32
        XCTAssertLessThanOrEqual(panel.frame.size.height, maxAllowedHeight + 1,
                                 "Panel height must not exceed screen visibleFrame minus margins")
        XCTAssertLessThanOrEqual(panel.frame.size.width, maxAllowedWidth + 1,
                                 "Panel width must not exceed screen visibleFrame minus margins")
    }

    func testRepeatedSetContentResizesEachTime() throws {
        let secondHeight: CGFloat = 280
        try requireScreenAtLeast(height: secondHeight + 40)

        let panel = FloatingPreviewPanel(size: NSSize(width: 380, height: 240))
        defer { panel.close() }

        panel.setContent(FixedSizeView(width: 340, height: 180, color: .yellow))
        let firstHeight = panel.frame.size.height

        panel.setContent(FixedSizeView(width: 340, height: secondHeight, color: .orange))
        let observedSecond = panel.frame.size.height

        XCTAssertGreaterThan(observedSecond, firstHeight,
                             "Panel should pick up the new content size on each setContent call")
        XCTAssertEqual(observedSecond, secondHeight, accuracy: 1.0)
    }

    // MARK: - Helpers

    /// Skips the test when the main display's `visibleFrame` is too small for the size
    /// being asserted (the `clampToScreen` upstream would otherwise cap the panel below
    /// the asserted dimension and produce a misleading failure).
    private func requireScreenAtLeast(height required: CGFloat) throws {
        let visible = NSScreen.main?.visibleFrame.height ?? 0
        guard visible >= required else {
            throw XCTSkip("Test requires NSScreen.main.visibleFrame.height >= \(required); got \(visible)")
        }
    }
}

// MARK: - Test fixture

/// SwiftUI view that always reports a fixed `fittingSize`. Used as a stand-in for
/// `FloatingPreviewView` so panel-sizing logic can be tested without spinning up a
/// full `PreviewCoordinator` graph.
private struct FixedSizeView: View {
    let width: CGFloat
    let height: CGFloat
    let color: Color

    var body: some View {
        color.frame(width: width, height: height)
    }
}

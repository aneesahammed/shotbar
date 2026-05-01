import XCTest
@testable import ShotBarApp

final class PreferencesPersistenceTests: XCTestCase {
    func testPreviewAndAnnotationPreferencesRoundTrip() {
        let suiteName = "ShotBarAppTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let prefs = Preferences(defaults: defaults)
        prefs.previewEnabled = false
        prefs.previewDuration = 9
        prefs.previewCorner = .topLeft
        prefs.previewScreenChoice = .captureScreen
        prefs.annotationDefaultColor = .blue
        prefs.annotationDefaultStrokeWidth = 11

        XCTAssertEqual(
            defaults.bool(forKey: AppConstants.UserDefaultsKeys.previewEnabled),
            false,
            "Stored previewEnabled should be false; prefs=\(prefs.previewEnabled), object=\(String(describing: defaults.object(forKey: AppConstants.UserDefaultsKeys.previewEnabled)))"
        )

        let restored = Preferences(defaults: defaults)
        XCTAssertFalse(restored.previewEnabled)
        XCTAssertEqual(restored.previewDuration, 9)
        XCTAssertEqual(restored.previewCorner, .topLeft)
        XCTAssertEqual(restored.previewScreenChoice, .captureScreen)
        XCTAssertEqual(restored.annotationDefaultColor, .blue)
        XCTAssertEqual(restored.annotationDefaultStrokeWidth, 11)
    }
}

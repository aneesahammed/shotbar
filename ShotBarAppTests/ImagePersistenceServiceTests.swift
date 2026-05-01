import XCTest
@testable import ShotBarApp

final class ImagePersistenceServiceTests: XCTestCase {
    func testNextAvailableURLAddsCounterAfterAnnotatedCollision() throws {
        let suiteName = "ShotBarAppTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let service = ImagePersistenceService(prefs: Preferences(defaults: defaults))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let first = directory.appendingPathComponent("Screenshot Test (annotated)").appendingPathExtension("png")
        FileManager.default.createFile(atPath: first.path, contents: Data())

        let available = service.nextAvailableURL(in: directory, baseName: "Screenshot Test (annotated)", extension: "png")
        XCTAssertEqual(available.lastPathComponent, "Screenshot Test (annotated) (2).png")
    }
}

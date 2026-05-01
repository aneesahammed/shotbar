import Foundation
import CoreGraphics

enum PersistenceResult: Equatable {
    case copied
    case saved(URL)
    case failed(String)

    var savedURL: URL? {
        if case .saved(let url) = self { return url }
        return nil
    }

    var failureMessage: String? {
        if case .failed(let message) = self { return message }
        return nil
    }
}

struct SaveOptions {
    var baseName: String
    var suffix: String
    var format: ImageFormat
    var showToast: Bool
    var playSound: Bool
}

struct RenderedImageMetadata {
    let pixelsPerPoint: CGFloat
}

struct CaptureAsset: Identifiable, Equatable {
    let id: UUID
    let cacheURL: URL
    let thumbnail: CGImage
    let kind: CaptureKind
    let createdAt: Date
    let baseName: String
    let pixelsPerPoint: CGFloat
    let originScreenID: CGDirectDisplayID?
    let pixelSize: CGSize
    var originalSavedURL: URL?
    var initialResult: PersistenceResult?

    static func == (lhs: CaptureAsset, rhs: CaptureAsset) -> Bool {
        lhs.id == rhs.id
    }
}

struct CaptureBatch: Identifiable, Equatable {
    let id: UUID
    var assets: [CaptureAsset]
    let createdAt: Date

    init(id: UUID = UUID(), assets: [CaptureAsset], createdAt: Date = Date()) {
        self.id = id
        self.assets = assets
        self.createdAt = createdAt
    }

    static func == (lhs: CaptureBatch, rhs: CaptureBatch) -> Bool {
        lhs.id == rhs.id && lhs.assets == rhs.assets
    }
}

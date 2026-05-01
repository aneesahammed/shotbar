import AppKit
import Foundation

@MainActor
final class CaptureStore: ObservableObject {
    @Published private(set) var recentBatches: [CaptureBatch] = []

    private let maxRecent = 3
    private let fileManager: FileManager
    private let cacheRoot: URL
    private var editorRetainCounts: [UUID: Int] = [:]

    init(fileManager: FileManager = .default, cacheRoot: URL? = nil) {
        self.fileManager = fileManager
        if let cacheRoot {
            self.cacheRoot = cacheRoot
        } else {
            let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
                ?? fileManager.temporaryDirectory
            self.cacheRoot = caches
                .appendingPathComponent(AppConstants.CacheDirectories.app, isDirectory: true)
                .appendingPathComponent(AppConstants.CacheDirectories.captures, isDirectory: true)
        }
        purgeStaleCacheOnLaunch()
    }

    var latestBatch: CaptureBatch? {
        recentBatches.first
    }

    func makeAsset(
        from cgImage: CGImage,
        kind: CaptureKind,
        suffix: String,
        pixelsPerPoint: CGFloat,
        originScreenID: CGDirectDisplayID?
    ) async throws -> CaptureAsset {
        try fileManager.createDirectory(at: cacheRoot, withIntermediateDirectories: true, attributes: nil)

        let id = UUID()
        let url = cacheRoot.appendingPathComponent(id.uuidString).appendingPathExtension(AppConstants.FileExtensions.png)
        try ImageCodec.writePNG(cgImage, to: url, dpi: 72.0 * Double(max(pixelsPerPoint, 1.0)))
        excludeFromBackup(url)

        return CaptureAsset(
            id: id,
            cacheURL: url,
            thumbnail: ImageCodec.thumbnail(from: cgImage, maxSide: AppConstants.previewThumbnailMaxSide),
            kind: kind,
            createdAt: Date(),
            baseName: filename(suffix: suffix),
            pixelsPerPoint: max(pixelsPerPoint, 1.0),
            originScreenID: originScreenID,
            pixelSize: CGSize(width: cgImage.width, height: cgImage.height),
            originalSavedURL: nil,
            initialResult: nil
        )
    }

    func insert(_ batch: CaptureBatch) {
        recentBatches.removeAll { $0.id == batch.id }
        recentBatches.insert(batch, at: 0)
        while recentBatches.count > maxRecent {
            let evicted = recentBatches.removeLast()
            purgeBatchIfUnretained(evicted)
        }
    }

    func update(_ batch: CaptureBatch) {
        guard let index = recentBatches.firstIndex(where: { $0.id == batch.id }) else { return }
        recentBatches[index] = batch
    }

    func updateAsset(_ asset: CaptureAsset, in batchID: UUID) {
        guard let batchIndex = recentBatches.firstIndex(where: { $0.id == batchID }),
              let assetIndex = recentBatches[batchIndex].assets.firstIndex(where: { $0.id == asset.id }) else { return }
        recentBatches[batchIndex].assets[assetIndex] = asset
    }

    func discard(batchID: UUID) {
        guard let index = recentBatches.firstIndex(where: { $0.id == batchID }) else { return }
        let batch = recentBatches.remove(at: index)
        purgeBatchIfUnretained(batch)
    }

    func retainForEditing(_ asset: CaptureAsset) {
        editorRetainCounts[asset.id, default: 0] += 1
    }

    func releaseFromEditing(_ asset: CaptureAsset) {
        let current = editorRetainCounts[asset.id, default: 0] - 1
        if current <= 0 {
            editorRetainCounts.removeValue(forKey: asset.id)
            if !recentBatches.contains(where: { $0.assets.contains(where: { $0.id == asset.id }) }) {
                purge(asset)
            }
        } else {
            editorRetainCounts[asset.id] = current
        }
    }

    func purgeUnretained(_ asset: CaptureAsset) {
        guard editorRetainCounts[asset.id] == nil else { return }
        purge(asset)
    }

    private func purgeStaleCacheOnLaunch() {
        try? fileManager.removeItem(at: cacheRoot)
        try? fileManager.createDirectory(at: cacheRoot, withIntermediateDirectories: true, attributes: nil)
        excludeFromBackup(cacheRoot)
    }

    private func purgeBatchIfUnretained(_ batch: CaptureBatch) {
        batch.assets.forEach { purgeUnretained($0) }
    }

    private func purge(_ asset: CaptureAsset) {
        try? fileManager.removeItem(at: asset.cacheURL)
    }

    private func excludeFromBackup(_ url: URL) {
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        var mutableURL = url
        try? mutableURL.setResourceValues(resourceValues)
    }

    private func filename(suffix: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "Screenshot \(formatter.string(from: Date())) \(suffix)"
    }
}

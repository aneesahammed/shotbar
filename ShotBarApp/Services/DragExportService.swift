import AppKit
import Foundation
import UniformTypeIdentifiers

protocol DragExporting {
    func itemProvider(
        for asset: CaptureAsset,
        format: ImageFormat,
        onFailure: @escaping @MainActor (Error) -> Void
    ) -> NSItemProvider

    func exportFile(for asset: CaptureAsset, format: ImageFormat) throws -> URL
    func cleanupOldDragFiles(olderThan retention: TimeInterval)
    func cleanupOldDragFilesAsync(olderThan retention: TimeInterval)
}

final class DragExportService: DragExporting {
    private struct DragExportJob {
        let sourceURL: URL
        let exportURL: URL
        let format: ImageFormat
        let pixelsPerPoint: CGFloat
        let stagedSourceURL: URL?
        let requiresReencode: Bool
    }

    private let fileManager: FileManager
    private let exportRoot: URL
    private let workQueue: DispatchQueue
    private let cleanupQueue: DispatchQueue
    private let linkFile: (URL, URL) throws -> Void
    private let copyFile: (URL, URL) throws -> Void
    private let stateLock = NSLock()
    private var activePaths: Set<URL> = []
    private var reservedExportPaths: Set<URL> = []
    private var cleanupPending = false
    private var lastCleanup = Date.distantPast

    init(
        fileManager: FileManager = .default,
        exportRoot: URL? = nil,
        workQueue: DispatchQueue = DispatchQueue(label: "com.shotbarapp.drag-export"),
        cleanupQueue: DispatchQueue = DispatchQueue(label: "com.shotbarapp.drag-export.cleanup", qos: .utility),
        linkFile: ((URL, URL) throws -> Void)? = nil,
        copyFile: ((URL, URL) throws -> Void)? = nil
    ) {
        let manager = fileManager
        self.fileManager = fileManager
        self.exportRoot = exportRoot ?? Self.defaultExportRoot(fileManager: fileManager)
        self.workQueue = workQueue
        self.cleanupQueue = cleanupQueue
        self.linkFile = linkFile ?? { sourceURL, destinationURL in
            try manager.linkItem(at: sourceURL, to: destinationURL)
        }
        self.copyFile = copyFile ?? { sourceURL, destinationURL in
            try manager.copyItem(at: sourceURL, to: destinationURL)
        }
    }

    func itemProvider(
        for asset: CaptureAsset,
        format: ImageFormat,
        onFailure: @escaping @MainActor (Error) -> Void
    ) -> NSItemProvider {
        let job: DragExportJob
        do {
            job = try prepareJob(for: asset, format: format)
        } catch {
            Task { @MainActor in onFailure(error) }
            return NSItemProvider()
        }

        let provider = NSItemProvider()
        provider.suggestedName = job.exportURL.lastPathComponent

        registerImageDataRepresentation(
            on: provider,
            typeIdentifier: format.utType.identifier,
            job: job,
            onFailure: onFailure
        ) { url in
            try Data(contentsOf: url)
        }

        registerImageDataRepresentation(
            on: provider,
            typeIdentifier: UTType.tiff.identifier,
            job: job,
            onFailure: onFailure
        ) { url in
            let image = try ImageCodec.loadImage(from: url)
            let size = NSSize(width: image.width, height: image.height)
            guard let data = NSImage(cgImage: image, size: size).tiffRepresentation else {
                throw Self.error("Could not encode dragged screenshot as TIFF", code: -76)
            }
            return data
        }

        provider.registerFileRepresentation(
            forTypeIdentifier: format.utType.identifier,
            fileOptions: [],
            visibility: .all
        ) { [weak self] completion in
            guard let self else {
                completion(nil, false, Self.error("Drag export service is no longer available", code: -70))
                return nil
            }
            return self.enqueueExport(job, onFailure: onFailure) { url, error in
                completion(url, false, error)
            }
        }

        provider.registerDataRepresentation(
            forTypeIdentifier: UTType.fileURL.identifier,
            visibility: .all
        ) { [weak self] completion in
            guard let self else {
                completion(nil, Self.error("Drag export service is no longer available", code: -70))
                return nil
            }
            return self.enqueueExport(job, onFailure: onFailure) { url, error in
                guard let url else {
                    completion(nil, error)
                    return
                }
                completion((url as NSURL).dataRepresentation, nil)
            }
        }

        return provider
    }

    func exportFile(for asset: CaptureAsset, format: ImageFormat) throws -> URL {
        let job = try prepareJob(for: asset, format: format)
        return try exportFile(for: job)
    }

    func cleanupOldDragFilesAsync(olderThan retention: TimeInterval = AppConstants.dragExportRetention) {
        scheduleCleanup(olderThan: retention, minimumInterval: 0)
    }

    private func cleanupOldDragFilesIfDueAsync(olderThan retention: TimeInterval = AppConstants.dragExportRetention) {
        scheduleCleanup(olderThan: retention, minimumInterval: 10 * 60)
    }

    private func scheduleCleanup(olderThan retention: TimeInterval, minimumInterval: TimeInterval) {
        let now = Date()
        stateLock.lock()
        guard !cleanupPending, now.timeIntervalSince(lastCleanup) >= minimumInterval else {
            stateLock.unlock()
            return
        }
        cleanupPending = true
        lastCleanup = now
        stateLock.unlock()

        cleanupQueue.async { [weak self] in
            guard let self else { return }
            self.cleanupOldDragFiles(olderThan: retention)
            self.stateLock.lock()
            self.cleanupPending = false
            self.stateLock.unlock()
        }
    }

    func cleanupOldDragFiles(olderThan retention: TimeInterval = AppConstants.dragExportRetention) {
        guard fileManager.fileExists(atPath: exportRoot.path) else { return }

        let cutoff = Date().addingTimeInterval(-retention)
        let keys: [URLResourceKey] = [.isRegularFileKey, .contentModificationDateKey, .creationDateKey]
        let protectedPaths = protectedPathsSnapshot()
        guard let enumerator = fileManager.enumerator(
            at: exportRoot,
            includingPropertiesForKeys: keys,
            options: [.skipsPackageDescendants]
        ) else {
            return
        }

        for case let url as URL in enumerator {
            guard !protectedPaths.contains(url) else { continue }
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true else { continue }
            let fileDate = values.contentModificationDate ?? values.creationDate ?? Date()
            if fileDate < cutoff {
                try? fileManager.removeItem(at: url)
            }
        }

        try? removeDirectoryIfEmpty(stagingDirectory)
    }

    private func prepareJob(for asset: CaptureAsset, format: ImageFormat) throws -> DragExportJob {
        try createExportDirectories()
        try validateReadableFile(asset.cacheURL)

        let exportURL = reserveExportURL(baseName: asset.baseName, extension: format.fileExtension)

        if asset.cacheURL.pathExtension.lowercased() == format.fileExtension {
            do {
                try hardLinkFile(from: asset.cacheURL, to: exportURL)
                try markRecentlyUsed(exportURL)
                excludeFromBackup(exportURL)
            } catch {
                return DragExportJob(
                    sourceURL: asset.cacheURL,
                    exportURL: exportURL,
                    format: format,
                    pixelsPerPoint: asset.pixelsPerPoint,
                    stagedSourceURL: nil,
                    requiresReencode: false
                )
            }

            return DragExportJob(
                sourceURL: exportURL,
                exportURL: exportURL,
                format: format,
                pixelsPerPoint: asset.pixelsPerPoint,
                stagedSourceURL: nil,
                requiresReencode: false
            )
        }

        let stagingURL = stagingDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(asset.cacheURL.pathExtension.isEmpty ? AppConstants.FileExtensions.png : asset.cacheURL.pathExtension)

        do {
            registerActivePath(stagingURL)
            try hardLinkFile(from: asset.cacheURL, to: stagingURL)
            try markRecentlyUsed(stagingURL)
            excludeFromBackup(stagingURL)
        } catch {
            return DragExportJob(
                sourceURL: asset.cacheURL,
                exportURL: exportURL,
                format: format,
                pixelsPerPoint: asset.pixelsPerPoint,
                stagedSourceURL: stagingURL,
                requiresReencode: true
            )
        }

        return DragExportJob(
            sourceURL: stagingURL,
            exportURL: exportURL,
            format: format,
            pixelsPerPoint: asset.pixelsPerPoint,
            stagedSourceURL: stagingURL,
            requiresReencode: true
        )
    }

    private func exportFile(for job: DragExportJob) throws -> URL {
        if !job.requiresReencode {
            do {
                if !fileManager.fileExists(atPath: job.exportURL.path) {
                    try duplicateFile(from: job.sourceURL, to: job.exportURL)
                    try markRecentlyUsed(job.exportURL)
                    excludeFromBackup(job.exportURL)
                }
                try validateReadableFile(job.exportURL)
                finish(job: job, removeStagedSource: false, removeExport: false)
                cleanupOldDragFilesIfDueAsync()
                return job.exportURL
            } catch {
                finish(job: job, removeStagedSource: false, removeExport: true)
                throw error
            }
        }

        if fileManager.fileExists(atPath: job.exportURL.path) {
            try validateReadableFile(job.exportURL)
            finish(job: job, removeStagedSource: true, removeExport: false)
            return job.exportURL
        }

        let sourceURL = try preparedSourceURL(for: job)
        let image = try ImageCodec.loadImage(from: sourceURL)
        let dpi = 72.0 * Double(max(job.pixelsPerPoint, 1.0))
        let tempURL = exportRoot
            .appendingPathComponent(".\(UUID().uuidString)")
            .appendingPathExtension(job.format.fileExtension)

        do {
            switch job.format {
            case .png:
                try ImageCodec.writePNG(image, to: tempURL, dpi: dpi)
            case .jpg:
                try ImageCodec.writeJPG(image, to: tempURL, quality: 1.0, dpi: dpi)
            }
            try fileManager.moveItem(at: tempURL, to: job.exportURL)
            try markRecentlyUsed(job.exportURL)
            excludeFromBackup(job.exportURL)
            finish(job: job, removeStagedSource: true, removeExport: false)
            cleanupOldDragFilesIfDueAsync()
            return job.exportURL
        } catch {
            try? fileManager.removeItem(at: tempURL)
            finish(job: job, removeStagedSource: true, removeExport: true)
            throw error
        }
    }

    private func enqueueExport(
        _ job: DragExportJob,
        onFailure: @escaping @MainActor (Error) -> Void,
        completion: @escaping (URL?, Error?) -> Void
    ) -> Progress {
        let progress = Progress(totalUnitCount: 1)
        workQueue.async { [weak self] in
            guard let self else {
                completion(nil, Self.error("Drag export service is no longer available", code: -70))
                return
            }

            if progress.isCancelled {
                completion(nil, Self.error("Drag export was cancelled", code: -73))
                return
            }

            do {
                let url = try self.exportFile(for: job)
                progress.completedUnitCount = 1
                completion(url, nil)
            } catch {
                Task { @MainActor in onFailure(error) }
                completion(nil, error)
            }
        }
        return progress
    }

    private func registerImageDataRepresentation(
        on provider: NSItemProvider,
        typeIdentifier: String,
        job: DragExportJob,
        onFailure: @escaping @MainActor (Error) -> Void,
        dataProvider: @escaping (URL) throws -> Data
    ) {
        provider.registerDataRepresentation(
            forTypeIdentifier: typeIdentifier,
            visibility: .all
        ) { [weak self] completion in
            guard let self else {
                completion(nil, Self.error("Drag export service is no longer available", code: -70))
                return nil
            }
            return self.enqueueExport(job, onFailure: onFailure) { url, error in
                guard let url else {
                    completion(nil, error)
                    return
                }
                do {
                    completion(try dataProvider(url), nil)
                } catch {
                    Task { @MainActor in onFailure(error) }
                    completion(nil, error)
                }
            }
        }
    }

    private func createExportDirectories() throws {
        try fileManager.createDirectory(at: exportRoot, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
        excludeFromBackup(exportRoot)
        excludeFromBackup(stagingDirectory)
    }

    private func hardLinkFile(from sourceURL: URL, to destinationURL: URL) throws {
        try linkFile(sourceURL, destinationURL)
    }

    private func duplicateFile(from sourceURL: URL, to destinationURL: URL) throws {
        do {
            try linkFile(sourceURL, destinationURL)
        } catch {
            try copyFile(sourceURL, destinationURL)
        }
    }

    private func preparedSourceURL(for job: DragExportJob) throws -> URL {
        guard let stagedSourceURL = job.stagedSourceURL else {
            try validateReadableFile(job.sourceURL)
            return job.sourceURL
        }

        if !fileManager.fileExists(atPath: stagedSourceURL.path) {
            try duplicateFile(from: job.sourceURL, to: stagedSourceURL)
            try markRecentlyUsed(stagedSourceURL)
            excludeFromBackup(stagedSourceURL)
        }
        try validateReadableFile(stagedSourceURL)
        return stagedSourceURL
    }

    private func markRecentlyUsed(_ url: URL) throws {
        try fileManager.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
    }

    private func validateReadableFile(_ url: URL) throws {
        guard fileManager.fileExists(atPath: url.path) else {
            throw Self.error("Cached screenshot is no longer available", code: -74)
        }

        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true, (values.fileSize ?? 0) > 0 else {
            throw Self.error("Cached screenshot is not a readable file", code: -75)
        }
    }

    private func excludeFromBackup(_ url: URL) {
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        var mutableURL = url
        try? mutableURL.setResourceValues(resourceValues)
    }

    private func removeDirectoryIfEmpty(_ url: URL) throws {
        guard let contents = try? fileManager.contentsOfDirectory(atPath: url.path),
              contents.isEmpty else { return }
        try fileManager.removeItem(at: url)
    }

    private func reserveExportURL(baseName: String, extension ext: String) -> URL {
        let sanitized = FileNaming.sanitizedBaseName(baseName)
        var candidate = exportRoot.appendingPathComponent(sanitized).appendingPathExtension(ext)
        var counter = 2

        stateLock.lock()
        while fileManager.fileExists(atPath: candidate.path) || reservedExportPaths.contains(candidate) {
            candidate = exportRoot
                .appendingPathComponent("\(sanitized) (\(counter))")
                .appendingPathExtension(ext)
            counter += 1
        }
        reservedExportPaths.insert(candidate)
        activePaths.insert(candidate)
        stateLock.unlock()

        return candidate
    }

    private func registerActivePath(_ url: URL) {
        stateLock.lock()
        activePaths.insert(url)
        stateLock.unlock()
    }

    private func protectedPathsSnapshot() -> Set<URL> {
        stateLock.lock()
        let paths = activePaths.union(reservedExportPaths)
        stateLock.unlock()
        return paths
    }

    private func finish(job: DragExportJob, removeStagedSource: Bool, removeExport: Bool) {
        if removeStagedSource, let stagedSourceURL = job.stagedSourceURL {
            try? fileManager.removeItem(at: stagedSourceURL)
        }
        if removeExport {
            try? fileManager.removeItem(at: job.exportURL)
        }

        stateLock.lock()
        activePaths.remove(job.exportURL)
        reservedExportPaths.remove(job.exportURL)
        if let stagedSourceURL = job.stagedSourceURL {
            activePaths.remove(stagedSourceURL)
        }
        stateLock.unlock()
    }

    private var stagingDirectory: URL {
        exportRoot.appendingPathComponent(AppConstants.CacheDirectories.dragStaging, isDirectory: true)
    }

    private static func defaultExportRoot(fileManager: FileManager) -> URL {
        let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return caches
            .appendingPathComponent(AppConstants.CacheDirectories.app, isDirectory: true)
            .appendingPathComponent(AppConstants.CacheDirectories.dragExports, isDirectory: true)
    }

    private static func error(_ message: String, code: Int) -> NSError {
        NSError(domain: "ShotBar", code: code, userInfo: [NSLocalizedDescriptionKey: message])
    }
}

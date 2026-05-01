import Foundation
import SwiftUI
import ScreenCaptureKit
import CoreGraphics
import CoreVideo
import ImageIO
import UniformTypeIdentifiers
import AppKit

// MARK: - Screenshot Manager (ScreenCaptureKit)

final class ScreenshotManager: ObservableObject {
    @Published var saveDirectory: URL?
    private let toast = Toast()
    private let prefs: Preferences
    private let persistence: ImagePersistenceService
    private let captureStore: CaptureStore
    private let previewCoordinator: PreviewCoordinator

    // Persist capture scale (pixels-per-point) for accurate clipboard DPI/size
    private var lastCapturePixelsPerPoint: CGFloat = 1.0

    // Add property to store the previous active application
    private var previousActiveApp: NSRunningApplication?

    init(
        prefs: Preferences,
        persistence: ImagePersistenceService,
        captureStore: CaptureStore,
        previewCoordinator: PreviewCoordinator
    ) {
        self.prefs = prefs
        self.persistence = persistence
        self.captureStore = captureStore
        self.previewCoordinator = previewCoordinator
    }

    // MARK: Save location

    func refreshSaveDirectory() {
        // Use the app's sandboxed Documents directory and surface it through Reveal Save Folder.
        let documentsDir = persistence.defaultSaveDirectory
        saveDirectory = documentsDir
        print("Save directory set to: \(documentsDir.path)")
    }

    @MainActor
    func revealSaveLocationInFinder() {
        persistence.revealSaveDirectory()
        // Hide the menu bar popover after revealing folder
        hideMenuBarPopover()
    }

    // MARK: Entry points

    func captureSelection(bypassPreview: Bool = false) {
        Task { @MainActor in
            // Dismiss the popover BEFORE the overlay appears so the popover
            // doesn't occlude the content the user is trying to select.
            await self.dismissPopoverAndSettle()
            SelectionOverlay.present { [weak self] selection, screen in
                guard let self, let selection, let screen else { return }
                Task { @MainActor in
                    do {
                        // Allow the overlay windows to fully dismiss before capturing
                        try? await Task.sleep(nanoseconds: 150_000_000)
                        let cg = try await self.captureDisplayRegion(selection: selection, on: screen)
                        await self.handleSingleCapture(
                            cgImage: cg,
                            kind: .selection,
                            suffix: "Selection",
                            originScreenID: self.screenID(for: screen),
                            bypassPreview: bypassPreview
                        )
                    } catch {
                        self.toast.show(text: "Selection failed: \(error.localizedDescription)", kind: .error)
                    }
                }
            }
        }
    }

    // Make this method public so it can be called before the menubar becomes active
    func storePreviousActiveApp() {
        // Store the current frontmost app before our menubar becomes active
        previousActiveApp = NSWorkspace.shared.frontmostApplication
    }

    func captureActiveWindow(bypassPreview: Bool = false) {
        Task { @MainActor in
            do {
                // First, try to get the previously stored active application
                guard let previousApp = previousActiveApp else {
                    self.toast.show(text: "No active window detected. Please focus a window first, then try again.", kind: .error)
                    return
                }

                // Dismiss the popover BEFORE capture so it isn't included in the
                // window list / image and doesn't visually occlude the target.
                await self.dismissPopoverAndSettle()

                let content = try await SCShareableContent.current

                // Get the current ShotBar app bundle identifier to exclude it
                let currentAppBundleID = Bundle.main.bundleIdentifier ?? "com.shotbarapp.ShotBarApp"

                // Filter windows to only include windows from the previously active app
                let targetAppWindows = content.windows.filter { win in
                    guard let app = win.owningApplication else { return false }

                    // Only include windows from the previously active app
                    guard app.bundleIdentifier == previousApp.bundleIdentifier else { return false }

                    // Exclude ShotBar app itself
                    if app.bundleIdentifier == currentAppBundleID { return false }

                    // Only include on-screen windows with reasonable sizes
                    return win.isOnScreen &&
                    win.frame.width > 100 &&
                    win.frame.height > 100 &&
                    win.frame.width < 10000 &&
                    win.frame.height < 10000
                }

                guard let targetWindow = targetAppWindows.first else {
                    self.toast.show(text: "No captureable window found for \(previousApp.localizedName ?? "the previous app")", kind: .error)
                    return
                }

                let filter = SCContentFilter(desktopIndependentWindow: targetWindow)
                let config = SCStreamConfiguration()

                let scale = self.pixelScale(for: targetWindow.frame, preferredScale: CGFloat(filter.pointPixelScale))
                config.width = max(1, Int(round(targetWindow.frame.width * scale.width)))
                config.height = max(1, Int(round(targetWindow.frame.height * scale.height)))

                config.captureResolution = .best
                config.pixelFormat = kCVPixelFormatType_32BGRA
                config.showsCursor = false
                config.scalesToFit = false

                self.lastCapturePixelsPerPoint = max(scale.width, scale.height, 1.0)

                var capturedImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)

                // Check if the capture resulted in a black image
                if self.isMostlyBlack(capturedImage) {
                    // Fallback: Try to capture just the window area from the display
                    // but with tighter bounds to avoid capturing overlapping UI
                    if let windowScreen = NSScreen.screens.first(where: { $0.frame.intersects(targetWindow.frame) }) ?? NSScreen.main {
                        do {
                            // Create a tighter selection area to avoid capturing overlapping UI
                            let tightFrame = createTightWindowFrame(from: targetWindow.frame, on: windowScreen)
                            capturedImage = try await self.captureDisplayRegion(selection: tightFrame, on: windowScreen)
                        } catch {
                            // If fallback also fails, show error
                            self.toast.show(text: "Failed to capture window: \(error.localizedDescription)", kind: .error)
                            return
                        }
                    }
                }

                let originScreen = NSScreen.screens.first(where: { $0.frame.intersects(targetWindow.frame) }) ?? NSScreen.main
                await self.handleSingleCapture(
                    cgImage: capturedImage,
                    kind: .window,
                    suffix: "Window",
                    originScreenID: originScreen.flatMap { self.screenID(for: $0) },
                    bypassPreview: bypassPreview
                )

            } catch {
                self.toast.show(text: "Window capture failed: \(error.localizedDescription)", kind: .error)
            }
        }
    }

    func captureFullScreens(bypassPreview: Bool = false) {
        Task { @MainActor in
            do {
                // Dismiss the popover BEFORE capturing the screen, otherwise
                // it shows up in every screenshot.
                await self.dismissPopoverAndSettle()

                let content = try await SCShareableContent.current
                let displays = content.displays
                if displays.isEmpty {
                    self.toast.show(text: "No displays", kind: .error)
                    return
                }
                var assets: [CaptureAsset] = []
                for (i, d) in displays.enumerated() {
                    let filter = SCContentFilter(display: d, excludingWindows: [])
                    let config = SCStreamConfiguration()
                    let suffix = displays.count > 1 ? "Display\(i+1)" : "Screen"

                    let px = displayPixelSize(for: d, preferredScale: CGFloat(filter.pointPixelScale))
                    config.width = px.width
                    config.height = px.height
                    self.lastCapturePixelsPerPoint = max(px.scale.width, px.scale.height, 1.0)

                    config.captureResolution = .best
                    config.pixelFormat = kCVPixelFormatType_32BGRA
                    config.showsCursor = false
                    config.scalesToFit = false

                    let cg = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
                    let asset = try await self.captureStore.makeAsset(
                        from: cg,
                        kind: displays.count > 1 ? .display : .screen,
                        suffix: suffix,
                        pixelsPerPoint: max(px.scale.width, px.scale.height, 1.0),
                        originScreenID: d.displayID
                    )
                    assets.append(asset)
                }
                if assets.isEmpty {
                    self.toast.show(text: "Full screen capture failed", kind: .error)
                } else {
                    self.playShutterSoundIfEnabled()
                    await self.handleCapturedBatch(CaptureBatch(assets: assets), bypassPreview: bypassPreview)
                }
            } catch {
                self.toast.show(text: "Full screen failed: \(error.localizedDescription)", kind: .error)
            }
        }
    }

    // MARK: Menu Management

    private func hideMenuBarPopover() {
        // Post notification synchronously; AppDelegate calls performClose, which animates.
        NotificationCenter.default.post(name: NSNotification.Name("HideMenuBarPopover"), object: nil)
    }

    /// Closes the menu-bar popover and waits long enough for the dismissal
    /// animation to finish so it isn't included in subsequent screenshots.
    @MainActor
    private func dismissPopoverAndSettle() async {
        hideMenuBarPopover()
        // NSPopover's default close animation is ~200ms. Add a small cushion
        // so SCShareableContent no longer reports the popover as a window and
        // the user's eye sees a clean screen before the capture takes place.
        try? await Task.sleep(nanoseconds: 250_000_000)
    }


    // MARK: SCK helpers - FIXED FOR HIGH QUALITY SELECTION CAPTURE
    private func captureDisplayRegion(selection: CGRect, on screen: NSScreen) async throws -> CGImage {
        let content = try await SCShareableContent.current

        // Map NSScreen -> SCDisplay via CGDirectDisplayID
        guard
            let num = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        else {
            throw NSError(domain: "ShotBar", code: -10, userInfo: [NSLocalizedDescriptionKey: "No display ID"])
        }
        let displayID = CGDirectDisplayID(num.uint32Value)

        guard let scDisplay = content.displays.first(where: { $0.displayID == displayID }) else {
            throw NSError(domain: "ShotBar", code: -10, userInfo: [NSLocalizedDescriptionKey: "Display mapping failed"])
        }

        let filter = SCContentFilter(display: scDisplay, excludingWindows: [])
        let displaySize = displayPixelSize(for: scDisplay, screen: screen, preferredScale: CGFloat(filter.pointPixelScale))
        let cropRect = CaptureGeometry.clampedCropRect(
            selection: selection,
            screenFrame: screen.frame,
            scaleX: displaySize.scale.width,
            scaleY: displaySize.scale.height,
            displayPixelSize: CGSize(width: displaySize.width, height: displaySize.height)
        )

        guard !cropRect.isNull, !cropRect.isEmpty,
              cropRect.width >= 1, cropRect.height >= 1 else {
            throw NSError(domain: "ShotBar", code: -11, userInfo: [NSLocalizedDescriptionKey: "Selection invalid or out of bounds"])
        }

        let cfg = SCStreamConfiguration()

        cfg.width = displaySize.width
        cfg.height = displaySize.height

        cfg.captureResolution = .best
        cfg.pixelFormat = kCVPixelFormatType_32BGRA
        cfg.showsCursor = false
        cfg.scalesToFit = false
        cfg.minimumFrameInterval = CMTime(value: 1, timescale: 60)

        // Set color space for proper color reproduction
        cfg.colorSpaceName = CGColorSpace.displayP3

        self.lastCapturePixelsPerPoint = max(displaySize.scale.width, displaySize.scale.height, 1.0)

        let fullImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg)

        guard let croppedImage = fullImage.cropping(to: cropRect) else {
            throw NSError(domain: "ShotBar", code: -12, userInfo: [NSLocalizedDescriptionKey: "Failed to crop image"])
        }

        return croppedImage
    }

    static func promptForPermissionIfNeeded() {
        // There isn't a dedicated SCK authorization API; touching SCK triggers the system prompt.
        Task {
            _ = try? await SCShareableContent.current
        }
    }

    private func displayPixelSize(for display: SCDisplay, preferredScale: CGFloat? = nil) -> (width: Int, height: Int, scale: CGSize) {
        let screen = screen(for: display)
        return displayPixelSize(for: display, screen: screen, preferredScale: preferredScale)
    }

    private func screen(for display: SCDisplay) -> NSScreen? {
        NSScreen.screens.first {
            (($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value) == display.displayID
        }
    }

    private func screenID(for screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber).map {
            CGDirectDisplayID($0.uint32Value)
        }
    }

    private func displayPixelSize(for display: SCDisplay, screen: NSScreen?, preferredScale: CGFloat? = nil) -> (width: Int, height: Int, scale: CGSize) {
        guard let screen else {
            let fallbackScale = preferredScale.flatMap { $0 > 0 ? $0 : nil } ?? 1
            let width = max(Int(round(CGFloat(display.width) * fallbackScale)), Int(CGDisplayPixelsWide(display.displayID)), 1)
            let height = max(Int(round(CGFloat(display.height) * fallbackScale)), Int(CGDisplayPixelsHigh(display.displayID)), 1)
            return (width, height, CGSize(width: fallbackScale, height: fallbackScale))
        }

        let modePixelSize = CaptureGeometry.displayModePixelSize(for: display.displayID)
        let legacyPixelSize = CaptureGeometry.legacyDisplayPixelSize(for: display.displayID)
        let scale = CaptureGeometry.pixelsPerPoint(
            pointSize: screen.frame.size,
            displayModePixelSize: modePixelSize,
            legacyDisplayPixelSize: legacyPixelSize,
            backingScaleFactor: screen.backingScaleFactor,
            preferredScale: preferredScale
        )
        let size = CaptureGeometry.outputPixelSize(
            pointSize: screen.frame.size,
            displayModePixelSize: modePixelSize,
            legacyDisplayPixelSize: legacyPixelSize,
            backingScaleFactor: screen.backingScaleFactor,
            preferredScale: preferredScale
        )

        return (max(1, Int(size.width)), max(1, Int(size.height)), scale)
    }

    private func pixelScale(for frame: CGRect, preferredScale: CGFloat? = nil) -> CGSize {
        guard let windowScreen = NSScreen.screens.first(where: { $0.frame.intersects(frame) }) ?? NSScreen.main,
              let displayNumber = windowScreen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        else {
            let fallback = preferredScale.flatMap { $0 > 0 ? $0 : nil } ?? 2.0
            return CGSize(width: fallback, height: fallback)
        }

        let displayID = CGDirectDisplayID(truncating: displayNumber)
        return CaptureGeometry.pixelsPerPoint(
            pointSize: windowScreen.frame.size,
            displayModePixelSize: CaptureGeometry.displayModePixelSize(for: displayID),
            legacyDisplayPixelSize: CaptureGeometry.legacyDisplayPixelSize(for: displayID),
            backingScaleFactor: windowScreen.backingScaleFactor,
            preferredScale: preferredScale
        )
    }


    // MARK: Saving

    @MainActor
    private func handleSingleCapture(
        cgImage: CGImage,
        kind: CaptureKind,
        suffix: String,
        originScreenID: CGDirectDisplayID?,
        bypassPreview: Bool
    ) async {
        do {
            let asset = try await captureStore.makeAsset(
                from: cgImage,
                kind: kind,
                suffix: suffix,
                pixelsPerPoint: max(lastCapturePixelsPerPoint, 1.0),
                originScreenID: originScreenID
            )
            playShutterSoundIfEnabled()
            await handleCapturedBatch(CaptureBatch(assets: [asset]), bypassPreview: bypassPreview)
        } catch {
            toast.show(text: "Capture cache failed: \(error.localizedDescription)", kind: .error)
        }
    }

    @MainActor
    private func handleCapturedBatch(_ inputBatch: CaptureBatch, bypassPreview: Bool) async {
        var batch = inputBatch
        batch = await persistInitialOutput(for: batch)

        if prefs.previewEnabled, !bypassPreview {
            captureStore.insert(batch)
            previewCoordinator.present(batch)
        } else {
            batch.assets.forEach { captureStore.purgeUnretained($0) }
        }
    }

    @MainActor
    private func persistInitialOutput(for inputBatch: CaptureBatch) async -> CaptureBatch {
        var batch = inputBatch
        switch prefs.destination {
        case .clipboard:
            guard let index = preferredClipboardAssetIndex(in: batch) else { return batch }
            var asset = batch.assets[index]
            let result = await persistence.copy(asset)
            asset.initialResult = result
            batch.assets[index] = asset
        case .file:
            var savedCount = 0
            var failure: String?
            for index in batch.assets.indices {
                var asset = batch.assets[index]
                let result = await persistence.save(
                    asset,
                    options: SaveOptions(
                        baseName: asset.baseName,
                        suffix: "",
                        format: prefs.imageFormat,
                        showToast: batch.assets.count == 1,
                        playSound: false
                    )
                )
                asset.initialResult = result
                if let url = result.savedURL {
                    asset.originalSavedURL = url
                    savedCount += 1
                } else if let message = result.failureMessage {
                    failure = message
                }
                batch.assets[index] = asset
            }
            if batch.assets.count > 1 {
                if savedCount == batch.assets.count {
                    persistence.show(text: "Saved \(savedCount) screenshots", kind: .success)
                } else if let failure {
                    persistence.show(text: failure, kind: .error)
                }
            }
        }
        return batch
    }

    private func preferredClipboardAssetIndex(in batch: CaptureBatch) -> Int? {
        guard !batch.assets.isEmpty else { return nil }
        let cursorScreenID = NSScreen.screens
            .first(where: { $0.frame.contains(NSEvent.mouseLocation) })
            .flatMap { screenID(for: $0) }
        if let cursorScreenID,
           let index = batch.assets.firstIndex(where: { $0.originScreenID == cursorScreenID }) {
            return index
        }
        return batch.assets.startIndex
    }

    // MARK: - Heuristics
    private func isMostlyBlack(_ cgImage: CGImage) -> Bool {
        guard let provider = cgImage.dataProvider, let data = provider.data as Data? else { return false }
        let bytesPerPixel = max(cgImage.bitsPerPixel / 8, 1)
        let sampleStride = max(bytesPerPixel * 97, 4)
        let maxSamples = min(50_000, data.count / sampleStride)
        if maxSamples == 0 { return false }
        var nonBlackCount = 0
        var index = 0
        for _ in 0..<maxSamples {
            if index + bytesPerPixel <= data.count {
                // Try to handle both BGRA and ARGB without depending on bitmapInfo
                if bytesPerPixel >= 4 {
                    // Read four bytes
                    let byte0 = Int(data[index])
                    let byte1 = Int(data[index+1])
                    let byte2 = Int(data[index+2])
                    let byte3 = Int(data[index+3])
                    // Heuristic: if alpha is at either end, choose the brightest trio
                    let sumRGB0 = byte0 + byte1 + byte2
                    let sumRGB1 = byte1 + byte2 + byte3
                    let sumRGB2 = byte0 + byte2 + byte3
                    let sumRGB3 = byte0 + byte1 + byte3
                    let sum = max(sumRGB0, max(sumRGB1, max(sumRGB2, sumRGB3)))
                    if sum > 5 { nonBlackCount += 1 }
                } else {
                    if Int(data[index]) > 5 { nonBlackCount += 1 }
                }
            }
            index += sampleStride
        }
        let fraction = Double(nonBlackCount) / Double(maxSamples)
        return fraction < 0.01
    }

    private func playShutterSoundIfEnabled() {
        guard prefs.soundEnabled else { return }
        NSSound(named: NSSound.Name("Tink"))?.play()
    }

    private func appDocumentsDirectory() -> URL {
        // File captures intentionally stay inside the app sandbox.
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory

        // Create the directory if it doesn't exist
        do {
            try FileManager.default.createDirectory(at: documentsURL, withIntermediateDirectories: true, attributes: nil)
        } catch {
            print("Warning: Could not create Documents directory: \(error)")
        }

        return documentsURL
    }

    // Helper function to create a tighter frame that avoids overlapping UI elements
    private func createTightWindowFrame(from windowFrame: CGRect, on screen: NSScreen) -> CGRect {
        // Reduce the frame size slightly to avoid capturing overlapping UI elements
        let inset: CGFloat = 2.0 // 2 points inset to avoid borders and overlapping elements

        var tightFrame = windowFrame.insetBy(dx: inset, dy: inset)

        // Ensure the frame doesn't go outside the screen bounds
        let screenFrame = screen.frame
        tightFrame = tightFrame.intersection(screenFrame)

        // Ensure minimum size
        if tightFrame.width < 50 || tightFrame.height < 50 {
            tightFrame = windowFrame // Fall back to original frame if too small
        }

        return tightFrame
    }
}

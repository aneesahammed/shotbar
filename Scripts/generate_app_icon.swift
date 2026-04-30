#!/usr/bin/env swift
import AppKit
import Foundation

struct IconSpec {
    let size: Int // point size
    let scale: Int // 1 or 2
}

let macIconSpecs: [IconSpec] = [
    IconSpec(size: 16, scale: 1),
    IconSpec(size: 16, scale: 2),
    IconSpec(size: 32, scale: 1),
    IconSpec(size: 32, scale: 2),
    IconSpec(size: 128, scale: 1),
    IconSpec(size: 128, scale: 2),
    IconSpec(size: 256, scale: 1),
    IconSpec(size: 256, scale: 2),
    IconSpec(size: 512, scale: 1),
    IconSpec(size: 512, scale: 2), // 1024px
]

let fileManager = FileManager.default
let currentDir = fileManager.currentDirectoryPath
let appIconDir = URL(fileURLWithPath: currentDir)
    .appendingPathComponent("ShotBarApp/Assets.xcassets/AppIcon.appiconset", isDirectory: true)

func ensureDir(_ url: URL) throws {
    var isDir: ObjCBool = false
    if !fileManager.fileExists(atPath: url.path, isDirectory: &isDir) || !isDir.boolValue {
        throw NSError(domain: "generate_app_icon", code: 1, userInfo: [NSLocalizedDescriptionKey: "AppIcon.appiconset not found at \(url.path)"])
    }
}

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1.0) -> NSColor {
    return NSColor(calibratedRed: r/255.0, green: g/255.0, blue: b/255.0, alpha: a)
}

func point(center: NSPoint, radius: CGFloat, angle: CGFloat) -> NSPoint {
    NSPoint(
        x: center.x + cos(angle) * radius,
        y: center.y + sin(angle) * radius
    )
}

func withShadow(color: NSColor, blur: CGFloat, offset: NSSize, _ drawing: () -> Void) {
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = color
    shadow.shadowBlurRadius = blur
    shadow.shadowOffset = offset
    shadow.set()
    drawing()
    NSGraphicsContext.restoreGraphicsState()
}

func drawCaptureBrackets(in rect: NSRect, length: CGFloat, lineWidth: CGFloat, color strokeColor: NSColor) {
    let path = NSBezierPath()
    path.lineWidth = lineWidth
    path.lineCapStyle = .round
    path.lineJoinStyle = .round

    path.move(to: NSPoint(x: rect.minX, y: rect.maxY - length))
    path.line(to: NSPoint(x: rect.minX, y: rect.maxY))
    path.line(to: NSPoint(x: rect.minX + length, y: rect.maxY))

    path.move(to: NSPoint(x: rect.maxX - length, y: rect.maxY))
    path.line(to: NSPoint(x: rect.maxX, y: rect.maxY))
    path.line(to: NSPoint(x: rect.maxX, y: rect.maxY - length))

    path.move(to: NSPoint(x: rect.minX, y: rect.minY + length))
    path.line(to: NSPoint(x: rect.minX, y: rect.minY))
    path.line(to: NSPoint(x: rect.minX + length, y: rect.minY))

    path.move(to: NSPoint(x: rect.maxX - length, y: rect.minY))
    path.line(to: NSPoint(x: rect.maxX, y: rect.minY))
    path.line(to: NSPoint(x: rect.maxX, y: rect.minY + length))

    strokeColor.setStroke()
    path.stroke()
}

func drawApertureMark(center: NSPoint, radius: CGFloat, pixels: CGFloat) {
    let outerRect = NSRect(
        x: center.x - radius,
        y: center.y - radius,
        width: radius * 2,
        height: radius * 2
    )
    let outerPath = NSBezierPath(ovalIn: outerRect)

    withShadow(
        color: color(2, 8, 14, 0.32),
        blur: pixels * 0.018,
        offset: NSSize(width: 0, height: -pixels * 0.008)
    ) {
        NSGradient(colors: [
            color(248, 253, 255),
            color(136, 230, 244),
            color(43, 188, 216)
        ])!.draw(in: outerPath, angle: 120)
    }

    color(255, 255, 255, 0.72).setStroke()
    outerPath.lineWidth = max(pixels * 0.006, 1)
    outerPath.stroke()

    let innerRadius = radius * 0.55
    let innerRect = NSRect(
        x: center.x - innerRadius,
        y: center.y - innerRadius,
        width: innerRadius * 2,
        height: innerRadius * 2
    )
    let innerPath = NSBezierPath(ovalIn: innerRect)
    NSGradient(colors: [
        color(24, 36, 48),
        color(8, 14, 22)
    ])!.draw(in: innerPath, angle: -45)

    if pixels >= 128 {
        let bladeRadius = innerRadius * 0.88
        let hubRadius = innerRadius * 0.28
        for index in 0..<6 {
            let a0 = CGFloat(index) * (.pi / 3.0) + .pi / 12.0
            let a1 = a0 + .pi / 3.8
            let path = NSBezierPath()
            path.move(to: point(center: center, radius: hubRadius, angle: a0 + 0.28))
            path.line(to: point(center: center, radius: bladeRadius, angle: a0))
            path.line(to: point(center: center, radius: bladeRadius, angle: a1))
            path.close()
            color(112, 132, 145, index % 2 == 0 ? 0.34 : 0.22).setFill()
            path.fill()
        }
    }

    color(255, 255, 255, 0.34).setStroke()
    innerPath.lineWidth = max(pixels * 0.0045, 1)
    innerPath.stroke()
}

func drawAppIconBitmap(size pixels: Int) -> NSBitmapImageRep {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        fatalError("Failed to create bitmap rep")
    }

    rep.size = NSSize(width: pixels, height: pixels) // 1 point == 1 pixel
    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ctx
    defer {
        NSGraphicsContext.restoreGraphicsState()
    }

    let p = CGFloat(pixels)
    let rect = NSRect(x: 0, y: 0, width: p, height: p)
    color(0, 0, 0, 0).setFill()
    NSBezierPath(rect: rect).fill()

    let baseRect = rect.insetBy(dx: p * 0.055, dy: p * 0.055)
    let baseRadius = p * 0.205
    let basePath = NSBezierPath(roundedRect: baseRect, xRadius: baseRadius, yRadius: baseRadius)

    withShadow(
        color: color(11, 19, 28, 0.34),
        blur: p * 0.052,
        offset: NSSize(width: 0, height: -p * 0.024)
    ) {
        NSGradient(colors: [
            color(250, 252, 253),
            color(229, 235, 240),
            color(189, 201, 211)
        ])!.draw(in: basePath, angle: 90)
    }

    color(255, 255, 255, 0.72).setStroke()
    basePath.lineWidth = max(p * 0.006, 1)
    basePath.stroke()

    let baseInnerPath = NSBezierPath(
        roundedRect: baseRect.insetBy(dx: p * 0.017, dy: p * 0.017),
        xRadius: baseRadius * 0.88,
        yRadius: baseRadius * 0.88
    )
    color(64, 80, 94, 0.16).setStroke()
    baseInnerPath.lineWidth = max(p * 0.004, 1)
    baseInnerPath.stroke()

    let stageRect = NSRect(
        x: p * 0.17,
        y: p * 0.205,
        width: p * 0.66,
        height: p * 0.565
    )
    let stagePath = NSBezierPath(roundedRect: stageRect, xRadius: p * 0.075, yRadius: p * 0.075)

    withShadow(
        color: color(8, 12, 18, 0.38),
        blur: p * 0.035,
        offset: NSSize(width: 0, height: -p * 0.013)
    ) {
        NSGradient(colors: [
            color(45, 61, 76),
            color(23, 32, 43),
            color(8, 13, 21)
        ])!.draw(in: stagePath, angle: -55)
    }

    color(255, 255, 255, 0.18).setStroke()
    stagePath.lineWidth = max(p * 0.006, 1)
    stagePath.stroke()

    if pixels >= 128 {
        NSGraphicsContext.saveGraphicsState()
        stagePath.addClip()
        let sheenPath = NSBezierPath()
        sheenPath.move(to: NSPoint(x: stageRect.minX - p * 0.05, y: stageRect.maxY - p * 0.08))
        sheenPath.curve(
            to: NSPoint(x: stageRect.maxX + p * 0.04, y: stageRect.maxY - p * 0.205),
            controlPoint1: NSPoint(x: stageRect.midX - p * 0.13, y: stageRect.maxY + p * 0.04),
            controlPoint2: NSPoint(x: stageRect.midX + p * 0.18, y: stageRect.maxY - p * 0.20)
        )
        sheenPath.lineWidth = max(p * 0.018, 2)
        color(255, 255, 255, 0.10).setStroke()
        sheenPath.stroke()
        NSGraphicsContext.restoreGraphicsState()
    }

    let selectionRect = stageRect.insetBy(dx: p * 0.097, dy: p * 0.092)
    let bracketLength = p * 0.135
    let bracketWidth = max(p * 0.026, 2.0)

    withShadow(
        color: color(0, 8, 12, 0.48),
        blur: p * 0.014,
        offset: NSSize(width: 0, height: -p * 0.006)
    ) {
        drawCaptureBrackets(
            in: selectionRect,
            length: bracketLength,
            lineWidth: bracketWidth,
            color: color(73, 225, 245)
        )
    }

    drawCaptureBrackets(
        in: selectionRect.insetBy(dx: p * 0.003, dy: p * 0.003),
        length: bracketLength * 0.91,
        lineWidth: max(bracketWidth * 0.42, 1),
        color: color(255, 255, 255, 0.76)
    )

    drawApertureMark(
        center: NSPoint(x: selectionRect.midX, y: selectionRect.midY),
        radius: p * 0.079,
        pixels: p
    )

    return rep
}

func savePNG(_ rep: NSBitmapImageRep, to url: URL) throws {
    guard let data = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "generate_app_icon", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to encode PNG for \(url.lastPathComponent)"])
    }
    try data.write(to: url)
}

func writeContentsJSON(files: [(filename: String, spec: IconSpec)], to url: URL) throws {
    struct ImageEntry: Codable {
        let filename: String
        let idiom: String
        let scale: String
        let size: String
    }
    struct Root: Codable {
        let images: [ImageEntry]
        struct Info: Codable { let author: String; let version: Int }
        let info: Info
    }

    let images = files.map { f in
        ImageEntry(
            filename: f.filename,
            idiom: "mac",
            scale: "\(f.spec.scale)x",
            size: "\(f.spec.size)x\(f.spec.size)"
        )
    }

    let root = Root(images: images, info: .init(author: "xcode", version: 1))
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(root)
    try data.write(to: url)
}

// Main

do {
    try ensureDir(appIconDir)

    var written: [(String, IconSpec)] = []

    for spec in macIconSpecs {
        let pixels = spec.size * spec.scale
        let rep = drawAppIconBitmap(size: pixels)
        let filename = "appicon_\(spec.size)@\(spec.scale)x.png"
        let outURL = appIconDir.appendingPathComponent(filename)
        try savePNG(rep, to: outURL)
        written.append((filename, spec))
        fputs("Wrote \(outURL.path)\n", stderr)
    }

    let contentsURL = appIconDir.appendingPathComponent("Contents.json")
    try writeContentsJSON(files: written, to: contentsURL)
    fputs("Updated Contents.json\n", stderr)

    // Also write a 1024 preview to repo root for reference
    let preview = drawAppIconBitmap(size: 1024)
    let previewURL = URL(fileURLWithPath: currentDir).appendingPathComponent("ShotBarApp_Icon_1024.png")
    try savePNG(preview, to: previewURL)
    fputs("Wrote preview to \(previewURL.path)\n", stderr)

} catch {
    fputs("Error: \(error)\n", stderr)
    exit(1)
}

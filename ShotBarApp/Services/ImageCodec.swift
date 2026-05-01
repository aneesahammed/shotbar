import AppKit
import CoreImage
import ImageIO
import UniformTypeIdentifiers

enum ImageCodec {
    static func loadImage(from url: URL) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw NSError(domain: "ShotBar", code: -40, userInfo: [NSLocalizedDescriptionKey: "Could not load cached screenshot"])
        }
        return image
    }

    static func pngData(from cgImage: CGImage, dpi: Double? = nil) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, cgImage, imageProperties(format: .png, dpi: dpi) as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    static func writePNG(_ cgImage: CGImage, to url: URL, dpi: Double? = nil) throws {
        try write(cgImage, to: url, type: UTType.png.identifier as CFString, properties: imageProperties(format: .png, dpi: dpi))
    }

    static func writeJPG(_ cgImage: CGImage, to url: URL, quality: Double = 1.0, dpi: Double? = nil) throws {
        var props = imageProperties(format: .jpg, dpi: dpi)
        props[kCGImageDestinationLossyCompressionQuality] = quality
        props[kCGImagePropertyOrientation] = 1
        try write(cgImage, to: url, type: UTType.jpeg.identifier as CFString, properties: props)
    }

    static func thumbnail(from cgImage: CGImage, maxSide: CGFloat) -> CGImage {
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        let scale = min(maxSide / max(width, height), 1)
        let target = CGSize(width: max(1, round(width * scale)), height: max(1, round(height * scale)))

        guard let context = CGContext(
            data: nil,
            width: Int(target.width),
            height: Int(target.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return cgImage
        }
        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(origin: .zero, size: target))
        return context.makeImage() ?? cgImage
    }

    private static func write(_ cgImage: CGImage, to url: URL, type: CFString, properties: [CFString: Any]) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type, 1, nil) else {
            throw NSError(domain: "ShotBar", code: -1, userInfo: [NSLocalizedDescriptionKey: "Could not create image destination"])
        }
        CGImageDestinationAddImage(destination, cgImage, properties as CFDictionary)
        if !CGImageDestinationFinalize(destination) {
            throw NSError(domain: "ShotBar", code: -2, userInfo: [NSLocalizedDescriptionKey: "Could not write image"])
        }
    }

    private static func imageProperties(format: ImageFormat, dpi: Double?) -> [CFString: Any] {
        var props: [CFString: Any] = [
            kCGImageDestinationEmbedThumbnail: false,
            kCGImagePropertyColorModel: kCGImagePropertyColorModelRGB
        ]
        if format == .png {
            props[kCGImagePropertyPNGCompressionFilter] = 0
        }
        if let dpi {
            props[kCGImagePropertyDPIWidth] = dpi
            props[kCGImagePropertyDPIHeight] = dpi
        }
        return props
    }
}

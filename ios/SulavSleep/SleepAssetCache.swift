import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Launch-time decode cache for the sloth artwork. The retired city assets
/// are no longer prewarmed; the shared starry stage draws without bitmaps.
enum SleepAssetCache {
    #if canImport(UIKit)
    private static var decodedImages: [String: UIImage] = [:]
    private static var didPrewarm = false
    #endif

    static func prewarmCriticalAssets() {
        #if canImport(UIKit)
        guard !didPrewarm else { return }
        didPrewarm = true
        let phase = CityPhase.current()
        var names: [String] = []
        // The brand mark (welcome screen, questionnaire header) and the
        // splash continuation both draw before or during the first
        // interactive moments, so their art is prepaid too.
        names.append("HomeSloth\(phase.rawValue)Blink")
        names.append("SplashSloth")
        for name in names {
            guard let image = UIImage(named: name) else { continue }
            decodedImages[name] = image.decodedForDisplay()
        }
        #endif
    }

    #if canImport(UIKit)
    /// Main-thread only (all callers are view code). Decodes and caches on
    /// miss so phase-boundary crossfades pay each new asset once, off the
    /// interaction path.
    static func image(named name: String) -> UIImage? {
        if !didPrewarm {
            prewarmCriticalAssets()
        }
        if let cached = decodedImages[name] { return cached }
        guard let image = UIImage(named: name) else { return nil }
        let decoded = image.decodedForDisplay()
        decodedImages[name] = decoded
        return decoded
    }
    /// Render existing warm window pixels as lamplight without changing the
    /// artwork's silhouettes, geometry, or cool glass. Cached once per plane.
    static func illuminatedNightImage(named name: String) -> UIImage? {
        let key = name + ".lamplight"
        if let cached = decodedImages[key] { return cached }
        guard let source = image(named: name), let cg = source.cgImage else { return image(named: name) }
        let width = cg.width, height = cg.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let rendered: UIImage? = pixels.withUnsafeMutableBytes { bytes in
            guard let context = CGContext(data: bytes.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
            let data = bytes.bindMemory(to: UInt8.self)
            for offset in stride(from: 0, to: data.count, by: 4) {
                let r = Double(data[offset]), g = Double(data[offset + 1]), b = Double(data[offset + 2])
                // The source art's warm rectangles are lit windows; preserve
                // transparent edges and all blue/purple building structure.
                if data[offset + 3] > 240, r > 45, r > g * 1.18, r > b * 1.15 {
                    data[offset] = UInt8(min(255, r * 1.65 + 32))
                    data[offset + 1] = UInt8(min(225, g * 1.65 + 30))
                    data[offset + 2] = UInt8(min(145, b * 1.25 + 12))
                }
            }
            guard let output = context.makeImage() else { return nil }
            return UIImage(cgImage: output, scale: source.scale, orientation: source.imageOrientation)
        }
        if let rendered { decodedImages[key] = rendered }
        return rendered ?? source
    }
    #endif
}

#if canImport(UIKit)
private extension UIImage {
    func decodedForDisplay() -> UIImage {
        guard let cgImage else { return self }
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            UIImage(cgImage: cgImage, scale: scale, orientation: imageOrientation)
                .draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
#endif

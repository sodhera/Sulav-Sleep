import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

enum SleepAssetCache {
    static let pixelCityAssetNames = [
        "NightCitySky",
        "NightCityFarSkyline",
        "NightCityMidSkyline",
        "NightCityNearSkyline",
        "NightCityFrontSkyline",
    ]

    #if canImport(UIKit)
    private static var decodedImages: [String: UIImage] = [:]
    private static var didPrewarm = false
    #endif

    static func prewarmCriticalAssets() {
        #if canImport(UIKit)
        guard !didPrewarm else { return }
        didPrewarm = true
        decodedImages = Dictionary(
            uniqueKeysWithValues: pixelCityAssetNames.compactMap { name in
                guard let image = UIImage(named: name) else { return nil }
                return (name, image.decodedForDisplay())
            }
        )
        #endif
    }

    #if canImport(UIKit)
    static func image(named name: String) -> UIImage? {
        if decodedImages.isEmpty {
            prewarmCriticalAssets()
        }
        return decodedImages[name] ?? UIImage(named: name)
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


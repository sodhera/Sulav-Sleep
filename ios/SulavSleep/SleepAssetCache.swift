import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Launch-time decode cache for the big scene bitmaps. `UIImage(named:)` is
/// lazy — the expensive PNG decode happens at the first Core Animation commit
/// that draws the image — so without this, the six full-screen city planes
/// (and the brand-mark sloth) all decoded on the main thread in the same
/// beat the onboarding scene first appeared, which is exactly when the user
/// is watching. Decoding at `App.init` instead hides the cost behind the
/// launch storyboard.
///
/// Asset names are **phase-prefixed at load time** ("NightCitySkyBase",
/// "DayCityClouds", …), matching `citySpecs` in SleepBackground.swift, so the
/// prewarm list must be built from the *current* `CityPhase` — a fixed list
/// of night names decodes art a day/dusk open never draws. Misses are
/// decoded and cached on demand (e.g. the next phase's set when the scene
/// crossfades at a boundary), so any name is only ever decoded once per run.
enum SleepAssetCache {
    /// The six depth planes of the pixel city, in `citySpecs` order,
    /// *without* their phase prefix.
    static let cityLayerNames = [
        "CitySkyBase",
        "CityClouds",
        "CityFarSkyline",
        "CityMidSkyline",
        "CityNearSkyline",
        "CityFrontSkyline",
    ]

    #if canImport(UIKit)
    private static var decodedImages: [String: UIImage] = [:]
    private static var didPrewarm = false
    #endif

    static func prewarmCriticalAssets() {
        #if canImport(UIKit)
        guard !didPrewarm else { return }
        didPrewarm = true
        let phase = CityPhase.current()
        var names = cityLayerNames.map { phase.rawValue + $0 }
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

# Credits

## Artwork

- **Night city pixel art background** — CraftPix.net 2D Game Assets.
  Source: https://opengameart.org/content/night-city-pixel-art-background
  License: OGA-BY 3.0 (https://static.opengameart.org/OGA-BY-3.0.txt)
  Used (warm-tinted and darkened) as the base of the app's environment scene in
  `ios/SulavSleep/Images.xcassets/NightCity.imageset/`. The Day*/Dusk* layer
  variants are derived from the night layers by
  `scripts/generate-scene-variants.py`. Attribution is also shown in the app
  under Settings.

- **App icon: sleeping sloth on a pillow** — stock cartoon vector
  ("cute sloth sleeping pillow cartoon vector icon illustration", downloaded
  as `5100_4_10.eps`; original source/license to be confirmed before App
  Store release). Used recolored from its purple original by
  `scripts/generate-app-icon.py` in four places under
  `ios/SulavSleep/Images.xcassets/`: the app icon (amber/navy palette,
  `AppIcon.appiconset/`), the launch-screen splash sloth (icon colorway on
  transparent, `SplashSloth.imageset/`), the sleep screen's ember "night
  sloth" (`NightSloth.imageset/`), and Home's awake/drowsy day sloths with
  redrawn eyes (`HomeSlothAwake.imageset/`, `HomeSlothDrowsy.imageset/`).

- **Typeface: DM Sans** — by Colophon Foundry, Jonny Pinhorn and Indian Type
  Foundry, released under the **SIL Open Font License, Version 1.1**. Bundled
  as the two variable fonts (`opsz` 9–40, `wght` 100–1000) at
  `ios/SulavSleep/Resources/Fonts/DMSans.ttf` and `DMSans-Italic.ttf`, with
  the licence alongside them at `Resources/Fonts/OFL.txt`. The OFL permits
  bundling in an application, including a commercial one; it requires the
  licence to travel with the font files (it does) and forbids selling the
  fonts on their own. The font is copied into both the app and the widget
  extension bundles — see the Typography note in `DESIGN.md`.

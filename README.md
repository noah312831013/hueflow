# Hueflow

Living 3D gradient wallpapers and a screen saver for macOS, rendered natively with Metal.

```
native/   the Mac app (Swift + Metal), built with swiftc; no Xcode project
site/     the sales website (static HTML)
```

## The app

- **Rendering:** a Metal port of [ShaderGradient](https://github.com/ruucm/shadergradient) (MIT, © ruucm). It covers the plane, water and sphere shapes, the noise, the color formulas, the camera and the halftone grain. Wallpapers, the gallery, thumbnails and the screen saver all share one renderer.
- **UI:** an Apple TV–style gallery and a live editor (Shape / Colors / Effects / Camera), and saved gradients.
- **System:** a desktop-level window per display (each can be enabled and assigned separately) and a 🌈 menu bar item. It pauses on demand or on battery, and has an idle screen saver.
- **System Settings `.saver`:** the same Metal renderer, installed from the Screen Saver popover.
- **Licensing:** a 7-day free trial, then a Lemon Squeezy license key (`native/App/License.swift`).

```sh
cd native
./build.sh      # build/Hueflow.app + build/Hueflow.zip (also copied to site/downloads/); needs Xcode
./test.sh       # self-checks
open build/Hueflow.app
```

Settings are stored in `~/Library/Application Support/Hueflow/config.json`.

"Environment" lighting approximates the city/dawn/lobby HDRs with a procedural sky, so those presets differ slightly from shadergradient.co.

## The website

`site/index.html` is the landing page and `site/legal.html` holds the terms, privacy and refunds. The hero gradient is the ShaderGradient React library, bundled with:

```sh
npm install
npm run build   # site/hero.js
```

Host `site/` on any static host (Vercel, Netlify, GitHub Pages).

## Launch checklist

1. **Lemon Squeezy:** create the store and the product (US$9.99, one-time), enable license keys and set the activation limit to 3.
2. Put the IDs in `LicenseConfig` in `native/App/License.swift` (`storeID`, `productID`, `checkoutURL`).
3. Replace the checkout link in `site/index.html` if the product changes.
4. Have the terms in `site/legal.html` reviewed.
5. **Apple Developer Program** (US$99/year): create a Developer ID Application certificate, then run:
   ```sh
   xcrun notarytool store-credentials hueflow   # once
   DEVELOPER_ID="Developer ID Application: Your Name (TEAMID)" NOTARY_PROFILE=hueflow native/build.sh
   ```
   Without signing and notarization, other Macs will block the app.

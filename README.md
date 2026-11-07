# Hueflow

Living 3D gradient wallpapers and a screen saver for macOS, rendered natively with Metal.

```
native/   the Mac app (Swift + Metal), built with swiftc; no Xcode project
site/     the sales website (static HTML)
```

## The app

- **Rendering:** a Metal port of [ShaderGradient](https://github.com/ruucm/shadergradient) (MIT, © ruucm). It covers the plane, water and sphere shapes, the noise, the color formulas, the camera and the halftone grain. Wallpapers, the gallery, thumbnails and the screen saver all share one renderer.
- **Beyond ShaderGradient:** shape and color patterns (noise, warp, cells, ridged, waves) with scale and sharpness, mesh subdivision, grain amount and size, music-reactive strength (a Core Audio tap on the system output follows the bass; macOS 14.2+), depth-of-field bokeh (focus and blur, a 16-tap gather on the scene before the grain), optional 4× MSAA (on by default) and an optional Retina-resolution grain pass for smoother silhouettes. Gradients that use these no longer match shadergradient.co.
- **UI:** an Apple TV–style gallery and a live editor (Shape / Colors / Effects / Camera), and saved gradients.
- **System:** a desktop-level window per display (each can be enabled and assigned separately) and a 🌈 menu bar item. It pauses on demand, on battery or behind full-screen apps, and has an idle screen saver. A Performance submenu holds five options, all on by default: 30 fps wallpapers, a half-resolution 3D scene (grain stays full resolution), pausing while covered, depth/MSAA buffers in GPU tile memory, and 15 fps in Low Power Mode or when the Mac runs hot. `native/bench.sh` measures the GPU time per frame.
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

`site/index.html` is the landing page and `site/legal.html` holds the terms, privacy and refunds. The hero gradient and the "Make it yours" editor use the ShaderGradient React library. `site/build.mjs` hooks the library's shader compile so `site/src/patterns.js` can add the app's patterns to the editor. The hook matches `@shadergradient/react` 2.4.20 exactly (pinned in `package.json`), and the build fails if a library update changes that code. Bundle with:

```sh
npm install
npm run build   # site/hero.js
```

The gallery cards in `site/assets/cards/` are rendered by the app's own renderer, supersampled so the grain doesn't turn into moiré. Regenerate them after changing presets:

```sh
native/site-thumbs.sh
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

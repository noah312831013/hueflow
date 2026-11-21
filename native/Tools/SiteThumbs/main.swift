// Renders the website's images with the app's renderer: gallery cards from the presets and the pattern showcase.
// Run: ./site-thumbs.sh
import AppKit

let assets = URL(fileURLWithPath: CommandLine.arguments[1])
// Cards show at up to ~320 CSS px wide; 2× for Retina.
func write(_ props: Props, _ dir: String, _ name: String) throws {
    let d = assets.appendingPathComponent(dir)
    try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
    guard let img = Renderer.shared.thumbnail(props, pointSize: CGSize(width: 320, height: 200)),
          let jpg = NSBitmapImageRep(cgImage: img).representation(using: .jpeg, properties: [.compressionFactor: 0.88]) else { fatalError("render failed: \(name)") }
    try jpg.write(to: d.appendingPathComponent(name + ".jpg"))
    print("\(dir)/\(name).jpg")
}
for p in presets { try write(p.props, "cards", p.name.lowercased().replacingOccurrences(of: " ", with: "-")) }
// Same pattern on shape and color, on Universe's shape and camera, in grayscale so the pattern reads on its own.
var base = presets.first { $0.name == "Universe" }!.props
base["color1"] = .str("#ffffff"); base["color2"] = .str("#808080"); base["color3"] = .str("#000000")
for k in patternKinds.keys.sorted() {
    var p = base
    p["shapePattern"] = .str(k); p["colorPattern"] = .str(k); p["subdivision"] = .num(1); p["colorScale"] = .num(1.8)
    try write(p, "patterns", k)
}

// Afterglow (presets[0], the free wallpaper) is the brand image: website hero, app icon and favicon.
let brand = presets[0].props
guard let hero = Renderer.shared.thumbnail(brand, pointSize: CGSize(width: 960, height: 600), scale: 1),
      let heroJPG = NSBitmapImageRep(cgImage: hero).representation(using: .jpeg, properties: [.compressionFactor: 0.88]) else { fatalError("hero") }
try heroJPG.write(to: assets.appendingPathComponent("hero.jpg"))
print("hero.jpg")

/// macOS icon grid: an 824/1024 rounded square with a soft shadow. Grain off: it turns to noise at small sizes.
func icon(_ size: Int) -> CGImage {
    let s = CGFloat(size) / 1024
    var p = brand; p["grain"] = .str("off")
    guard let art = Renderer.shared.thumbnail(p, pointSize: CGSize(width: 412, height: 412)),
          let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { fatalError("icon") }
    let body = CGRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let shape = CGPath(roundedRect: body, cornerWidth: 185 * s, cornerHeight: 185 * s, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10 * s), blur: 20 * s, color: CGColor(gray: 0, alpha: 0.3))
    ctx.addPath(shape); ctx.setFillColor(CGColor(gray: 0, alpha: 1)); ctx.fillPath()
    ctx.restoreGState()
    ctx.addPath(shape); ctx.clip()
    ctx.draw(art, in: body)
    return ctx.makeImage()!
}
func png(_ img: CGImage, _ url: URL) throws { try NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])!.write(to: url) }
try png(icon(256), assets.appendingPathComponent("icon.png"))
let iconset = URL(fileURLWithPath: CommandLine.arguments[2])
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for pt in [16, 32, 128, 256, 512] {
    try png(icon(pt), iconset.appendingPathComponent("icon_\(pt)x\(pt).png"))
    try png(icon(pt * 2), iconset.appendingPathComponent("icon_\(pt)x\(pt)@2x.png"))
}
print("icon.png, Hueflow.icns")

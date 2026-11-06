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

// Self-checks for the props model and renderer setup. Run: ./test.sh
import Foundation

let json = #"{"type":"sphere","uTime":0,"grain":"off","animate":"off","axesHelper":"on","wireframe":false}"#
let decoded = try! JSONDecoder().decode(Props.self, from: Data(json.utf8))
assert(decoded["wireframe"] == .bool(false) && decoded["uTime"] == .num(0))
assert(try! JSONDecoder().decode(Props.self, from: JSONEncoder().encode(decoded)) == decoded, "JSON round-trip")

assert(hexColor("#ff8000") == SIMD3<Float>(1, 128 / 255, 0))
assert(hexColor("bad") == SIMD3<Float>(0, 0, 0))
let g = GradientParams(decoded)
assert(g.type == 2 && !g.grain && g.time(elapsed: 10) == 0, "animate off keeps uTime")
var r = GradientParams(["range": .str("enabled"), "rangeStart": .num(5), "rangeEnd": .num(10)])
assert(r.time(elapsed: 7) == 7, "range wraps into [start, end)")
r.approach(GradientParams(["brightness": .num(2)]), 0.5)
assert(abs(r.brightness - 1.6) < 1e-5, "eases toward target")

let pat = GradientParams(["shapePattern": .str("cells"), "colorPattern": .str("noise"), "colorScale": .num(99)])
assert(pat.shapePattern == 2 && pat.colorPattern == 1 && pat.colorScale == 5, "patterns parse; color 0 is the position gradient")
assert(GradientParams([:]).colorPattern == 0 && GradientParams(["shapePattern": .str("bogus")]).shapePattern == 0)

let cam: Props = ["type": .str("plane"), "cAzimuthAngle": .num(10), "cPolarAngle": .num(178), "cDistance": .num(4)]
assert(cam.camera(.orbit(dx: 50, dy: -10))["cAzimuthAngle"] == .num(350), "azimuth wraps into 0..<360")
assert(cam.camera(.orbit(dx: 0, dy: -10))["cPolarAngle"] == .num(180), "polar clamps at 180")
assert(cam.camera(.zoom(2))["cDistance"] == .num(2), "planes zoom by moving the camera closer")
let sph: Props = ["type": .str("sphere"), "cameraZoom": .num(10), "cAzimuthAngle": .num(180)]
assert(sph.camera(.zoom(2))["cameraZoom"] == .num(20), "spheres zoom the lens")
assert(sph.camera(.roll(30))["rotationZ"] == .num(-30), "roll follows the fingers when seen from behind")

let back: Props = ["type": .str("plane"), "cAzimuthAngle": .num(180), "cPolarAngle": .num(90), "cDistance": .num(3.6)]
let panned = back.camera(.pan(dx: 100, dy: 0, viewHeight: 800))
assert(panned.num("positionX", 0) < 0 && abs(panned.num("positionY", 0)) < 1e-9, "seen from -z, screen-right is world -x")
assert(back.camera(.pan(dx: 0, dy: 100, viewHeight: 800)).num("positionY", 0) < 0, "dragging down moves the model down")

assert(presets.count == 10 && presets[0].name == "Halo")
assert(Renderer.shared.snapshot(presets[0].props, width: 64, height: 40) != nil, "Metal renders offscreen")
let half = Renderer.shared.makeTargets(width: 101, height: 40, scale: 0.5)
assert(half.scene.width == 51 && half.scene.height == 20 && half.depth.width == 51, "half-res scene targets")
assert(half.scene.storageMode == .private, "the scene is read by the grain pass, so never memoryless")
let far = presets[0].props.merging(["cDistance": .num(14), "animate": .str("off")]) { $1 }
func pixels(_ p: Props) -> Data { Renderer.shared.snapshot(p, width: 96, height: 60)!.dataProvider!.data! as Data }
assert(pixels(far) == pixels(far.merging(["bokeh": .str("on"), "blur": .num(0)]) { $1 }), "bokeh with no blur is a no-op")
assert(pixels(far) != pixels(far.merging(["bokeh": .str("on"), "blur": .num(1)]) { $1 }), "bokeh blurs")
assert(GradientParams(["blur": .num(5), "focus": .num(-99)]).blur == 1 && GradientParams(["focus": .num(-99)]).focus == -10, "bokeh clamps")
// Beat envelope: a 60 Hz tone pulsing on and off twice a second rises on the pulses and falls between them.
var beat = BeatEnvelope(), highs: [Float] = [], lows: [Float] = []
for block in 0..<200 { // 200 × 10 ms at 48 kHz
    let on = (block / 25) % 2 == 0
    let samples = (0..<480).map { i -> Float in on ? 0.5 * sin(2 * .pi * 60 * Float(block * 480 + i) / 48000) : 0 }
    samples.withUnsafeBufferPointer { beat.feed($0, channels: 1, sampleRate: 48000) }
    if block >= 100 { (block % 25 == 24 ? (on ? { highs.append(beat.level) } : { lows.append(beat.level) }) : {})() }
}
assert(highs.allSatisfy { $0 > 0.7 } && lows.allSatisfy { $0 < 0.2 }, "beat envelope follows the pulses: \(highs) \(lows)")
var hiss = BeatEnvelope()
let noise = (0..<48000).map { _ in Float.random(in: -0.001...0.001) }
noise.withUnsafeBufferPointer { hiss.feed($0, channels: 2, sampleRate: 48000) }
assert(hiss.level < 0.01, "near-silence stays still")
print("all tests passed")

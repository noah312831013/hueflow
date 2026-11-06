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

assert(presets.count == 10 && presets[0].name == "Halo")
assert(Renderer.shared.snapshot(presets[0].props, width: 64, height: 40) != nil, "Metal renders offscreen")
print("all tests passed")

// GPU cost of one wallpaper frame (scene pass + grain pass), timed with the command buffer's GPU clock.
// Run: ./bench.sh
import AppKit
import Metal

let r = Renderer.shared
func gpuMs(_ props: Props, w: Int, h: Int, scale: Float = 1, frames: Int = 90) -> Double {
    let p = GradientParams(props)
    let targets = r.makeTargets(width: w, height: h, scale: scale)
    let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: Renderer.outputFormat, width: w, height: h, mipmapped: false)
    td.usage = .renderTarget; td.storageMode = .private
    let drawable = r.device.makeTexture(descriptor: td)!
    var total = 0.0
    for i in 0..<(frames + 10) {
        let cmd = r.queue.makeCommandBuffer()!
        r.encode(cmd, params: p, time: p.time(elapsed: Double(i) / 60), fade: 1, targets: targets, target: drawable, pointSize: CGSize(width: w, height: h))
        cmd.commit(); cmd.waitUntilCompleted()
        if i >= 10 { total += cmd.gpuEndTime - cmd.gpuStartTime } // first frames warm up caches
    }
    return total / Double(frames) * 1000
}

let water = presets.first { $0.props.str("type", "") == "waterPlane" }!.props
let cases: [(String, Props)] = [
    ("presets (avg of 10)", [:]),
    ("heavy: warp shape sub2 + cells color", water.merging(["shapePattern": .str("warp"), "subdivision": .num(2), "colorPattern": .str("cells")]) { $1 }),
]
// Variants: what the Performance options change per frame (30 fps halves the per-second figures on its own).
let variants: [(String, Bool, Float)] = [("baseline", false, 1), ("tile memory", true, 1), ("half-res", false, 0.5), ("tile + half-res", true, 0.5)]
for (w, h) in [(1512, 982), (2560, 1440)] {
    for aa in [false, true] {
        r.antialias = aa
        for (name, props) in cases {
            var line = String(format: "%4dx%-4d msaa:%@  %@\n", w, h, aa ? "on " : "off", name as NSString)
            for (vname, tile, scale) in variants {
                r.tileMemory = tile
                let ms = props.isEmpty ? presets.map { gpuMs($0.props, w: w, h: h, scale: scale) }.reduce(0, +) / Double(presets.count)
                                       : gpuMs(props, w: w, h: h, scale: scale)
                line += String(format: "    %-16@ %5.2f ms/frame  %4.0f ms GPU/s @60  %4.0f @30\n", vname as NSString, ms, ms * 60, ms * 30)
            }
            print(line, terminator: "")
        }
    }
}

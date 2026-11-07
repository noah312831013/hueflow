// ShaderGradient props: a flat key -> string/number/bool map, same shape as ShaderGradient's own props,
// so config files and presets round-trip unchanged.
import Foundation
import simd

enum PropValue: Codable, Hashable {
    case str(String), num(Double), bool(Bool)

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .num(n) }
        else { self = .str(try c.decode(String.self)) }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .str(let s): try c.encode(s)
        case .num(let n): try c.encode(n)
        case .bool(let b): try c.encode(b)
        }
    }
}

typealias Props = [String: PropValue]

extension Dictionary where Key == String, Value == PropValue {
    func num(_ k: String, _ d: Double) -> Double {
        switch self[k] {
        case .num(let n)?: return n
        case .str(let s)?: return Double(s) ?? d
        default: return d
        }
    }
    func str(_ k: String, _ d: String) -> String {
        if case .str(let s)? = self[k] { return s }
        return d
    }
    /// Stable JSON, used as identity for thumbnails and "is this the current wallpaper".
    var key: String {
        let e = JSONEncoder(); e.outputFormatting = .sortedKeys
        return String(decoding: (try? e.encode(self)) ?? Data(), as: UTF8.self)
    }
}

struct Entry: Codable, Hashable, Identifiable {
    var id: String?
    var name: String
    var props: Props
    var builtin: Bool? = nil
    var identity: String { id ?? "preset:" + name }
}

let presets: [Entry] = {
    let list = (try? JSONDecoder().decode([Entry].self, from: Data(presetsJSON.utf8))) ?? []
    return list.map { Entry(id: "preset:" + $0.name, name: $0.name, props: $0.props, builtin: true) }
}()

/// A trackpad/mouse camera change in the editor preview.
enum CameraGesture {
    case orbit(dx: Double, dy: Double) // points, AppKit drag deltas (right +, down +)
    case zoom(Double)                  // factor, > 1 = closer
    case roll(Double)                  // degrees, counterclockwise on screen
    case pan(dx: Double, dy: Double, viewHeight: Double) // points, like orbit; viewHeight scales points to world units
}

let cameraKeys = ["cAzimuthAngle", "cPolarAngle", "cDistance", "cameraZoom", "rotationZ", "positionX", "positionY", "positionZ"]

extension Dictionary where Key == String, Value == PropValue {
    /// Moves the camera the way the content follows the fingers, within the editor sliders' ranges.
    func camera(_ g: CameraGesture) -> Props {
        var p = self
        func set(_ k: String, _ v: Double, _ lo: Double, _ hi: Double, step: Double = 0.1) {
            p[k] = .num((Swift.min(hi, Swift.max(lo, v)) / step).rounded() * step)
        }
        let az = num("cAzimuthAngle", 180)
        switch g {
        case let .orbit(dx, dy):
            let a = (az - dx * 0.4).truncatingRemainder(dividingBy: 360)
            set("cAzimuthAngle", a < 0 ? a + 360 : a, 0, 360)
            set("cPolarAngle", num("cPolarAngle", 90) - dy * 0.4, 0, 180)
        case let .zoom(f):
            // The renderer zooms the sphere's lens but moves the camera for planes (GradientParams/uniforms).
            if str("type", "plane") == "sphere" { set("cameraZoom", num("cameraZoom", 1) * f, 0.1, 30) }
            else { set("cDistance", num("cDistance", 3.6) / f, 0.1, 20) }
        case let .roll(deg):
            // Seen from behind (camera on -z), a model rotation about z turns the other way on screen.
            let facing = cos(az * .pi / 180) >= 0 ? 1.0 : -1.0
            set("rotationZ", num("rotationZ", 0) + deg * facing, -360, 360)
        case let .pan(dx, dy, viewHeight):
            // Move the model along the camera's screen axes (same camera as Renderer.uniforms/lookAt), so it tracks the
            // fingers: world units per point = visible height at the target / view height.
            let sphere = str("type", "plane") == "sphere"
            let a = az * .pi / 180, pol = Swift.max(1e-3, Swift.min(.pi - 1e-3, num("cPolarAngle", 90) * .pi / 180))
            let eye = SIMD3(sin(pol) * sin(a), cos(pol), sin(pol) * cos(a))
            let f = -eye, right = simd_normalize(simd_cross(f, SIMD3(0, 1, 0))), up = simd_cross(right, f)
            let dist = sphere ? 14 : num("cDistance", 3.6), zoom = sphere ? num("cameraZoom", 1) : 1
            let k = 2 * tan(num("fov", 45) * .pi / 360) * dist / zoom / Swift.max(1, viewHeight)
            let move = (right * dx - up * dy) * k
            set("positionX", num("positionX", 0) + move.x, -5, 5, step: 0.001)
            set("positionY", num("positionY", 0) + move.y, -5, 5, step: 0.001)
            set("positionZ", num("positionZ", 0) + move.z, -5, 5, step: 0.001)
        }
        return p
    }
}

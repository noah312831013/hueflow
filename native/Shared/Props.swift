// ShaderGradient props: a flat key -> string/number/bool map, same shape as ShaderGradient's own props,
// so config files and presets round-trip unchanged.
import Foundation

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

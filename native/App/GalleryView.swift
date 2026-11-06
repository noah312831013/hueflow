// Apple TV–style gallery of presets + saved gradients, with an in-place parameter editor.
// One live Metal gradient is the backdrop for both views: the gallery previews the focused card,
// the editor previews the edited props, and prop changes ease in instead of reloading.
import AppKit
import SwiftUI

let typeNames: KeyValuePairs<String, String> = ["plane": "Plane", "sphere": "Sphere", "waterPlane": "Water"]
let onOff: KeyValuePairs<String, String> = ["on": "On", "off": "Off"]

enum ControlKind {
    case options(KeyValuePairs<String, String>)
    case range(Double, Double, Double)
    case color
}

struct ControlSpec: Identifiable {
    let key: String, label: String, kind: ControlKind
    var show: (Props) -> Bool = { _ in true }
    /// Slider value when the prop is missing, if not the range's low end (must match the renderer's default).
    var fallback: Double? = nil
    var id: String { key }
}

private let isSphere: (Props) -> Bool = { $0.str("type", "plane") == "sphere" }
private let isEnv: (Props) -> Bool = { $0.str("lightType", "3d") == "env" }
private let hasGrain: (Props) -> Bool = { $0.str("grain", "on") == "on" }

/// Editor controls, grouped by tab, with their ranges.
let tabs: [(String, [ControlSpec])] = [
    ("Shape", [
        ControlSpec(key: "type", label: "Type", kind: .options(typeNames)),
        ControlSpec(key: "animate", label: "Animate", kind: .options(onOff)),
        ControlSpec(key: "uSpeed", label: "Speed", kind: .range(0, 2, 0.1)),
        ControlSpec(key: "uStrength", label: "Strength", kind: .range(0, 10, 0.1)),
        ControlSpec(key: "uDensity", label: "Density", kind: .range(0, 7, 0.1)),
        ControlSpec(key: "uFrequency", label: "Frequency", kind: .range(0, 10, 0.1), show: isSphere),
        ControlSpec(key: "uAmplitude", label: "Spiral", kind: .range(0, 10, 0.1), show: isSphere),
        ControlSpec(key: "subdivision", label: "Subdivision", kind: .range(0, 2, 1)),
    ]),
    ("Colors", [
        ControlSpec(key: "color1", label: "Color 1", kind: .color),
        ControlSpec(key: "color2", label: "Color 2", kind: .color),
        ControlSpec(key: "color3", label: "Color 3", kind: .color),
    ]),
    ("Effects", [
        ControlSpec(key: "grain", label: "Grain", kind: .options(onOff)),
        ControlSpec(key: "grainAmount", label: "Grain Amount", kind: .range(0, 1, 0.05), show: hasGrain, fallback: 1),
        ControlSpec(key: "grainSize", label: "Grain Size", kind: .range(1, 8, 0.5), show: hasGrain, fallback: 2),
        ControlSpec(key: "lightType", label: "Lighting", kind: .options(["3d": "Lights", "env": "Environment"])),
        ControlSpec(key: "brightness", label: "Brightness", kind: .range(0.1, 3, 0.1), show: { !isEnv($0) }),
        ControlSpec(key: "envPreset", label: "Environment", kind: .options(["city": "City", "dawn": "Dawn", "lobby": "Lobby"]), show: isEnv),
        ControlSpec(key: "reflection", label: "Reflection", kind: .range(0, 1, 0.1), show: isEnv),
    ]),
    ("Camera", [
        ControlSpec(key: "cAzimuthAngle", label: "Azimuth", kind: .range(0, 360, 1)),
        ControlSpec(key: "cPolarAngle", label: "Polar", kind: .range(0, 180, 1)),
        ControlSpec(key: "cDistance", label: "Distance", kind: .range(0, 20, 0.1)),
        ControlSpec(key: "cameraZoom", label: "Zoom", kind: .range(0.1, 30, 0.1)),
        ControlSpec(key: "positionX", label: "Position X", kind: .range(-5, 5, 0.1)),
        ControlSpec(key: "positionY", label: "Position Y", kind: .range(-5, 5, 0.1)),
        ControlSpec(key: "positionZ", label: "Position Z", kind: .range(-5, 5, 0.1)),
        ControlSpec(key: "rotationX", label: "Rotation X", kind: .range(-360, 360, 1)),
        ControlSpec(key: "rotationY", label: "Rotation Y", kind: .range(-360, 360, 1)),
        ControlSpec(key: "rotationZ", label: "Rotation Z", kind: .range(-360, 360, 1)),
    ]),
]

let tvSpring = Animation.spring(response: 0.45, dampingFraction: 0.82)

// MARK: - Metal views in SwiftUI

struct LiveGradient: NSViewRepresentable {
    let props: Props
    func makeNSView(context: Context) -> GradientView { GradientView(props: props) }
    func updateNSView(_ v: GradientView, context: Context) { if v.props != props { v.props = props } }
}

/// Real renders of gradients for the cards, made on demand and kept in memory.
@MainActor
enum Thumbs {
    private static var cache: [String: NSImage] = [:]
    static func image(_ props: Props) -> NSImage? {
        if let i = cache[props.key] { return i }
        // Card is 224×140 pt. The grain's 2 pt dot grid aliases into moiré when resampled, so render 3× the card's
        // Retina pixels with the live preview's grain scale and filter down to 2×.
        let pt = CGSize(width: 224, height: 140), w = 448, h = 280
        guard let big = Renderer.shared.snapshot(props, width: w * 3, height: h * 3, elapsed: 3.5, pointSize: pt),
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(big, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let cg = ctx.makeImage() else { return nil }
        let i = NSImage(cgImage: cg, size: pt)
        cache[props.key] = i
        return i
    }
}

// MARK: - Root

struct GalleryRoot: View {
    @ObservedObject var store: Store
    @ObservedObject var license: License
    @State private var showLicense = false
    @State private var focused: Entry = presets[0]
    @State private var editing: Entry?
    @State private var draft: Props = [:]
    @State private var showSaver = false

    var body: some View {
        ZStack {
            LiveGradient(props: editing == nil ? focused.props : draft)
                .ignoresSafeArea()
            if let e = editing {
                EditorView(store: store, entry: e, props: $draft, onClose: close, onSaved: { editing = $0 })
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .trailing).combined(with: .opacity)))
            } else {
                browse.transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
            if let t = store.toast {
                VStack {
                    Spacer()
                    Text(t).font(.system(size: 14, weight: .semibold)).padding(.horizontal, 20).padding(.vertical, 12)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.bottom, 32)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .sheet(isPresented: Binding(get: { showLicense || license.state == .expired }, set: { showLicense = $0 })) {
            LicenseSheet(license: license)
        }
        .animation(tvSpring, value: editing?.identity)
        .animation(tvSpring, value: store.toast)
        .preferredColorScheme(.dark)
        .onAppear { focused = store.cfg.default.map { d in presets.first { $0.props.key == d.props.key } ?? d } ?? presets[0] }
    }

    private func open(_ e: Entry) { draft = e.props; editing = e }
    private func close() {
        if let e = editing { focused = Entry(id: e.id, name: e.name, props: draft, builtin: e.builtin) }
        editing = nil
    }

    private var browse: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                Button { showLicense = true } label: {
                    switch license.state {
                    case .trial(let days): Label(days == 1 ? "1 day left · Buy" : "\(days) days left · Buy", systemImage: "sparkles")
                    case .licensed: Label("Hueflow", systemImage: "checkmark.seal.fill")
                    case .expired: Label("Trial ended", systemImage: "lock.fill")
                    }
                }
                .buttonStyle(GlassButton())
                .padding(.leading, 64) // clear the traffic lights
                Spacer()
                Button { showSaver.toggle() } label: { Label("Screen Saver", systemImage: "moon.stars.fill") }
                    .buttonStyle(GlassButton())
                    .popover(isPresented: $showSaver, arrowEdge: .bottom) { SaverPopover(store: store) }
            }
            .padding(.top, 14).padding(.horizontal, 28)

            Spacer()

            VStack(alignment: .leading, spacing: 6) {
                Text(focused.builtin == true ? "Featured" : "My Gradients").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white.opacity(0.7))
                    .textCase(.uppercase)
                Text(focused.name).font(.system(size: 52, weight: .bold)).shadow(color: .black.opacity(0.3), radius: 16)
                    .contentTransition(.opacity)
                    .id(focused.name)
                HStack(spacing: 10) {
                    Button { store.apply(focused); store.show("Set as wallpaper") } label: { Label("Set as Wallpaper", systemImage: "desktopcomputer") }
                        .buttonStyle(PrimaryButton())
                    Button { open(focused) } label: { Label("Edit", systemImage: "slider.horizontal.3") }
                        .buttonStyle(GlassButton())
                }
                .padding(.top, 8)
            }
            .padding(.horizontal, 48)
            .animation(.easeInOut(duration: 0.3), value: focused.name)

            VStack(alignment: .leading, spacing: 18) {
                Row(title: "Featured", entries: presets, store: store, focused: $focused, open: open)
                if !store.cfg.custom.isEmpty {
                    Row(title: "My Gradients", entries: store.cfg.custom, store: store, focused: $focused, open: open)
                }
            }
            .padding(.top, 28).padding(.bottom, 28)
        }
        .background(alignment: .bottom) {
            LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .top, endPoint: .bottom).frame(height: 520).allowsHitTesting(false)
        }
    }
}

// MARK: - Cards

struct Row: View {
    let title: String
    let entries: [Entry]
    @ObservedObject var store: Store
    @Binding var focused: Entry
    let open: (Entry) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 17, weight: .semibold)).padding(.horizontal, 48)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 22) {
                    ForEach(entries, id: \.identity) { e in
                        Card(entry: e, current: store.cfg.default?.props.key == e.props.key, focused: focused.identity == e.identity)
                            .onHover { if $0 { focused = e } }
                            .onTapGesture { open(e) }
                            .contextMenu {
                                Button("Set as Wallpaper") { store.apply(e); store.show("Set as wallpaper") }
                                Button("Edit") { open(e) }
                                if let id = e.id, e.builtin != true {
                                    Divider()
                                    Button("Delete", role: .destructive) { store.deleteCustom(id) }
                                }
                            }
                    }
                }
                .padding(.horizontal, 48).padding(.vertical, 18)
            }
            .frame(height: 210)
            .scrollClipDisabled() // let the focused card's scale and shadow spill past the row instead of being cut off
        }
    }
}

struct Card: View {
    let entry: Entry
    let current: Bool
    let focused: Bool
    @State private var image: NSImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let image { Image(nsImage: image).resizable().aspectRatio(contentMode: .fill) }
                    else { LinearGradient(colors: [entry.props.str("color1", "#000"), entry.props.str("color2", "#000"), entry.props.str("color3", "#000")].map(Color.init(hex:)), startPoint: .topLeading, endPoint: .bottomTrailing) }
                }
                .frame(width: 224, height: 140)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                // Apple TV focus sheen
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(
                    LinearGradient(colors: [.white.opacity(focused ? 0.22 : 0), .clear], startPoint: .topLeading, endPoint: .center)))
                if current {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 18)).symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .black.opacity(0.35)).padding(8)
                }
            }
            .shadow(color: .black.opacity(focused ? 0.5 : 0.25), radius: focused ? 22 : 8, y: focused ? 14 : 4)
            Text(entry.name).font(.system(size: 13, weight: .medium)).foregroundStyle(.white.opacity(focused ? 1 : 0.65)).lineLimit(1)
        }
        .scaleEffect(focused ? 1.1 : 1, anchor: .center)
        .zIndex(focused ? 1 : 0)
        .animation(tvSpring, value: focused)
        .task(id: entry.props.key) { image = Thumbs.image(entry.props) }
    }
}

// MARK: - Editor

struct EditorView: View {
    @ObservedObject var store: Store
    let entry: Entry
    @Binding var props: Props
    let onClose: () -> Void
    let onSaved: (Entry) -> Void
    @State private var tab = "Shape"
    @State private var name = ""
    @State private var target: UInt32 = 0 // 0 = all displays

    var body: some View {
        HStack {
            Spacer()
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Button(action: onClose) { Image(systemName: "chevron.left").font(.system(size: 15, weight: .semibold)) }
                        .buttonStyle(GlassButton(round: true))
                    TextField("Name", text: $name).textFieldStyle(.plain).font(.system(size: 22, weight: .bold))
                }
                Picker("Section", selection: $tab.animation(tvSpring)) {
                    ForEach(tabs, id: \.0) { Text($0.0).tag($0.0) }
                }
                .pickerStyle(.segmented).labelsHidden()

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(tabs.first { $0.0 == tab }!.1.filter { $0.show(props) }) { c in
                            ControlRow(spec: c, props: $props)
                        }
                    }
                    .padding(.vertical, 4)
                    .id(tab)
                    .transition(.opacity.combined(with: .offset(y: 8)))
                }

                Picker("Apply to", selection: $target) {
                    Text("All Displays").tag(UInt32(0))
                    ForEach(store.displays) { Text($0.label).tag($0.id) }
                }

                VStack(spacing: 8) {
                    Button { store.apply(Entry(name: name, props: props), to: target == 0 ? nil : target); store.show("Set as wallpaper") } label: {
                        Text("Set as Wallpaper").frame(maxWidth: .infinity)
                    }.buttonStyle(PrimaryButton())
                    HStack(spacing: 8) {
                        Button("Save") { save() }.buttonStyle(GlassButton(stretch: true))
                        Button("Revert") { withAnimation(tvSpring) { props = entry.props } }.buttonStyle(GlassButton(stretch: true))
                    }
                }
            }
            .padding(22)
            .frame(width: 380)
            .background(.black.opacity(0.32), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(.white.opacity(0.12)))
            .shadow(color: .black.opacity(0.35), radius: 30)
            .padding(.top, 44).padding([.bottom, .trailing], 20)
        }
        .onAppear { name = entry.builtin == true ? "\(entry.name) Copy" : entry.name }
    }

    private func save() {
        let n = name.trimmingCharacters(in: .whitespaces).isEmpty ? "Untitled" : name
        let id = store.saveCustom(Entry(id: entry.builtin == true ? nil : entry.id, name: n, props: props))
        onSaved(Entry(id: id, name: n, props: props))
        store.show("Saved to My Gradients")
    }
}

struct ControlRow: View {
    let spec: ControlSpec
    @Binding var props: Props

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            switch spec.kind {
            case .options(let opts):
                Text(spec.label).font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.75))
                Picker(spec.label, selection: Binding(get: { props.str(spec.key, opts.first!.key) }, set: { props[spec.key] = .str($0) })) {
                    ForEach(opts, id: \.key) { Text($0.value).tag($0.key) }
                }
                .pickerStyle(.segmented).labelsHidden()
            case .range(let lo, let hi, let step):
                let value = Binding(get: { min(hi, max(lo, props.num(spec.key, spec.fallback ?? lo))) },
                                    set: { props[spec.key] = .num(($0 / step).rounded() * step) })
                HStack {
                    Text(spec.label).font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.75))
                    Spacer()
                    Text(step < 1 ? String(format: step < 0.1 ? "%.2f" : "%.1f", value.wrappedValue) : String(Int(value.wrappedValue)))
                        .font(.system(size: 12, weight: .medium).monospacedDigit())
                }
                Slider(value: value, in: lo...hi).controlSize(.small)
            case .color:
                HStack {
                    Text(spec.label).font(.system(size: 13, weight: .medium))
                    Spacer()
                    Text(props.str(spec.key, "#000000")).font(.system(size: 12).monospaced()).foregroundStyle(.secondary)
                    ColorPicker(spec.label, selection: Binding(get: { Color(hex: props.str(spec.key, "#000000")) },
                                                              set: { props[spec.key] = .str($0.hex) }), supportsOpacity: false)
                        .labelsHidden()
                }
            }
        }
    }
}

// MARK: - License

struct LicenseSheet: View {
    @ObservedObject var license: License
    @Environment(\.dismiss) private var dismiss
    @State private var key = ""
    @State private var error: String?
    @State private var busy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Hueflow").font(.system(size: 26, weight: .bold))
            switch license.state {
            case .licensed:
                Label("Activated on this Mac. Thank you!", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
                HStack {
                    Button("Deactivate This Mac") { Task { busy = true; await license.deactivate(); busy = false } }.disabled(busy)
                    Spacer()
                    Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
                }
            case .trial, .expired:
                if case .trial(let days) = license.state {
                    Text(days == 1 ? "1 day left in your free trial. Buy once, keep it forever." : "\(days) days left in your free trial. Buy once, keep it forever.").foregroundStyle(.secondary)
                } else {
                    Text("Your free trial has ended. Buy Hueflow and enter your license key to keep your live wallpapers and screen saver.").foregroundStyle(.secondary)
                }
                Button { NSWorkspace.shared.open(LicenseConfig.checkoutURL) } label: {
                    Text("Buy Hueflow").frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButton())
                Divider()
                Text("Already bought it? Paste the license key from your receipt email:").font(.callout)
                TextField("XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX", text: $key).textFieldStyle(.roundedBorder).font(.body.monospaced())
                if let error { Text(error).font(.callout).foregroundStyle(.red) }
                HStack {
                    if case .trial = license.state { Button("Later") { dismiss() } }
                    Spacer()
                    Button(busy ? "Activating…" : "Activate") {
                        busy = true; error = nil
                        Task {
                            do { try await license.activate(key) } catch { self.error = error.localizedDescription }
                            busy = false
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(busy || key.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .padding(24)
        .frame(width: 420)
        .interactiveDismissDisabled(license.state == .expired)
    }
}

// MARK: - Screen saver popover

struct SaverPopover: View {
    @ObservedObject var store: Store
    @State private var installing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Toggle("Start when idle", isOn: Binding(get: { store.cfg.saver.enabled }, set: { v in store.updateSaver { $0.enabled = v } }))
            Picker("Idle time", selection: Binding(get: { store.cfg.saver.minutes }, set: { v in store.updateSaver { $0.minutes = v } })) {
                ForEach(SaverSettings.minuteChoices, id: \.self) { Text($0 == 1 ? "1 minute" : "\($0) minutes").tag($0) }
            }
            HStack {
                Text("Content").fixedSize()
                Spacer()
                Picker("Content", selection: Binding(get: { store.cfg.saver.source }, set: { v in store.updateSaver { $0.source = v } })) {
                    Text("Shuffle all").tag("shuffle")
                    Text("Current wallpaper").tag("wallpaper")
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
            }
            Toggle("Show clock", isOn: Binding(get: { store.cfg.saver.clock }, set: { v in store.updateSaver { $0.clock = v } }))
            Divider()
            HStack {
                Button("Preview") { store.startSaver() }
                Spacer()
                Button(installing ? "Installing…" : "Install in System Settings") {
                    installing = true
                    Task {
                        do {
                            try await store.installSaver()
                            store.show("Installed: System Settings › Wallpaper › Screen Saver… › Other")
                        } catch { store.show("Install failed") }
                        installing = false
                    }
                }
                .disabled(installing)
            }
        }
        .padding(18)
        .frame(width: 360)
    }
}

// MARK: - Styles & helpers

struct PrimaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 14, weight: .semibold)).foregroundStyle(.black)
            .padding(.horizontal, 20).padding(.vertical, 10)
            .background(.white, in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(tvSpring, value: configuration.isPressed)
    }
}

struct GlassButton: ButtonStyle {
    var round = false
    var stretch = false
    @State private var hover = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 14, weight: .semibold))
            .frame(maxWidth: stretch ? .infinity : nil)
            .padding(.horizontal, round ? 10 : 16).padding(.vertical, 9)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().fill(.white.opacity(hover ? 0.12 : 0)))
            .scaleEffect(configuration.isPressed ? 0.95 : hover ? 1.04 : 1)
            .animation(tvSpring, value: configuration.isPressed)
            .animation(tvSpring, value: hover)
            .onHover { hover = $0 }
    }
}

extension Color {
    init(hex: String) {
        let c = hexColor(hex)
        self.init(.sRGB, red: Double(c.x), green: Double(c.y), blue: Double(c.z))
    }
    var hex: String {
        let c = NSColor(self).usingColorSpace(.sRGB) ?? .black
        return String(format: "#%02x%02x%02x", Int((c.redComponent * 255).rounded()), Int((c.greenComponent * 255).rounded()), Int((c.blueComponent * 255).rounded()))
    }
}

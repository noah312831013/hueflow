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
    /// Shown only under the tab's "Advanced" disclosure.
    var advanced = false
    var id: String { key }
}

private let isSphere: (Props) -> Bool = { $0.str("type", "plane") == "sphere" }
private let isEnv: (Props) -> Bool = { $0.str("lightType", "3d") == "env" }
private let hasColorPattern: (Props) -> Bool = { $0.str("colorPattern", "position") != "position" }
let patternNames: KeyValuePairs<String, String> = ["noise": "Noise", "warp": "Warp", "cells": "Cells", "ridged": "Ridged", "waves": "Waves"]
private let hasGrain: (Props) -> Bool = { $0.str("grain", "on") == "on" }
private let hasMusic: (Props) -> Bool = { $0.str("music", "off") == "on" }
private let hasBokeh: (Props) -> Bool = { $0.str("bokeh", "off") == "on" }

/// Editor controls, grouped by tab, with their ranges.
let tabs: [(String, [ControlSpec])] = [
    ("Shape", [
        ControlSpec(key: "type", label: "Type", kind: .options(typeNames)),
        ControlSpec(key: "shapePattern", label: "Pattern", kind: .options(patternNames)),
        ControlSpec(key: "uSpeed", label: "Speed", kind: .range(0, 2, 0.1)),
        ControlSpec(key: "uStrength", label: "Strength", kind: .range(0, 10, 0.1)),
        ControlSpec(key: "music", label: "Move to Music", kind: .options(["off": "Off", "on": "On"])),
        ControlSpec(key: "musicTarget", label: "Moves", kind: .options(["strength": "Strength", "color": "Color"]), show: hasMusic),
        ControlSpec(key: "musicIntensity", label: "Beat Intensity", kind: .range(0, 3, 0.1), show: hasMusic, fallback: 1),
        ControlSpec(key: "uDensity", label: "Density", kind: .range(0, 7, 0.1)),
        ControlSpec(key: "animate", label: "Animate", kind: .options(onOff), advanced: true),
        ControlSpec(key: "shapeSharpness", label: "Sharpness", kind: .range(0, 1, 0.05), fallback: 0.5, advanced: true),
        ControlSpec(key: "subdivision", label: "Subdivision", kind: .range(0, 2, 1), advanced: true),
        ControlSpec(key: "uFrequency", label: "Frequency", kind: .range(0, 10, 0.1), show: isSphere, advanced: true),
        ControlSpec(key: "uAmplitude", label: "Spiral", kind: .range(0, 10, 0.1), show: isSphere, advanced: true),
    ]),
    ("Colors", [
        ControlSpec(key: "color1", label: "Color 1", kind: .color),
        ControlSpec(key: "color2", label: "Color 2", kind: .color),
        ControlSpec(key: "color3", label: "Color 3", kind: .color),
        ControlSpec(key: "colorPattern", label: "Pattern", kind: .options(["position": "Gradient", "noise": "Noise", "warp": "Warp", "cells": "Cells", "ridged": "Ridged", "waves": "Waves"])),
        ControlSpec(key: "saturation", label: "Saturation", kind: .range(0, 2, 0.05), fallback: 1),
        ControlSpec(key: "colorScale", label: "Scale", kind: .range(0.1, 5, 0.1), show: hasColorPattern, fallback: 1, advanced: true),
        ControlSpec(key: "colorSharpness", label: "Sharpness", kind: .range(0, 1, 0.05), show: hasColorPattern, fallback: 0.5, advanced: true),
    ]),
    ("Effects", [
        ControlSpec(key: "grain", label: "Grain", kind: .options(onOff)),
        ControlSpec(key: "grainAmount", label: "Grain Amount", kind: .range(0, 1, 0.05), show: hasGrain, fallback: 1, advanced: true),
        ControlSpec(key: "grainSize", label: "Grain Size", kind: .range(1, 8, 0.5), show: hasGrain, fallback: 2, advanced: true),
        ControlSpec(key: "lightType", label: "Lighting", kind: .options(["3d": "Lights", "env": "Environment"])),
        ControlSpec(key: "brightness", label: "Brightness", kind: .range(0.1, 3, 0.1), show: { !isEnv($0) }),
        ControlSpec(key: "envPreset", label: "Environment", kind: .options(["city": "City", "dawn": "Dawn", "lobby": "Lobby"]), show: isEnv),
        ControlSpec(key: "reflection", label: "Reflection", kind: .range(0, 1, 0.1), show: isEnv, advanced: true),
        ControlSpec(key: "bokeh", label: "Bokeh", kind: .options(["off": "Off", "on": "On"])),
        ControlSpec(key: "focus", label: "Focus", kind: .range(-10, 10, 0.1), show: hasBokeh, fallback: 0),
        ControlSpec(key: "blur", label: "Blur", kind: .range(0, 1, 0.05), show: hasBokeh, fallback: 0.5),
    ]),
    ("Camera", [
        ControlSpec(key: "cAzimuthAngle", label: "Azimuth", kind: .range(0, 360, 1)),
        ControlSpec(key: "cPolarAngle", label: "Polar", kind: .range(0, 180, 1)),
        ControlSpec(key: "cDistance", label: "Distance", kind: .range(0, 20, 0.1)),
        ControlSpec(key: "cameraZoom", label: "Zoom", kind: .range(0.1, 30, 0.1)),
        ControlSpec(key: "positionX", label: "Position X", kind: .range(-5, 5, 0.1), advanced: true),
        ControlSpec(key: "positionY", label: "Position Y", kind: .range(-5, 5, 0.1), advanced: true),
        ControlSpec(key: "positionZ", label: "Position Z", kind: .range(-5, 5, 0.1), advanced: true),
        ControlSpec(key: "rotationX", label: "Rotation X", kind: .range(-360, 360, 1), advanced: true),
        ControlSpec(key: "rotationY", label: "Rotation Y", kind: .range(-360, 360, 1), advanced: true),
        ControlSpec(key: "rotationZ", label: "Rotation Z", kind: .range(-360, 360, 1), advanced: true),
    ]),
]

let tvSpring = Animation.spring(response: 0.45, dampingFraction: 0.82)

// MARK: - Metal views in SwiftUI

struct LiveGradient: NSViewRepresentable {
    let props: Props
    /// While editing: trackpad/mouse gestures on the preview move the camera through this (nil = view only).
    var onCamera: ((CameraGesture) -> Void)? = nil
    var onCameraReset: (() -> Void)? = nil
    func makeNSView(context: Context) -> CameraGradientView { CameraGradientView(props: props) }
    func updateNSView(_ v: CameraGradientView, context: Context) {
        if v.props != props { v.props = props }
        v.onCamera = onCamera
        v.onReset = onCameraReset
    }
}

/// Preview that turns trackpad and mouse input into camera gestures: two-finger swipe or drag orbits (with ⇧ or ⌥, or
/// right-drag: pans), pinch zooms, two-finger rotate rolls, double-click resets.
final class CameraGradientView: GradientView {
    var onCamera: ((CameraGesture) -> Void)?
    var onReset: (() -> Void)?
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { onCamera != nil }
    // The gallery window can sit closed-off on another Space, minimized or covered: don't render it then.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NotificationCenter.default.removeObserver(self, name: NSWindow.didChangeOcclusionStateNotification, object: nil)
        guard let w = window else { return }
        NotificationCenter.default.addObserver(self, selector: #selector(occlusionChanged), name: NSWindow.didChangeOcclusionStateNotification, object: w)
        occlusionChanged()
    }
    @objc private func occlusionChanged() { isPaused = !(window?.occlusionState.contains(.visible) ?? false) }
    override func scrollWheel(with e: NSEvent) {
        guard let onCamera, e.hasPreciseScrollingDeltas else { return super.scrollWheel(with: e) } // mouse wheels: no orbit
        move(e, dx: e.scrollingDeltaX, dy: e.scrollingDeltaY)
    }
    override func mouseDragged(with e: NSEvent) { move(e, dx: e.deltaX, dy: e.deltaY) }
    override func rightMouseDragged(with e: NSEvent) { onCamera?(.pan(dx: e.deltaX, dy: e.deltaY, viewHeight: bounds.height)) }
    private func move(_ e: NSEvent, dx: Double, dy: Double) {
        // ⌥ as well as ⇧: macOS may turn ⇧-scrolling into horizontal scrolling.
        let pan = !e.modifierFlags.intersection([.shift, .option]).isEmpty
        onCamera?(pan ? .pan(dx: dx, dy: dy, viewHeight: bounds.height) : .orbit(dx: dx, dy: dy))
    }
    override func magnify(with e: NSEvent) { onCamera?(.zoom(1 + e.magnification)) }
    override func rotate(with e: NSEvent) { onCamera?(.roll(Double(e.rotation))) }
    override func mouseUp(with e: NSEvent) { if e.clickCount == 2 { onReset?() } }
}

/// Real renders of gradients for the cards, made on demand and kept in memory.
@MainActor
enum Thumbs {
    private static var cache: [String: NSImage] = [:]
    static func image(_ props: Props) -> NSImage? {
        if let i = cache[props.key] { return i }
        let pt = CGSize(width: 224, height: 140) // card size
        guard let cg = Renderer.shared.thumbnail(props, pointSize: pt) else { return nil }
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
            LiveGradient(props: editing == nil ? focused.props : draft,
                         onCamera: editing == nil ? nil : { draft = draft.camera($0) },
                         onCameraReset: editing.map { e in { for k in cameraKeys { draft[k] = e.props[k] } } })
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
        .sheet(isPresented: $showLicense) {
            LicenseSheet(license: license)
        }
        .animation(tvSpring, value: editing?.identity)
        .animation(tvSpring, value: store.toast)
        .preferredColorScheme(.dark)
        .onAppear { focused = store.current.map { d in presets.first { $0.props.key == d.props.key } ?? d } ?? presets[0] }
    }

    /// Free version: only presets[0] as wallpaper and no editor; anything else opens the purchase sheet.
    private func locked(_ e: Entry) -> Bool { !license.isUnlocked && e.props != presets[0].props }
    private func open(_ e: Entry) { if license.isUnlocked { draft = e.props; editing = e } else { showLicense = true } }
    private func use(_ e: Entry) { if locked(e) { showLicense = true } else { store.apply(e); store.show("Set as wallpaper") } }
    private func close() {
        if let e = editing { focused = Entry(id: e.id, name: e.name, props: draft, builtin: e.builtin) }
        editing = nil
    }

    private var browse: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                Button { showLicense = true } label: {
                    switch license.state {
                    case .free: Label("Unlock All Gradients", systemImage: "sparkles")
                    case .licensed: Label("Hueflow", systemImage: "checkmark.seal.fill")
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
                    Button { use(focused) } label: { Label(locked(focused) ? "Unlock to Use" : "Set as Wallpaper", systemImage: locked(focused) ? "lock.fill" : "desktopcomputer") }
                        .buttonStyle(PrimaryButton())
                    Button { open(focused) } label: { Label("Edit", systemImage: license.isUnlocked ? "slider.horizontal.3" : "lock.fill") }
                        .buttonStyle(GlassButton())
                }
                .padding(.top, 8)
            }
            .padding(.horizontal, 48)
            .animation(.easeInOut(duration: 0.3), value: focused.name)

            VStack(alignment: .leading, spacing: 18) {
                Row(title: "Featured", entries: presets, store: store, focused: $focused, open: open, use: use, locked: locked)
                if !store.cfg.custom.isEmpty {
                    Row(title: "My Gradients", entries: store.cfg.custom, store: store, focused: $focused, open: open, use: use, locked: locked)
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
    let use: (Entry) -> Void
    let locked: (Entry) -> Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 17, weight: .semibold)).padding(.horizontal, 48)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 22) {
                    let current = store.current?.props
                    ForEach(entries, id: \.identity) { e in
                        Card(entry: e, current: current == e.props, focused: focused.identity == e.identity, locked: locked(e))
                            .onTapGesture { focused = e } // no double-click: SwiftUI would hold every single click until it times out
                            .contextMenu {
                                Button("Set as Wallpaper") { use(e) }
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
    let locked: Bool
    @State private var image: NSImage?
    @State private var tilt: CGPoint? // cursor over the thumbnail, -1…1 per axis; nil when not hovered
    private var lifted: Bool { focused || tilt != nil }

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
                // Apple TV parallax glare: follows the cursor
                .overlay(RadialGradient(colors: [.white.opacity(tilt == nil ? 0 : 0.28), .clear],
                                        center: UnitPoint(x: ((tilt?.x ?? 0) + 1) / 2, y: ((tilt?.y ?? 0) + 1) / 2), startRadius: 0, endRadius: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous)).allowsHitTesting(false))
                if locked {
                    Image(systemName: "lock.circle.fill").font(.system(size: 18)).symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .black.opacity(0.35)).padding(8)
                } else if current {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 18)).symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .black.opacity(0.35)).padding(8)
                }
            }
            // Shadow from a plain shape: shadowing the image itself re-renders it offscreen every animation frame.
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.black)
                .shadow(color: .black.opacity(lifted ? 0.5 : 0.25), radius: lifted ? 22 : 8, y: lifted ? 14 : 4))
            .rotation3DEffect(.degrees(tilt.map { hypot($0.x, $0.y) * 7 } ?? 0), axis: (x: -(tilt?.y ?? 0), y: tilt?.x ?? 0, z: 0), perspective: 0.6)
            Text(entry.name).font(.system(size: 13, weight: .medium)).foregroundStyle(.white.opacity(lifted ? 1 : 0.65)).lineLimit(1)
        }
        .scaleEffect(focused ? 1.1 : tilt != nil ? 1.05 : 1, anchor: .center)
        .zIndex(lifted ? 1 : 0)
        .animation(tvSpring, value: focused)
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: tilt)
        // Hover and clicks use the untransformed frame: tracking the tilted card made its edge slip out from under the
        // cursor, flipping hover off and on every frame.
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            if case .active(let p) = phase { tilt = CGPoint(x: p.x / 112 - 1, y: min(1, p.y / 70 - 1)) } else { tilt = nil }
        }
        .task(id: entry.props) { image = Thumbs.image(entry.props) }
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
    @State private var showAdvanced = false
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
                        let visible = tabs.first { $0.0 == tab }!.1.filter { $0.show(props) }
                        ForEach(visible.filter { !$0.advanced }) { c in ControlRow(spec: c, props: $props) }
                        let advanced = visible.filter(\.advanced)
                        if !advanced.isEmpty {
                            Button { withAnimation(tvSpring) { showAdvanced.toggle() } } label: {
                                HStack(spacing: 6) {
                                    Text("Advanced")
                                    Image(systemName: "chevron.right").rotationEffect(.degrees(showAdvanced ? 90 : 0))
                                    Spacer()
                                }
                                .font(.system(size: 12, weight: .semibold)).foregroundStyle(.white.opacity(0.6))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 4)
                            if showAdvanced { ForEach(advanced) { c in ControlRow(spec: c, props: $props) } }
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
                let picker = Picker(spec.label, selection: Binding(get: { props.str(spec.key, opts.first!.key) }, set: { props[spec.key] = .str($0) })) {
                    ForEach(opts, id: \.key) { Text($0.value).tag($0.key) }
                }
                .labelsHidden()
                // More than 4 segments overflow the editor panel.
                if opts.count > 4 { picker.pickerStyle(.menu) } else { picker.pickerStyle(.segmented) }
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
            case .free:
                Text("The free version includes the \(presets[0].name) wallpaper. Buy once to unlock every gradient, the editor and your own gradients, forever.").foregroundStyle(.secondary)
                Button { NSWorkspace.shared.open(LicenseConfig.checkoutURL) } label: {
                    Text("Buy Hueflow").frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButton())
                Divider()
                Text("Already bought it? Paste the license key from your receipt email:").font(.callout)
                TextField("XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX", text: $key).textFieldStyle(.roundedBorder).font(.body.monospaced())
                if let error { Text(error).font(.callout).foregroundStyle(.red) }
                HStack {
                    Button("Later") { dismiss() }
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

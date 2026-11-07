// App state and system integration: config persistence, a desktop-level gradient window per display,
// the menu bar item, the built-in idle screen saver and installing the System Settings .saver.
import AppKit
import IOKit.ps
import ServiceManagement
import SwiftUI

struct SaverSettings: Codable, Equatable {
    var enabled = false
    var minutes = 5
    var source = "shuffle" // "shuffle" | "wallpaper"
    var clock = true
    static let minuteChoices = [1, 5, 10, 15, 30]
}

/// Missing keys fall back to defaults, so older config files still load.
struct Config: Codable {
    var `default`: Entry?
    var perDisplay: [String: Entry] = [:]
    var disabled: [UInt32] = []
    var recent: [Entry] = []
    var custom: [Entry] = []
    var paused = false
    var pauseOnBattery = true
    var pauseInFullScreen = true
    var antialias = true
    // Performance (Performance submenu); each saves GPU with little or no visible change.
    var lowerFrameRate = true    // wallpapers at 30 fps instead of 60
    var halfResolution = true    // wallpapers' 3D scene at half size, grain at full size
    var retina = false           // wallpapers' grain at the Retina scale: smooth silhouettes, ~3× GPU time
    var pauseWhenCovered = true  // pause a wallpaper while other windows hide it
    var tileMemory = true        // depth/MSAA buffers in GPU tile memory
    var saveEnergy = true        // 15 fps in Low Power Mode or when the Mac runs hot
    var hideDockIcon = false
    var saver = SaverSettings()

    init() {}
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        `default` = try c.decodeIfPresent(Entry.self, forKey: .default)
        perDisplay = try c.decodeIfPresent([String: Entry].self, forKey: .perDisplay) ?? [:]
        disabled = try c.decodeIfPresent([UInt32].self, forKey: .disabled) ?? []
        recent = try c.decodeIfPresent([Entry].self, forKey: .recent) ?? []
        custom = try c.decodeIfPresent([Entry].self, forKey: .custom) ?? []
        paused = try c.decodeIfPresent(Bool.self, forKey: .paused) ?? false
        pauseOnBattery = try c.decodeIfPresent(Bool.self, forKey: .pauseOnBattery) ?? true
        pauseInFullScreen = try c.decodeIfPresent(Bool.self, forKey: .pauseInFullScreen) ?? true
        hideDockIcon = try c.decodeIfPresent(Bool.self, forKey: .hideDockIcon) ?? false
        antialias = try c.decodeIfPresent(Bool.self, forKey: .antialias) ?? true
        lowerFrameRate = try c.decodeIfPresent(Bool.self, forKey: .lowerFrameRate) ?? true
        halfResolution = try c.decodeIfPresent(Bool.self, forKey: .halfResolution) ?? true
        retina = try c.decodeIfPresent(Bool.self, forKey: .retina) ?? false
        pauseWhenCovered = try c.decodeIfPresent(Bool.self, forKey: .pauseWhenCovered) ?? true
        tileMemory = try c.decodeIfPresent(Bool.self, forKey: .tileMemory) ?? true
        saveEnergy = try c.decodeIfPresent(Bool.self, forKey: .saveEnergy) ?? true
        saver = try c.decodeIfPresent(SaverSettings.self, forKey: .saver) ?? SaverSettings()
    }
}

struct Display: Identifiable, Hashable {
    let id: UInt32
    let label: String
}

extension NSScreen {
    var displayID: UInt32 { (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0 }
}

@MainActor
final class Store: ObservableObject {
    @Published private(set) var cfg = Config()
    @Published var toast: String?
    private var desktops: [NSWindow] = []
    private var savers: [NSWindow] = []
    private var saverStartedAt = Date.distantPast
    private var statusItem: NSStatusItem?
    var onShowGallery: () -> Void = {}
    /// Trial running or licensed; wallpapers and the screen saver only run while true.
    var isUnlocked: () -> Bool = { true }

    private static let dir: URL = {
        let d = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Hueflow")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()
    private static let configURL = dir.appendingPathComponent("config.json")
    init() {
        if let data = try? Data(contentsOf: Self.configURL), let c = try? JSONDecoder().decode(Config.self, from: data) { cfg = c }
        Renderer.shared.antialias = cfg.antialias
        Renderer.shared.tileMemory = cfg.tileMemory
    }

    /// Re-applies everything after the license state changes.
    func refresh() { changed() }

    func start() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = Self.menuBarIcon
        item.button?.toolTip = "Hueflow"
        statusItem = item
        applyDockIcon()
        changed()
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.changed() }
        }
        // Resume the moment a covered wallpaper shows again (the 1 s poll would lag).
        NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyPause() }
        }
        DistributedNotificationCenter.default().addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.stopSaver() }
        }
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.poll() } }
    }

    // MARK: config

    var displays: [Display] {
        NSScreen.screens.enumerated().map { i, s in Display(id: s.displayID, label: s.localizedName.isEmpty ? "Display \(i + 1)" : s.localizedName) }
    }
    func entry(for id: UInt32) -> Entry? { cfg.perDisplay[String(id)] ?? cfg.default }
    func isEnabled(_ id: UInt32) -> Bool { !cfg.disabled.contains(id) }

    private func changed(rebuild: Bool = true) {
        if let data = try? JSONEncoder().encode(cfg) { try? data.write(to: Self.configURL, options: .atomic) }
        if rebuild { renderDesktops() }
        applyPause()
        updateMenu()
    }

    /// target: nil = all displays.
    func apply(_ entry: Entry, to target: UInt32? = nil) {
        let e = Entry(name: entry.name, props: entry.props)
        if let t = target {
            cfg.perDisplay[String(t)] = e
            cfg.disabled.removeAll { $0 == t }
        } else {
            cfg.default = e
            cfg.perDisplay = [:]
            cfg.disabled = []
        }
        cfg.recent = Array(([e] + cfg.recent.filter { $0.props.key != e.props.key }).prefix(10))
        changed()
    }

    func setEnabled(_ id: UInt32, _ on: Bool) {
        cfg.disabled.removeAll { $0 == id }
        if !on { cfg.disabled.append(id) }
        changed()
    }

    /// Saves a new custom gradient or updates the one with the same id; returns its id.
    @discardableResult
    func saveCustom(_ entry: Entry) -> String {
        if let id = entry.id, let i = cfg.custom.firstIndex(where: { $0.id == id }) {
            cfg.custom[i].name = entry.name
            cfg.custom[i].props = entry.props
            changed(rebuild: false)
            return id
        }
        let id = UUID().uuidString.lowercased()
        cfg.custom.insert(Entry(id: id, name: entry.name, props: entry.props), at: 0)
        changed(rebuild: false)
        return id
    }

    func deleteCustom(_ id: String) {
        cfg.custom.removeAll { $0.id == id }
        changed(rebuild: false)
    }

    /// Live views pick it up on their next frame (paused wallpapers on resume).
    func setAntialias(_ on: Bool) { cfg.antialias = on; Renderer.shared.antialias = on; changed(rebuild: false) }
    func toggle(_ option: WritableKeyPath<Config, Bool>) {
        cfg[keyPath: option].toggle()
        Renderer.shared.tileMemory = cfg.tileMemory // views rebuild their buffers on the next frame
        changed(rebuild: false)
    }

    /// Login item state lives in macOS (System Settings › General › Login Items), not in our config.
    var opensAtLogin: Bool { SMAppService.mainApp.status == .enabled }

    func setOpensAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            show("Couldn't change Open at Login: \(error.localizedDescription)")
        }
        // macOS can hold the request until the user approves it in Login Items.
        if on && SMAppService.mainApp.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
        updateMenu()
    }

    func setHideDockIcon(_ on: Bool) {
        cfg.hideDockIcon = on
        changed(rebuild: false)
        applyDockIcon()
    }

    /// Without a Dock icon the app lives only in the menu bar; the gallery still opens from there.
    private func applyDockIcon() {
        NSApp.setActivationPolicy(cfg.hideDockIcon ? .accessory : .regular)
        // Switching to .accessory deactivates the app; keep an open gallery in front.
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first { $0.isVisible && $0.canBecomeKey }?.makeKeyAndOrderFront(nil)
        }
    }

    /// Template image (adapts to light/dark menu bars): a rounded "screen" with a flowing wave inside.
    static let menuBarIcon: NSImage = {
        let img = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            let frame = NSRect(x: 1.5, y: 2.5, width: 15, height: 13)
            let screen = NSBezierPath(roundedRect: frame, xRadius: 3.5, yRadius: 3.5)
            screen.lineWidth = 1.5
            NSColor.black.setStroke()
            screen.stroke()
            screen.addClip()
            let wave = NSBezierPath()
            wave.move(to: NSPoint(x: 0, y: 7))
            wave.curve(to: NSPoint(x: 9, y: 9.5), controlPoint1: NSPoint(x: 3, y: 12), controlPoint2: NSPoint(x: 6, y: 12))
            wave.curve(to: NSPoint(x: 18, y: 8), controlPoint1: NSPoint(x: 12, y: 7), controlPoint2: NSPoint(x: 15, y: 4))
            wave.line(to: NSPoint(x: 18, y: 0))
            wave.line(to: NSPoint(x: 0, y: 0))
            wave.close()
            NSColor.black.setFill()
            wave.fill()
            return true
        }
        img.isTemplate = true
        return img
    }()
    func updateSaver(_ f: (inout SaverSettings) -> Void) { f(&cfg.saver); changed(rebuild: false) }

    func show(_ message: String) {
        toast = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) { [weak self] in if self?.toast == message { self?.toast = nil } }
    }

    // MARK: desktop windows

    private func renderDesktops() {
        desktops.forEach { $0.orderOut(nil) }
        desktops = []
        guard isUnlocked() else { return }
        desktops = NSScreen.screens.filter { isEnabled($0.displayID) }.map { screen in
            // Full screen frame so the wallpaper also shows behind a transparent menu bar.
            let w = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            w.setFrame(screen.frame, display: false)
            w.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
            w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            w.ignoresMouseEvents = true
            w.hasShadow = false
            w.isReleasedWhenClosed = false
            w.backgroundColor = .black
            let props = (entry(for: screen.displayID) ?? presets[0]).props
            w.contentView = GradientView(props: props)
            w.orderFrontRegardless()
            matchSystemWallpaper(screen, props)
            return w
        }
    }

    /// macOS styles the menu bar (text color, legibility haze) and the lock screen from the system wallpaper, not from our
    /// window, so set a still of the same gradient as the system wallpaper.
    private func matchSystemWallpaper(_ screen: NSScreen, _ props: Props) {
        let fm = FileManager.default
        let dir = Self.dir.appendingPathComponent("Wallpapers")
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        // FNV-1a of the props: a new file name per gradient, because macOS caches images by URL.
        let hash = props.key.utf8.reduce(UInt64(14695981039346656037)) { ($0 ^ UInt64($1)) &* 1099511628211 }
        let prefix = "display-\(screen.displayID)-"
        let url = dir.appendingPathComponent(prefix + String(hash, radix: 16) + ".jpg")
        guard NSWorkspace.shared.desktopImageURL(for: screen) != url else { return }
        if !fm.fileExists(atPath: url.path) {
            let scale = screen.backingScaleFactor
            guard let img = Renderer.shared.snapshot(props, width: Int(screen.frame.width * scale), height: Int(screen.frame.height * scale), elapsed: 3.5),
                  let jpg = NSBitmapImageRep(cgImage: img).representation(using: .jpeg, properties: [.compressionFactor: 0.9]) else { return }
            try? jpg.write(to: url)
        }
        try? NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [:])
        // Keep only the current still per display.
        for f in (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        where f.lastPathComponent.hasPrefix(prefix) && f != url { try? fm.removeItem(at: f) }
    }

    private var onBattery: Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() else { return false }
        return (type as String) == kIOPMBatteryPowerKey
    }

    /// Wallpapers are hidden behind the screen saver and full-screen windows, so they pause then.
    private func applyPause() {
        let all = cfg.paused || !savers.isEmpty || (cfg.pauseOnBattery && onBattery)
        let fullScreen = cfg.pauseInFullScreen && !all ? fullScreenDisplays : []
        let fps = wallpaperFPS
        for w in desktops {
            guard let v = w.contentView as? GradientView else { continue }
            let hidden = cfg.pauseWhenCovered && !w.occlusionState.contains(.visible)
            let paused = all || hidden || fullScreen.contains(w.screen?.displayID ?? 0)
            if v.isPaused != paused { v.isPaused = paused }
            // Beats need 60 fps to look smooth, so music-reactive wallpapers skip the 30 fps option (not the 15 fps saver).
            let f = fps == 30 && v.props.str("music", "off") == "on" ? 60 : fps
            if v.preferredFramesPerSecond != f { v.preferredFramesPerSecond = f }
            v.sceneScale = cfg.halfResolution ? 0.5 : 1
            v.retina = cfg.retina
        }
    }

    /// Wallpapers move slowly, so 30 fps looks the same as 60; Low Power Mode or a hot Mac drops to 15.
    private var wallpaperFPS: Int {
        let info = ProcessInfo.processInfo
        if cfg.saveEnergy && (info.isLowPowerModeEnabled || info.thermalState == .serious || info.thermalState == .critical) { return 15 }
        return cfg.lowerFrameRate ? 30 : 60
    }

    /// Displays covered edge to edge by a normal window on the current Space (full-screen apps, borderless games/video).
    private var fullScreenDisplays: Set<UInt32> {
        let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let rects = info.compactMap { w -> CGRect? in
            guard w[kCGWindowLayer as String] as? Int == 0, let b = w[kCGWindowBounds as String] as? NSDictionary else { return nil }
            return CGRect(dictionaryRepresentation: b as CFDictionary)
        }
        return Set(NSScreen.screens.filter { s in
            let d = CGDisplayBounds(s.displayID) // same top-left coordinates as window bounds
            // On notched displays full-screen windows start below the camera, at the safe area.
            return rects.contains { $0.minX <= d.minX && $0.maxX >= d.maxX && $0.maxY >= d.maxY && $0.minY <= d.minY + s.safeAreaInsets.top }
        }.map(\.displayID))
    }

    // MARK: built-in screen saver

    private var saverOptions: SaverOptions {
        SaverOptions(shuffle: cfg.saver.source == "shuffle", clock: cfg.saver.clock, props: cfg.default?.props, extra: cfg.custom.map(\.props))
    }

    // shortcut: idle is polled and the saver is our own window, so it only runs while the app is open and doesn't know
    // about video playback in other apps; the System Settings .saver (installSaver) covers that.
    func startSaver() {
        guard savers.isEmpty, isUnlocked() else { return }
        saverStartedAt = Date()
        savers = NSScreen.screens.map { screen in
            let w = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            w.setFrame(screen.frame, display: false)
            w.level = .screenSaver // above menu bar and Dock
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            w.backgroundColor = .black
            w.isReleasedWhenClosed = false
            var o = saverOptions
            if let e = entry(for: screen.displayID) { o.props = e.props }
            w.contentView = SaverContent(options: o)
            w.orderFrontRegardless()
            return w
        }
        NSCursor.hide()
        applyPause()
    }

    func stopSaver() {
        guard !savers.isEmpty else { return }
        savers.forEach { ($0.contentView as? SaverContent)?.stop(); $0.orderOut(nil) }
        savers = []
        NSCursor.unhide()
        applyPause()
    }

    private func poll() {
        let anyInput = CGEventType(rawValue: ~0)!
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
        if !savers.isEmpty {
            // Any input dismisses it; the grace period ignores the click that started it.
            if idle < 1 && Date().timeIntervalSince(saverStartedAt) > 2.5 { stopSaver() }
        } else if cfg.saver.enabled && idle >= Double(cfg.saver.minutes * 60) && !screenLocked {
            startSaver()
        }
        applyPause() // picks up battery and full-screen changes
    }

    private var screenLocked: Bool {
        (CGSessionCopyCurrentDictionary() as? [String: Any])?["CGSSessionScreenIsLocked"] as? Bool ?? false
    }

    // MARK: System Settings .saver

    // shortcut: an installed .saver keeps working after the trial ends; have the saver check the license if that matters.
    /// Copies the bundled Hueflow.saver with the current saver settings and a thumbnail baked in, signs it ad hoc,
    /// installs it to ~/Library/Screen Savers and opens System Settings so it can be picked.
    func installSaver() async throws {
        let fm = FileManager.default
        guard let bundled = Bundle.main.url(forResource: "Hueflow", withExtension: "saver") else { throw CocoaError(.fileNoSuchFile) }
        // File name must match CFBundleName (Hueflow): WallpaperAgent looks modules up by it.
        let staging = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("Hueflow.saver")
        try fm.createDirectory(at: staging.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.copyItem(at: bundled, to: staging)
        let res = staging.appendingPathComponent("Contents/Resources")
        try fm.createDirectory(at: res, withIntermediateDirectories: true)
        try JSONEncoder().encode(saverOptions).write(to: res.appendingPathComponent("saver-config.json"))
        let props = cfg.default?.props ?? presets[0].props
        for (name, w) in [("thumbnail.png", 320), ("thumbnail@2x.png", 640)] {
            if let img = Renderer.shared.snapshot(props, width: w, height: w * 5 / 8),
               let png = NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:]) {
                try png.write(to: res.appendingPathComponent(name))
            }
        }
        try await run("/usr/bin/codesign", ["--force", "--sign", "-", staging.path]) // resources changed the bundle
        let dir = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Screen Savers")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = dir.appendingPathComponent("Hueflow.saver")
        try? fm.removeItem(at: dest)
        try fm.copyItem(at: staging, to: dest)
        // System Settings caches the module list; restart the processes that hold it so the new saver shows up.
        for p in ["System Settings", "WallpaperLegacyExtension", "Wallpaper", "legacyScreenSaver", "legacyScreenSaver-x86_64", "WallpaperAgent"] {
            try? await run("/usr/bin/killall", [p])
        }
        try await Task.sleep(for: .seconds(2.5)) // let launchd bring WallpaperAgent back
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Wallpaper-Settings.extension")!)
    }

    private func run(_ tool: String, _ args: [String]) async throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            p.terminationHandler = { p in
                p.terminationStatus == 0 ? c.resume() : c.resume(throwing: CocoaError(.executableLoad))
            }
            do { try p.run() } catch { c.resume(throwing: error) }
        }
    }

    // MARK: menu bar

    private func updateMenu() {
        let m = NSMenu()
        m.autoenablesItems = false
        func item(_ title: String, checked: Bool? = nil, in menu: NSMenu? = nil, _ action: @escaping () -> Void) {
            let i = MenuItem(title: title, action: action)
            if let checked { i.state = checked ? .on : .off }
            (menu ?? m).addItem(i)
        }
        func toggles(_ list: [(String, WritableKeyPath<Config, Bool>)], in menu: NSMenu) {
            for (title, option) in list { item(title, checked: cfg[keyPath: option], in: menu) { [weak self] in self?.toggle(option) } }
        }
        func submenu(_ title: String, _ fill: (NSMenu) -> Void) {
            let sub = NSMenu()
            sub.autoenablesItems = false
            fill(sub)
            let i = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            i.submenu = sub
            m.addItem(i)
        }

        // Everyday actions at the top level; settings grouped in submenus.
        item("Open Hueflow") { [weak self] in self?.onShowGallery() }
        item("Pause", checked: cfg.paused) { [weak self] in self?.toggle(\.paused) }
        if !cfg.recent.isEmpty {
            m.addItem(.separator())
            m.addItem(.sectionHeader(title: "Recent"))
            let current = cfg.default?.props.key
            for e in cfg.recent.prefix(5) { item(e.name, checked: e.props.key == current) { [weak self] in self?.apply(e) } }
        }
        m.addItem(.separator())
        submenu("Screen Saver") { sub in
            item("Start When Idle", checked: cfg.saver.enabled, in: sub) { [weak self] in self?.updateSaver { $0.enabled.toggle() } }
            item("Start Now", in: sub) { [weak self] in self?.startSaver() }
        }
        submenu("Auto-Pause") { sub in
            toggles([("On Battery", \.pauseOnBattery), ("In Full Screen", \.pauseInFullScreen), ("When Covered", \.pauseWhenCovered)], in: sub)
        }
        submenu("Quality & Performance") { sub in
            item("Antialiasing", checked: cfg.antialias, in: sub) { [weak self] in self?.setAntialias(!(self?.cfg.antialias ?? false)) }
            toggles([("Retina Resolution (Smoother Edges)", \.retina)], in: sub)
            sub.addItem(.separator())
            toggles([("30 fps Wallpaper", \.lowerFrameRate), ("Half-Resolution 3D", \.halfResolution),
                     ("Tile Memory Buffers", \.tileMemory), ("Slow Down in Low Power Mode or When Hot", \.saveEnergy)], in: sub)
        }
        submenu("Displays") { sub in
            for d in displays { item("Show on \(d.label)", checked: isEnabled(d.id), in: sub) { [weak self] in self?.setEnabled(d.id, !(self?.isEnabled(d.id) ?? true)) } }
        }
        m.addItem(.separator())
        item("Open at Login", checked: opensAtLogin) { [weak self] in self?.setOpensAtLogin(!(self?.opensAtLogin ?? false)) }
        item("Hide Dock Icon", checked: cfg.hideDockIcon) { [weak self] in self?.setHideDockIcon(!(self?.cfg.hideDockIcon ?? false)) }
        m.addItem(.separator())
        item("Quit Hueflow") { NSApp.terminate(nil) }
        statusItem?.menu = m
    }
}

/// NSMenuItem that runs a closure.
final class MenuItem: NSMenuItem {
    private let handler: () -> Void
    init(title: String, action: @escaping () -> Void) {
        handler = action
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
    }
    required init(coder: NSCoder) { fatalError() }
    @objc private func fire() { handler() }
}

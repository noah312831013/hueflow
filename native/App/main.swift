// Hueflow: native (Swift + Metal) gradient wallpapers for macOS.
import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let store = Store()
    let license = License()
    private var gallery: NSWindow?

    func applicationDidFinishLaunching(_ n: Notification) {
        GradientView.audioLevel = { AudioTap.shared.level() }
        NSApp.mainMenu = mainMenu()
        store.onShowGallery = { [weak self] in self?.showGallery() }
        store.isUnlocked = { [weak self] in self?.license.isUnlocked ?? false }
        license.onChange = { [weak self] in self?.store.refresh() }
        store.start()
        // Started at login: just put the wallpaper up; the gallery opens from the menu bar.
        let event = NSAppleEventManager.shared().currentAppleEvent
        let atLogin = event?.eventID == kAEOpenApplication && event?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
        if !atLogin { showGallery() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool { showGallery(); return true }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false } // keep running as a wallpaper

    func showGallery() {
        if let g = gallery {
            if g.isMiniaturized { g.deminiaturize(nil) }
            g.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true) // menu bar clicks don't activate the app on their own
            return
        }
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 820),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        w.title = "Hueflow"
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.minSize = NSSize(width: 900, height: 600)
        w.backgroundColor = .black
        w.isReleasedWhenClosed = false
        w.delegate = self
        w.contentView = NSHostingView(rootView: GalleryRoot(store: store, license: license))
        w.center()
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        gallery = w
    }

    func windowWillClose(_ n: Notification) { gallery = nil }

    /// Credits include the MIT notice for ShaderGradient, whose shaders and presets Hueflow ports.
    private func showAbout() {
        let credits = """
        Rendering is a Metal port of ShaderGradient (@shadergradient/react) by ruucm, including its presets.

        MIT License — Copyright (c) ruucm

        Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated \
        documentation files (the "Software"), to deal in the Software without restriction, including without limitation \
        the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and \
        to permit persons to whom the Software is furnished to do so, subject to the following conditions:

        The above copyright notice and this permission notice shall be included in all copies or substantial portions \
        of the Software.

        THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED \
        TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL \
        THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF \
        CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER \
        DEALINGS IN THE SOFTWARE.
        """
        NSApp.orderFrontStandardAboutPanel(options: [
            .credits: NSAttributedString(string: credits, attributes: [.font: NSFont.systemFont(ofSize: 10), .foregroundColor: NSColor.labelColor]),
        ])
        NSApp.activate(ignoringOtherApps: true)
    }

    private func mainMenu() -> NSMenu {
        let main = NSMenu()
        let app = NSMenu()
        app.addItem(MenuItem(title: "About Hueflow") { [weak self] in self?.showAbout() })
        app.addItem(.separator())
        app.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        app.addItem(withTitle: "Quit Hueflow", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        for m in [app, edit] {
            let item = NSMenuItem()
            item.submenu = m
            main.addItem(item)
        }
        return main
    }
}

MainActor.assumeIsolated {
    let delegate = AppDelegate()
    NSApplication.shared.delegate = delegate
    NSApplication.shared.setActivationPolicy(delegate.store.cfg.hideDockIcon ? .accessory : .regular) // before launch, so a hidden icon never flashes
    NSApplication.shared.run()
}

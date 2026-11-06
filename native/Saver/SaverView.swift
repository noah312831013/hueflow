// System Settings screen saver: the Metal renderer inside legacyScreenSaver (where WKWebView only drew black).
import ScreenSaver

@objc(HueflowSaverView)
final class HueflowSaverView: ScreenSaverView {
    private var content: SaverContent?

    override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        // Written by the app when it installs the saver.
        let url = Bundle(for: Self.self).url(forResource: "saver-config", withExtension: "json")
        let options = url.flatMap { try? JSONDecoder().decode(SaverOptions.self, from: Data(contentsOf: $0)) } ?? SaverOptions()
        let c = SaverContent(options: options, scale: isPreview ? 0.25 : 1)
        c.frame = bounds
        c.autoresizingMask = [.width, .height]
        addSubview(c)
        content = c
    }
    required init?(coder: NSCoder) { super.init(coder: coder) }

    override func stopAnimation() { super.stopAnimation(); content?.stop() }
    override var hasConfigureSheet: Bool { false }
}

// Screen saver content shared by the app's built-in saver and the System Settings .saver:
// a gradient that optionally shuffles every 40s (fading through black) and an optional clock.
import AppKit

struct SaverOptions: Codable {
    var shuffle = true
    var clock = true
    var props: Props?
    var extra: [Props] = []
}

final class SaverContent: NSView {
    private let gradient: GradientView
    private var list: [Props]
    private var index = 0
    private var timers: [Timer] = []
    private var fadeTarget: Float = 1
    private var clockDate: NSTextField?
    private var clockTime: NSTextField?
    static let shuffleSeconds: TimeInterval = 40
    static let fadeSeconds: TimeInterval = 1.4
    /// Formats follow the user's locale (12/24-hour clock, date order).
    private static func format(_ template: String) -> DateFormatter {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate(template)
        return f
    }
    private static let timeFormat = format("jjmm")
    private static let dateFormat = format("EEEEMMMMd")

    init(options o: SaverOptions, scale: CGFloat = 1) {
        let first = o.props ?? presets[0].props
        var rest = (presets.map(\.props) + o.extra).filter { $0.key != first.key }
        rest.shuffle()
        // Shuffled gradients keep the starting one's music reactivity, or it would stop at the first shuffle.
        let music = first.filter { ["music", "musicTarget", "musicIntensity"].contains($0.key) }
        list = [first] + rest.map { $0.merging(music) { $1 } }
        gradient = GradientView(props: first)
        gradient.fade = 0
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = .black
        gradient.autoresizingMask = [.width, .height]
        addSubview(gradient)
        if o.clock { addClock(scale: scale) }
        fadeTarget = 1
        timers.append(Timer.scheduledTimer(withTimeInterval: 1 / 60, repeats: true) { [weak self] _ in self?.tick() })
        if o.shuffle {
            timers.append(Timer.scheduledTimer(withTimeInterval: Self.shuffleSeconds, repeats: true) { [weak self] _ in self?.next() })
        }
    }
    required init?(coder: NSCoder) { fatalError() }

    deinit { timers.forEach { $0.invalidate() } }
    func stop() { timers.forEach { $0.invalidate() }; timers = []; gradient.isPaused = true }

    override func layout() {
        super.layout()
        gradient.frame = bounds
        layoutClock()
    }

    private func tick() {
        let step = Float(1 / 60 / Self.fadeSeconds)
        gradient.fade += max(-step, min(step, fadeTarget - gradient.fade))
        if let t = clockTime, let d = clockDate {
            let now = Date()
            t.stringValue = Self.timeFormat.string(from: now)
            d.stringValue = Self.dateFormat.string(from: now)
        }
    }

    private func next() {
        fadeTarget = 0
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.fadeSeconds) { [weak self] in
            guard let self else { return }
            index = (index + 1) % list.count
            gradient.props = list[index]
            fadeTarget = 1
        }
    }

    private func addClock(scale: CGFloat) {
        func label(_ size: CGFloat, _ weight: NSFont.Weight) -> NSTextField {
            let l = NSTextField(labelWithString: "")
            l.font = .systemFont(ofSize: size * scale, weight: weight)
            l.textColor = .white
            l.alignment = .center
            let s = NSShadow(); s.shadowBlurRadius = 18 * scale; s.shadowColor = NSColor.black.withAlphaComponent(0.35)
            l.shadow = s
            addSubview(l)
            return l
        }
        clockDate = label(26, .semibold)
        clockTime = label(120, .bold)
        clockTime?.font = .monospacedDigitSystemFont(ofSize: 120 * scale, weight: .bold)
    }

    private func layoutClock() {
        guard let t = clockTime, let d = clockDate else { return }
        t.sizeToFit(); d.sizeToFit()
        let top = bounds.height * 0.86
        d.frame = NSRect(x: 0, y: top - d.frame.height, width: bounds.width, height: d.frame.height)
        t.frame = NSRect(x: 0, y: d.frame.minY - t.frame.height + 8, width: bounds.width, height: t.frame.height)
    }
}

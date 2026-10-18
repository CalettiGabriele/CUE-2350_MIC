import AppKit
import QuartzCore

/// Status pill at the top of the active screen (TDD §3.9, revised 2026-10-16).
///
/// - Screen with a notch ("Dynamic Island" style, no border): black shape attached to the
///   notch. Left wing: status dot (red "radar" pulse while recording); right wing: elapsed
///   time; below the notch: one line of text.
/// - Screen without a notch: black pill below the menu bar with a thin light border so it
///   stays visible on dark backgrounds: [dot] text [time].
/// Plain fade in/out; the only continuous animation is the radar pulse while recording.
/// The active screen is the one under the mouse pointer; the panel never takes focus.
@MainActor
final class HUD {
    enum Glyph { case none, recording, working, info }

    private let panel: NSPanel
    private let island = IslandView()
    private let dot = RadarDot()
    private let label = NSTextField(labelWithString: "")
    private let timeLabel = NSTextField(labelWithString: "")
    private var hideTimer: Timer?
    private var clock: Timer?
    private var startedAt: Date?
    private var visible = false
    private var generation = 0
    private var glyph: Glyph = .none

    private let rowHeight: CGFloat = 26
    private let wing: CGFloat = 54          // space added on each side of the notch
    private let maxWidth: CGFloat = 440

    init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 240, height: 40),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        // Above the menu bar so it can merge with the notch.
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.contentView = island

        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .white
        label.lineBreakMode = .byTruncatingTail
        label.alignment = .center
        timeLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        timeLabel.textColor = NSColor(white: 1, alpha: 0.85)
        timeLabel.alignment = .center
        for view in [dot, label, timeLabel] as [NSView] { island.addSubview(view) }
    }

    // MARK: - API

    /// Persistent state. `showsMeter` = recording: radar dot and elapsed time.
    func show(_ title: String, detail: String = "", showsMeter: Bool = false, glyph: Glyph = .working) {
        hideTimer?.invalidate()
        clock?.invalidate()
        if showsMeter {
            startedAt = Date()
            clock = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.updateClock() }
            }
        } else {
            startedAt = nil
        }
        updateClock()
        present(title, glyph: glyph)
    }

    /// Short notice that hides itself.
    func toast(_ title: String, detail: String = "", duration: TimeInterval = 1.2) {
        clock?.invalidate()
        startedAt = nil
        updateClock()
        present(title, glyph: .none)
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.hide() }
        }
    }

    /// Not shown: the radar pulse already says "recording".
    func setLevel(_ dbfs: Float) {}

    func hide() {
        hideTimer?.invalidate()
        clock?.invalidate()
        guard visible else { return }
        visible = false
        generation += 1
        let token = generation
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.generation == token, !self.visible else { return }
                self.dot.style = .none
                self.panel.orderOut(nil)
            }
        })
    }

    // MARK: - Layout

    private func updateClock() {
        guard let startedAt else {
            timeLabel.stringValue = ""
            return
        }
        let seconds = Int(Date().timeIntervalSince(startedAt))
        timeLabel.stringValue = String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private func present(_ text: String, glyph: Glyph) {
        self.glyph = glyph
        label.stringValue = text
        switch glyph {
        case .recording: dot.style = .radar
        case .working: dot.style = .working
        case .none, .info: dot.style = .none
        }
        dot.isHidden = dot.style == .none
        guard let screen = activeScreen() else { return }
        let textWidth = min(label.intrinsicContentSize.width + 4, maxWidth - 60)
        let hasTime = startedAt != nil
        let timeWidth: CGFloat = 40

        let frame: NSRect
        if let notch = notch(of: screen) {
            // Dynamic Island: wings beside the notch, text below. No border.
            let width = min(max(notch.width + 2 * wing, textWidth + 40), maxWidth)
            let height = notch.height + rowHeight
            frame = NSRect(x: screen.frame.midX - width / 2, y: screen.frame.maxY - height, width: width, height: height)
            island.style = .notch
            let bandMid = height - notch.height / 2
            let wingWidth = (width - notch.width) / 2
            dot.frame = NSRect(x: wingWidth / 2 - 11, y: bandMid - 11, width: 22, height: 22)
            timeLabel.frame = NSRect(x: width - wingWidth / 2 - timeWidth / 2, y: bandMid - 8, width: timeWidth, height: 16)
            label.frame = NSRect(x: (width - textWidth) / 2, y: (rowHeight - 16) / 2, width: textWidth, height: 16)
        } else {
            // Pill below the menu bar: [dot] text [time], with a light border.
            let dotSpace: CGFloat = dot.isHidden ? 0 : 22
            let timeSpace: CGFloat = hasTime ? timeWidth + 4 : 0
            let width = textWidth + dotSpace + timeSpace + 28
            let top = screen.visibleFrame.maxY - 6
            frame = NSRect(x: screen.frame.midX - width / 2, y: top - rowHeight, width: width, height: rowHeight)
            island.style = .pill
            var x: CGFloat = 14
            dot.frame = NSRect(x: x - 4, y: (rowHeight - 22) / 2, width: 22, height: 22)
            x += dotSpace
            label.frame = NSRect(x: x, y: (rowHeight - 16) / 2, width: textWidth, height: 16)
            x += textWidth + 4
            timeLabel.frame = NSRect(x: x, y: (rowHeight - 16) / 2, width: timeWidth, height: 16)
        }
        timeLabel.isHidden = !hasTime

        panel.setFrame(frame, display: true)
        island.needsDisplay = true
        if !visible {
            visible = true
            generation += 1
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.15
                panel.animator().alphaValue = 1
            }
        } else {
            panel.alphaValue = 1
            panel.orderFrontRegardless()
        }
    }

    /// The screen under the mouse pointer ("active screen"), falling back to the main one.
    private func activeScreen() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
    }

    /// Notch size, or nil when the screen has none (via the auxiliary areas beside the notch).
    private func notch(of screen: NSScreen) -> NSSize? {
        guard screen.safeAreaInsets.top > 0,
              let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea else { return nil }
        let width = screen.frame.width - left.width - right.width
        return width > 0 ? NSSize(width: width, height: screen.safeAreaInsets.top) : nil
    }
}

/// Status dot: red with an expanding "radar" ring while recording, soft white pulse while
/// working.
private final class RadarDot: NSView {
    enum Style { case none, radar, working }

    var style: Style = .none {
        didSet { if style != oldValue { restyle() } }
    }

    private let core = CALayer()
    private let ring = CAShapeLayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.addSublayer(ring)
        layer?.addSublayer(core)
        ring.fillColor = nil
        ring.lineWidth = 1.5
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func layout() {
        super.layout()
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let coreSize: CGFloat = 8
        core.frame = CGRect(x: center.x - coreSize / 2, y: center.y - coreSize / 2, width: coreSize, height: coreSize)
        core.cornerRadius = coreSize / 2
        ring.frame = bounds
        ring.path = CGPath(ellipseIn: CGRect(x: center.x - coreSize / 2, y: center.y - coreSize / 2,
                                             width: coreSize, height: coreSize), transform: nil)
        ring.bounds = bounds
        ring.position = center
        restyle()
    }

    private func restyle() {
        core.removeAllAnimations()
        ring.removeAllAnimations()
        switch style {
        case .none:
            ring.opacity = 0
        case .radar:
            core.backgroundColor = NSColor.systemRed.cgColor
            ring.strokeColor = NSColor.systemRed.cgColor
            ring.opacity = 0
            let scale = CABasicAnimation(keyPath: "transform.scale")
            scale.fromValue = 1
            scale.toValue = 2.6
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0.9
            fade.toValue = 0
            let group = CAAnimationGroup()
            group.animations = [scale, fade]
            group.duration = 1.2
            group.repeatCount = .infinity
            group.timingFunction = CAMediaTimingFunction(name: .easeOut)
            ring.add(group, forKey: "radar")
        case .working:
            core.backgroundColor = NSColor(white: 1, alpha: 0.85).cgColor
            ring.opacity = 0
            let pulse = CABasicAnimation(keyPath: "opacity")
            pulse.fromValue = 1
            pulse.toValue = 0.3
            pulse.duration = 0.6
            pulse.autoreverses = true
            pulse.repeatCount = .infinity
            core.add(pulse, forKey: "pulse")
        }
    }
}

/// Black shape. Notch style: no border, flat top merging with the notch. Pill style: thin
/// light border so it stays visible on dark backgrounds.
private final class IslandView: NSView {
    enum Style { case notch, pill }
    var style: Style = .pill

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.setFill()
        switch style {
        case .notch:
            let r = min(14, bounds.height / 2)
            let path = NSBezierPath()
            path.move(to: NSPoint(x: bounds.minX, y: bounds.maxY))
            path.line(to: NSPoint(x: bounds.minX, y: bounds.minY + r))
            path.appendArc(withCenter: NSPoint(x: bounds.minX + r, y: bounds.minY + r), radius: r, startAngle: 180, endAngle: 270)
            path.line(to: NSPoint(x: bounds.maxX - r, y: bounds.minY))
            path.appendArc(withCenter: NSPoint(x: bounds.maxX - r, y: bounds.minY + r), radius: r, startAngle: 270, endAngle: 360)
            path.line(to: NSPoint(x: bounds.maxX, y: bounds.maxY))
            path.close()
            path.fill()
        case .pill:
            let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
            let path = NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2)
            path.fill()
            NSColor(white: 1, alpha: 0.28).setStroke()
            path.lineWidth = 1
            path.stroke()
        }
    }
}

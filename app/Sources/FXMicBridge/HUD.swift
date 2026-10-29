import AppKit
import QuartzCore

/// Status island at the top of the active screen (TDD §3.9, "Chapter 8" identity).
///
/// - Screen with a notch ("Dynamic Island" style, no border): black shape attached to the
///   notch. Left wing: a mirror of the mic's 8 LEDs as two vertical columns (red, white),
///   driven by the same masks `LedAnimator` sends to the device; right wing: elapsed time;
///   below the notch: one line of text, centred.
/// - Screen without a notch: a black pill (fully rounded ends) below the menu bar with a 1px
///   light rule:
///   [LEDs] text [time].
/// Every text uses the same mono chrome (uppercase IBM Plex Mono), except the selection card.
/// Motion: the shape is driven by a damped spring (slight overshoot), growing out of the notch,
/// following every size change and retracting into it; the contents fade in once the shape has
/// opened and fade out before it closes. The LED mirror steps like the hardware (no easing);
/// a short orange rule flashes when something is done. With Reduce Motion it only fades.
/// The active screen is the one under the mouse pointer; the panel never takes focus.
@MainActor
final class HUD {
    enum Glyph { case none, recording, working, info, done }

    private let panel: NSPanel
    private let island = IslandView()
    private let content = NSView()
    private let leds = LEDMirror()
    private let label = NSTextField(labelWithString: "")
    private let timeLabel = NSTextField(labelWithString: "")
    private let flash = CALayer()
    private let spring = IslandSpring()
    private var hideTimer: Timer?
    private var clock: Timer?
    private var startedAt: Date?
    private var visible = false
    private var idleTitle: String?
    private var showingIdle = true
    /// Invalidates a fade-out that a newer notice has overtaken.
    private var closeToken = 0
    private var glyph: Glyph = .none
    /// Notch of the screen the island is on (nil = floating pill).
    private var notchSize: NSSize?
    private var screenFrame: NSRect = .zero
    private let rowHeight: CGFloat = 28
    private let wing: CGFloat = 56          // space added on each side of the notch
    private let maxWidth: CGFloat = 460

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

        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        timeLabel.maximumNumberOfLines = 1
        island.wantsLayer = true
        content.wantsLayer = true
        island.addSubview(content)
        for view in [leds, label, timeLabel] as [NSView] { content.addSubview(view) }
        flash.backgroundColor = Theme.accentNS.cgColor
        flash.opacity = 0
        content.layer?.addSublayer(flash)

        spring.onStep = { [weak self] frame, openness in self?.apply(frame: frame, openness: openness) }
        spring.onRest = { [weak self] in self?.springSettled() }
    }

    // MARK: - API

    /// With no physical mic, keep its LEDs and selection visible between actions.
    /// Updating this context must not replace a recording, confirmation or other active notice.
    func setIdle(_ title: String?) {
        guard title != idleTitle else { return }
        idleTitle = title
        if showingIdle {
            hide()
        } else if visible {
            present(label.attributedStringValue, glyph: glyph)
        }
    }

    /// Persistent state. `showsMeter` = recording: elapsed time in the right wing.
    func show(_ title: String, detail: String = "", showsMeter: Bool = false, glyph: Glyph = .working) {
        showingIdle = false
        hideTimer?.invalidate()
        clock?.invalidate()
        if showsMeter {
            if startedAt == nil { startedAt = Date() }
            clock = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.updateClock() }
            }
        } else {
            startedAt = nil
        }
        updateClock()
        present(Self.chrome(title), glyph: glyph)
    }

    /// Short notice that hides itself. `.done` flashes the orange rule.
    func toast(_ title: String, detail: String = "", duration: TimeInterval = 0.9, glyph: Glyph = .none) {
        showingIdle = false
        clock?.invalidate()
        startedAt = nil
        updateClock()
        present(Self.chrome(title), glyph: glyph)
        if glyph == .done { flashRule() }
        hideAfter(duration)
    }

    /// Selection card: orange mono kicker + lowercase Barlow title, e.g. "MODE 2/4  enhanced".
    func card(kicker: String, title: String, duration: TimeInterval = 1.0) {
        showingIdle = false
        clock?.invalidate()
        startedAt = nil
        updateClock()
        let text = NSMutableAttributedString(string: kicker.uppercased() + "  ", attributes: [
            .font: Theme.monoNS(11, semibold: true), .kern: Theme.monoTracking(11), .foregroundColor: Theme.accentNS,
            .paragraphStyle: Self.centred,
        ])
        text.append(NSAttributedString(string: title.lowercased(), attributes: [
            .font: Theme.displayNS(15, .extrabold), .kern: -0.2, .foregroundColor: NSColor.white,
            .paragraphStyle: Self.centred,
        ]))
        present(text, glyph: .info)
        hideAfter(duration)
    }

    /// Mirror of the logical LED mask (bits 0–3 red top→bottom, 4–7 white top→bottom).
    func setLEDs(_ mask: UInt8) { leds.mask = mask }

    /// Not shown: the LED mirror already says "recording".
    func setLevel(_ dbfs: Float) {}

    func hide() {
        hideTimer?.invalidate()
        clock?.invalidate()
        startedAt = nil
        updateClock()
        showingIdle = true
        if let idleTitle {
            present(Self.chrome(idleTitle), glyph: .info)
            return
        }
        guard visible else { return }
        visible = false
        if Theme.reduceMotion || notchSize == nil {
            // Pill (screens without a notch) and Reduce Motion: fade out. The pill also
            // draws in slightly while it fades; it never shrinks to a small empty shape.
            closeToken += 1
            let token = closeToken
            if notchSize == nil, !Theme.reduceMotion {
                spring.animate(to: Self.scaled(panel.frame, 0.94, lift: 4), .resizing)
            }
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.2
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                panel.animator().alphaValue = 0
            }, completionHandler: { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, self.closeToken == token, !self.visible else { return }
                    self.spring.stop()
                    self.panel.orderOut(nil)
                }
            })
            return
        }
        spring.animate(to: collapsedFrame(), .closing)
    }

    // MARK: - Text styles

    private static let centred: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.lineBreakMode = .byTruncatingTail
        return style
    }()

    /// Every status and notice ("REC · ENHANCED", "WRITTEN (1.2 S)"): mono uppercase chrome.
    private static func chrome(_ text: String) -> NSAttributedString {
        NSAttributedString(string: text.uppercased(), attributes: [
            .font: Theme.monoNS(11, semibold: true), .kern: Theme.monoTracking(11),
            .foregroundColor: NSColor.white, .paragraphStyle: centred,
        ])
    }

    // MARK: - Layout

    private func hideAfter(_ duration: TimeInterval) {
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.hide() }
        }
    }

    private func updateClock() {
        guard let startedAt else {
            timeLabel.stringValue = ""
            return
        }
        let seconds = Int(Date().timeIntervalSince(startedAt))
        timeLabel.attributedStringValue = NSAttributedString(
            string: String(format: "%d:%02d", seconds / 60, seconds % 60),
            attributes: [.font: Theme.monoNS(11, semibold: true), .kern: 0.5,
                         .foregroundColor: NSColor(white: 1, alpha: 0.85), .paragraphStyle: Self.centred])
        layoutContent(size: island.bounds.size)
    }

    private func present(_ text: NSAttributedString, glyph: Glyph) {
        self.glyph = glyph
        label.attributedStringValue = text
        leds.isHidden = idleTitle == nil && (glyph == .none || glyph == .done)
        guard let screen = activeScreen() else { return }
        screenFrame = screen.frame
        notchSize = notch(of: screen)
        island.style = notchSize == nil ? .pill : .notch

        let target = targetFrame()
        if Theme.reduceMotion {
            // Reduce Motion: a short fade, shape still.
            spring.stop()
            closeToken += 1
            let opening = !visible || !panel.isVisible
            apply(frame: target, openness: 1)
            if opening {
                panel.alphaValue = 0
                panel.orderFrontRegardless()
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.15
                    panel.animator().alphaValue = 1
                }
            } else {
                NSAnimationContext.runAnimationGroup({ $0.duration = 0; panel.animator().alphaValue = 1 })
                panel.alphaValue = 1
                panel.orderFrontRegardless()
            }
            visible = true
            return
        }
        if notchSize == nil {
            // Pill: it grows in from slightly smaller and a little higher while fading in, and
            // glides to every new size. Critically damped spring, no overshoot, and never a
            // tiny empty shape: the fade carries the opening and the closing.
            spring.configure(smooth: true)
            closeToken += 1
            let opening = !visible || !panel.isVisible
            if opening {
                let start = Self.scaled(target, 0.9, lift: 6)
                spring.jump(to: start)
                apply(frame: start, openness: 1)
                panel.alphaValue = 0
                panel.orderFrontRegardless()
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.22
                    context.timingFunction = Theme.paperTiming
                    panel.animator().alphaValue = 1
                }
            } else {
                // A notice replaces the previous one (possibly mid fade-out): bring it back.
                NSAnimationContext.runAnimationGroup({ $0.duration = 0; panel.animator().alphaValue = 1 })
                panel.alphaValue = 1
                panel.orderFrontRegardless()
            }
            visible = true
            spring.animate(to: target, opening ? .opening : .resizing)
            return
        }
        spring.configure(smooth: false)
        let opening = !visible
        if opening, !panel.isVisible {
            let start = collapsedFrame()
            spring.jump(to: start)
            apply(frame: start, openness: 0)
            panel.alphaValue = 1
            panel.orderFrontRegardless()
        }
        visible = true
        spring.animate(to: target, opening ? .opening : .resizing)
    }

    private var textSize: NSSize {
        let size = label.fittingSize
        return NSSize(width: min(ceil(size.width), maxWidth - 80), height: ceil(size.height))
    }

    /// Final frame for the current text and glyph.
    private func targetFrame() -> NSRect {
        let text = textSize
        if let notch = notchSize {
            let width = min(max(notch.width + 2 * wing, text.width + 48), maxWidth)
            let height = notch.height + rowHeight
            return NSRect(x: screenFrame.midX - width / 2, y: screenFrame.maxY - height, width: width, height: height)
        }
        // The pill's round ends eat into the sides: keep a wider margin than a rectangle needs.
        let ledSpace: CGFloat = leds.isHidden ? 0 : leds.size(forHeight: rowHeight - 6).width + 14
        let timeSpace: CGFloat = startedAt != nil ? 46 : 0
        let width = text.width + 2 * max(ledSpace, timeSpace) + 56
        let top = (NSScreen.screens.first { $0.frame == screenFrame }?.visibleFrame.maxY ?? screenFrame.maxY) - 6
        return NSRect(x: screenFrame.midX - width / 2, y: top - rowHeight, width: width, height: rowHeight)
    }

    /// `rect` scaled around its centre, optionally moved up by `lift` (the pill's entry/exit).
    private static func scaled(_ rect: NSRect, _ factor: CGFloat, lift: CGFloat) -> NSRect {
        let width = rect.width * factor, height = rect.height * factor
        return NSRect(x: rect.midX - width / 2, y: rect.midY - height / 2 + lift, width: width, height: height)
    }

    /// Where the island grows from / retracts into the notch (notch screens only).
    private func collapsedFrame() -> NSRect {
        if let notch = notchSize {
            return NSRect(x: screenFrame.midX - notch.width / 2, y: screenFrame.maxY - notch.height,
                          width: notch.width, height: notch.height)
        }
        let full = targetFrame()
        return NSRect(x: full.midX - 20, y: full.minY + full.height / 2 - 4, width: 40, height: 8)
    }

    /// One spring step: panel frame, island shape and contents (fading with the openness).
    private func apply(frame: NSRect, openness: CGFloat) {
        panel.setFrame(frame, display: false)
        island.needsDisplay = true
        content.frame = island.bounds
        // Contents appear once the shape is mostly open and leave before it closes.
        // (The pill fades as a whole instead, see present/hide.)
        content.alphaValue = notchSize == nil ? 1 : max(0, min(1, (openness - 0.55) / 0.35))
        layoutContent(size: frame.size)
    }

    private func layoutContent(size: NSSize) {
        let text = textSize
        timeLabel.isHidden = startedAt == nil
        let timeSize = NSSize(width: 44, height: ceil(timeLabel.fittingSize.height))
        if let notch = notchSize {
            // Wings beside the notch, text row below it.
            let bandMid = size.height - notch.height / 2
            let wingWidth = max(0, (size.width - notch.width) / 2)
            let ledSize = leds.size(forHeight: notch.height - 6)
            leds.frame = NSRect(x: wingWidth / 2 - ledSize.width / 2, y: bandMid - ledSize.height / 2,
                                width: ledSize.width, height: ledSize.height)
            timeLabel.frame = NSRect(x: size.width - wingWidth / 2 - timeSize.width / 2, y: bandMid - timeSize.height / 2,
                                     width: timeSize.width, height: timeSize.height)
            let row = max(0, size.height - notch.height)
            label.frame = NSRect(x: (size.width - text.width) / 2, y: (row - text.height) / 2,
                                 width: text.width, height: text.height)
        } else {
            // Pill: LEDs left, time right, text centred between them.
            let ledSize = leds.size(forHeight: size.height - 6)
            leds.frame = NSRect(x: 18, y: (size.height - ledSize.height) / 2, width: ledSize.width, height: ledSize.height)
            timeLabel.frame = NSRect(x: size.width - 18 - timeSize.width, y: (size.height - timeSize.height) / 2,
                                     width: timeSize.width, height: timeSize.height)
            label.frame = NSRect(x: (size.width - text.width) / 2, y: (size.height - text.height) / 2,
                                 width: text.width, height: text.height)
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        flash.frame = CGRect(x: label.frame.minX, y: max(2, label.frame.minY - 3), width: label.frame.width, height: 2)
        CATransaction.commit()
    }

    private func springSettled() {
        if !visible { panel.orderOut(nil) }
    }

    private func flashRule() {
        guard !Theme.reduceMotion else { return }
        let pulse = CAKeyframeAnimation(keyPath: "opacity")
        pulse.values = [0, 1, 1, 0]
        pulse.keyTimes = [0, 0.2, 0.6, 1]
        pulse.duration = 0.5
        pulse.beginTime = CACurrentMediaTime() + 0.12    // as the island settles
        pulse.fillMode = .backwards
        flash.add(pulse, forKey: "flash")
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

/// Damped spring on the island frame (centre x, top edge, width, height), stepped at 120 Hz.
/// Underdamped: the island opens in ~0.5 s, overshoots by a few points and settles in ~1 s.
/// `openness`
/// goes 0 (collapsed) → 1 (target) and drives the contents' fade.
@MainActor
private final class IslandSpring {
    var onStep: ((NSRect, CGFloat) -> Void)?
    var onRest: (() -> Void)?

    /// Notch: underdamped, a few points of overshoot (ζ ≈ 0.62). Smooth (pill): critically
    /// damped, settles in ~0.35 s with no overshoot.
    private var stiffness: CGFloat = 85
    private var damping: CGFloat = 11.5

    func configure(smooth: Bool) {
        stiffness = smooth ? 240 : 85
        damping = smooth ? 31 : 11.5
    }
    private var value = [CGFloat](repeating: 0, count: 4)     // midX, maxY, width, height
    private var velocity = [CGFloat](repeating: 0, count: 4)
    private var target = [CGFloat](repeating: 0, count: 4)
    private var start = [CGFloat](repeating: 0, count: 4)
    enum Transition { case opening, resizing, closing }
    private var transition = Transition.resizing
    private var timer: Timer?
    private var last: CFTimeInterval = 0

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func jump(to frame: NSRect) {
        value = Self.components(frame)
        velocity = [0, 0, 0, 0]
        target = value
    }

    func animate(to frame: NSRect, _ transition: Transition) {
        self.transition = transition
        start = value
        target = Self.components(frame)
        guard timer == nil else { return }
        last = CACurrentMediaTime()
        timer = Timer(timeInterval: 1.0 / 120, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.step() }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    private func step() {
        let now = CACurrentMediaTime()
        var dt = min(now - last, 1.0 / 30)
        last = now
        // Fixed sub-steps keep the integration stable when a frame is late.
        while dt > 0 {
            let h = min(dt, 1.0 / 240)
            for i in 0..<4 {
                let force = -stiffness * (value[i] - target[i]) - damping * velocity[i]
                velocity[i] += force * h
                value[i] += velocity[i] * h
            }
            dt -= h
        }
        let atRest = (0..<4).allSatisfy { abs(value[$0] - target[$0]) < 0.25 && abs(velocity[$0]) < 2 }
        if atRest { value = target }
        onStep?(Self.frame(value), openness)
        if atRest {
            timer?.invalidate()
            timer = nil
            onRest?()
        }
    }

    /// 0 at the collapsed size, 1 at the open size, from the height (or width) travelled.
    /// A resize between two open states keeps the contents fully visible.
    private var openness: CGFloat {
        guard transition != .resizing else { return 1 }
        let i = abs(target[3] - start[3]) > abs(target[2] - start[2]) ? 3 : 2
        let span = target[i] - start[i]
        guard abs(span) > 0.5 else { return transition == .closing ? 0 : 1 }
        let progress = max(0, min(1, (value[i] - start[i]) / span))
        return transition == .closing ? 1 - progress * 1.6 : progress
    }

    private static func components(_ r: NSRect) -> [CGFloat] { [r.midX, r.maxY, r.width, r.height] }

    private static func frame(_ c: [CGFloat]) -> NSRect {
        let width = max(1, c[2]), height = max(1, c[3])
        return NSRect(x: (c[0] - width / 2).rounded(), y: (c[1] - height).rounded(), width: width.rounded(), height: height.rounded())
    }
}

/// The mic's LED column as two vertical columns: 4 red (left) and 4 white (right), top LED
/// first, like the hardware. Steps with each mask; lit dots get a small glow.
private final class LEDMirror: NSView {
    var mask: UInt8 = 0 {
        didSet { if mask != oldValue { needsDisplay = true } }
    }

    private let inset: CGFloat = 2

    /// Size for the available height: dots shrink to fit 4 rows.
    func size(forHeight height: CGFloat) -> NSSize {
        let dot = metrics(height).dot, gap = metrics(height).gap
        return NSSize(width: 2 * dot + gap * 1.6 + 2 * inset, height: 4 * dot + 3 * gap + 2 * inset)
    }

    private func metrics(_ height: CGFloat) -> (dot: CGFloat, gap: CGFloat) {
        let dot = max(3, min(6, (height - 2 * inset) / 4.6))
        return (dot, dot * 0.4)
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let (dot, gap) = metrics(bounds.height)
        for column in 0..<2 {
            for row in 0..<4 {
                let bit = column * 4 + row
                let on = mask & (1 << bit) != 0
                let red = column == 0
                let rect = NSRect(x: inset + CGFloat(column) * (dot + gap * 1.6), y: inset + CGFloat(row) * (dot + gap),
                                  width: dot, height: dot)
                let color: NSColor = on ? (red ? Theme.ledRedNS : .white) : (red ? Theme.ledRedOffNS : Theme.ledWhiteOffNS.withAlphaComponent(0.55))
                NSGraphicsContext.saveGraphicsState()
                if on {
                    let glow = NSShadow()
                    glow.shadowColor = (red ? Theme.ledRedNS : .white).withAlphaComponent(0.9)
                    glow.shadowBlurRadius = 3
                    glow.set()
                }
                color.setFill()
                NSBezierPath(ovalIn: rect).fill()
                NSGraphicsContext.restoreGraphicsState()
            }
        }
    }
}

/// Black shape. Notch style: no border, flat top merging with the notch. Pill style: fully
/// rounded ends with a 1px light rule so it stays visible on dark backgrounds.
private final class IslandView: NSView {
    enum Style { case notch, pill }
    var style: Style = .pill

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.setFill()
        switch style {
        case .notch:
            let r = min(14, bounds.height / 2, bounds.width / 2)
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
            let r = rect.height / 2
            let path = NSBezierPath(roundedRect: rect, xRadius: r, yRadius: r)
            path.fill()
            NSColor(white: 1, alpha: 0.28).setStroke()
            path.lineWidth = 1
            path.stroke()
        }
    }
}

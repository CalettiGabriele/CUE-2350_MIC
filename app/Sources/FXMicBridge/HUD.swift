import AppKit
import QuartzCore

/// Status island at the top of the active screen (TDD §3.9, "Chapter 8" identity).
///
/// - Screen with a notch ("Dynamic Island" style, no border): black shape attached to the
///   notch. Left wing: two rows of pips (red = channel, white = slot) that mirror the mic's 8
///   LEDs, driven by the same masks `LedAnimator` sends to the device (so the recording sweep
///   is the mic's); right wing: elapsed time, "2/3", a slot-kind glyph or a result glyph; below
///   the notch: the app icon, a title and, when there is one, a grey detail line, centred.
///   While recording, the title row folds away after a moment and the island stays as the two
///   wings, a little thicker than the notch so the spring never takes it below it.
/// - Screen without a notch: a black pill (fully rounded ends) below the menu bar with a 1px
///   light rule: [pips] icon title [right].
/// Titles are Barlow sentence case; numbers (time, "2/3") are mono. A title that does not fit
/// fades out at the end instead of ending in an ellipsis.
/// Motion: the shape is driven by a damped spring (slight overshoot), growing out of the notch,
/// following every size change and retracting into it; the contents fade in once the shape has
/// opened and fade out before it closes. The pips step like the hardware (no easing). With
/// Reduce Motion it only fades.
/// The active screen is the one under the mouse pointer; the panel never takes focus.
@MainActor
final class HUD {
    /// Right wing: elapsed time, a short text ("2/3"), an SF Symbol with an optional text (a slot
    /// kind, a result) or the check that draws itself in a ring, with an optional latency.
    enum Trailing: Equatable {
        case none, time, text(String)
        case glyph(String, text: String? = nil, tone: Tone = .normal)
        case success(text: String? = nil)
    }

    enum Tone { case normal, muted, bad }

    private struct Notice {
        var title: String
        var detail: String?
        var icon: NSImage?
        var trailing: Trailing
        /// Recording: the title row folds away after a while, leaving the two wings.
        var folds: Bool
    }

    private let panel: NSPanel
    private let island = IslandView()
    private let content = NSView()
    private let pips = PipsView()
    private let rowView = NSView()
    private let rowIcon = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")
    private let timeLabel = NSTextField(labelWithString: "")
    private let symbolView = NSImageView()
    private let checkView = CheckView()
    private let recDot = RecDotView()
    private let fadeMask = CAGradientLayer()
    private let spring = IslandSpring()
    private var hideTimer: Timer?
    private var foldTimer: Timer?
    private var clock: Timer?
    private var startedAt: Date?
    private var visible = false
    private var notice = Notice(title: "", detail: nil, icon: nil, trailing: .none, folds: false)
    private var folded = false
    /// Invalidates a fade-out that a newer notice has overtaken.
    private var closeToken = 0
    /// Notch of the screen the island is on (nil = floating pill).
    private var notchSize: NSSize?
    private var screenFrame: NSRect = .zero
    private let baseRow: CGFloat = 28       // title row under the notch
    private let detailRow: CGFloat = 44     // title row with a detail line
    /// Without the row the island is this much taller than the notch: the spring overshoots
    /// by a couple of points and must never take it below the notch.
    private let compactExtra: CGFloat = 6
    private let wing: CGFloat = 72          // space added on each side of the notch
    private let maxWidth: CGFloat = 460
    private let maxTitleWidth: CGFloat = 300
    private let iconSide: CGFloat = 16
    private let foldDelay: TimeInterval = 1.2

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

        label.lineBreakMode = .byClipping
        label.maximumNumberOfLines = 1
        label.wantsLayer = true
        detailLabel.lineBreakMode = .byTruncatingTail
        detailLabel.maximumNumberOfLines = 1
        timeLabel.maximumNumberOfLines = 1
        rowIcon.imageScaling = .scaleProportionallyUpOrDown
        symbolView.imageScaling = .scaleProportionallyUpOrDown
        fadeMask.startPoint = CGPoint(x: 0, y: 0.5)
        fadeMask.endPoint = CGPoint(x: 1, y: 0.5)
        fadeMask.colors = [NSColor.black.cgColor, NSColor.black.cgColor, NSColor.clear.cgColor]
        fadeMask.locations = [0, 0.78, 1]
        island.wantsLayer = true
        content.wantsLayer = true
        rowView.wantsLayer = true
        island.addSubview(content)
        for view in [rowIcon, label, detailLabel] as [NSView] { rowView.addSubview(view) }
        for view in [pips, rowView, timeLabel, symbolView, checkView, recDot] as [NSView] { content.addSubview(view) }

        spring.onStep = { [weak self] frame, openness in self?.apply(frame: frame, openness: openness) }
        spring.onRest = { [weak self] in self?.springSettled() }
    }

    // MARK: - API

    /// Mirror of the logical LED mask (bits 0–3 red left→right, 4–7 white left→right).
    func setLEDs(_ mask: UInt8) { pips.mask = mask }

    /// Bound channels (0…4): the red pips that are not lit show as bound or free.
    func setChannels(_ count: Int) { pips.channels = count }

    /// Not shown: the pips already say "recording".
    func setLevel(_ dbfs: Float) {}

    /// Persistent state. `showsMeter` = recording: elapsed time in the right wing and the title
    /// row folds away after a moment.
    func show(_ title: String, detail: String? = nil, icon: NSImage? = nil, showsMeter: Bool = false) {
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
        present(Notice(title: title, detail: detail, icon: icon, trailing: showsMeter ? .time : .none, folds: showsMeter))
    }

    /// Short notice that hides itself: the pips, an optional app icon, a title, a grey detail line
    /// and a result in the right wing.
    func toast(_ title: String, detail: String? = nil, icon: NSImage? = nil, trailing: Trailing = .none,
               duration: TimeInterval = 0.9) {
        clock?.invalidate()
        startedAt = nil
        present(Notice(title: title, detail: detail, icon: icon, trailing: trailing, folds: false))
        hideAfter(duration)
    }

    /// Selection card: the pips, the app icon and a name; `trailing` is the right wing.
    func card(title: String, icon: NSImage? = nil, trailing: Trailing = .none, duration: TimeInterval = 1.0) {
        toast(title, icon: icon, trailing: trailing, duration: duration)
    }

    func hide() {
        hideTimer?.invalidate()
        foldTimer?.invalidate()
        clock?.invalidate()
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

    private static let leftStyle: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.alignment = .left
        style.lineBreakMode = .byClipping
        return style
    }()

    private static let detailStyle: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.alignment = .left
        style.lineBreakMode = .byTruncatingTail
        return style
    }()

    /// Names and messages: Barlow, sentence case.
    private static func title(_ text: String) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [
            .font: Theme.displayNS(14, .semibold), .foregroundColor: NSColor.white, .paragraphStyle: leftStyle,
        ])
    }

    private static func detail(_ text: String) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [
            .font: Theme.displayNS(12, .semibold), .foregroundColor: NSColor(white: 1, alpha: 0.5),
            .paragraphStyle: detailStyle,
        ])
    }

    /// Numbers (time, "2/3", latency): mono.
    private static func mono(_ text: String, alpha: CGFloat = 0.85) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [
            .font: Theme.monoNS(11, semibold: true), .kern: 0.5,
            .foregroundColor: NSColor(white: 1, alpha: alpha), .paragraphStyle: leftStyle,
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
        guard notice.trailing == .time, let startedAt else { return }
        let seconds = Int(Date().timeIntervalSince(startedAt))
        timeLabel.attributedStringValue = Self.mono(String(format: "%d:%02d", seconds / 60, seconds % 60))
        layoutContent(size: island.bounds.size)
    }

    private func present(_ notice: Notice) {
        self.notice = notice
        foldTimer?.invalidate()
        folded = false
        rowView.alphaValue = 1
        label.attributedStringValue = Self.title(notice.title)
        detailLabel.attributedStringValue = Self.detail(notice.detail ?? "")
        rowIcon.image = notice.icon
        symbolView.image = nil
        switch notice.trailing {
        case .none: timeLabel.stringValue = ""
        case .time: updateClock()
        case .text(let text): timeLabel.attributedStringValue = Self.mono(text)
        case .glyph(let name, let text, let tone):
            let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
            symbolView.image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config)
            symbolView.contentTintColor = tone == .bad ? Theme.ledRedNS : NSColor(white: 1, alpha: tone == .muted ? 0.5 : 0.85)
            timeLabel.attributedStringValue = Self.mono(text ?? "")
        case .success(let text):
            timeLabel.attributedStringValue = Self.mono(text ?? "")
            if !Theme.reduceMotion { checkView.draw(after: 0.25) }
        }
        recDot.pulsing = notice.folds && !Theme.reduceMotion
        if notice.folds {
            foldTimer = Timer.scheduledTimer(withTimeInterval: foldDelay, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.fold() }
            }
        }
        guard let screen = activeScreen() else { return }
        screenFrame = screen.frame
        notchSize = notch(of: screen)
        island.style = notchSize == nil ? .pill : .notch
        spring.floorHeight = notchSize?.height ?? 1

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

    /// Recording: the title row fades, the island shrinks to the two wings.
    private func fold() {
        guard visible, !folded else { return }
        folded = true
        if Theme.reduceMotion {
            rowView.alphaValue = 0
            apply(frame: targetFrame(), openness: 1)
            return
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
            rowView.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.visible, self.folded else { return }
                self.spring.animate(to: self.targetFrame(), .resizing)
            }
        })
    }

    private var showsRow: Bool { !folded }
    private var hasIcon: Bool { notice.icon != nil }
    private var rowHeight: CGFloat { notice.detail == nil ? baseRow : detailRow }

    private var textSize: NSSize {
        let size = label.fittingSize
        return NSSize(width: min(ceil(size.width), maxTitleWidth), height: ceil(size.height))
    }

    private var detailSize: NSSize {
        guard notice.detail != nil else { return .zero }
        let size = detailLabel.fittingSize
        return NSSize(width: min(ceil(size.width), maxTitleWidth), height: ceil(size.height))
    }

    /// Icon + title, centred together.
    private var titleGroupWidth: CGFloat { (hasIcon ? iconSide + 8 : 0) + textSize.width }

    private var rowContentWidth: CGFloat { max(titleGroupWidth, detailSize.width) }

    /// Right wing content: glyph and/or text, or the time, centred together. While recording with
    /// the title row folded away a red dot goes before the time.
    private var trailingItems: [(view: NSView, size: NSSize)] {
        var items: [(NSView, NSSize)] = []
        if folded, notice.folds { items.append((recDot, NSSize(width: 7, height: 7))) }
        switch notice.trailing {
        case .none: break
        case .time, .text:
            items.append((timeLabel, Self.fitted(timeLabel)))
        case .glyph(_, let text, _):
            if symbolView.image != nil { items.append((symbolView, NSSize(width: 16, height: 16))) }
            if text != nil { items.append((timeLabel, Self.fitted(timeLabel))) }
        case .success(let text):
            items.append((checkView, NSSize(width: 20, height: 20)))
            if text != nil { items.append((timeLabel, Self.fitted(timeLabel))) }
        }
        return items
    }

    private static func fitted(_ view: NSTextField) -> NSSize {
        let size = view.fittingSize
        return NSSize(width: ceil(size.width), height: ceil(size.height))
    }

    private var trailingWidth: CGFloat {
        let items = trailingItems
        return items.reduce(0) { $0 + $1.size.width } + 6 * CGFloat(max(0, items.count - 1))
    }

    /// Final frame for the current notice.
    private func targetFrame() -> NSRect {
        if let notch = notchSize {
            let row = showsRow ? rowHeight : compactExtra
            let width = min(max(notch.width + 2 * wing, showsRow ? rowContentWidth + 48 : 0), maxWidth)
            let height = notch.height + row
            return NSRect(x: screenFrame.midX - width / 2, y: screenFrame.maxY - height, width: width, height: height)
        }
        // The pill's round ends eat into the sides: keep a wider margin than a rectangle needs.
        let left = PipsView.size.width + 14
        let right: CGFloat = trailingWidth > 0 ? trailingWidth + 14 : 0
        let side = max(left, right)
        let width = 2 * side + (showsRow ? rowContentWidth + 24 : 0) + 40
        let height = showsRow ? rowHeight : baseRow
        let top = (NSScreen.screens.first { $0.frame == screenFrame }?.visibleFrame.maxY ?? screenFrame.maxY) - 6
        return NSRect(x: screenFrame.midX - width / 2, y: top - height, width: width, height: height)
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
        let detail = detailSize
        let pipsSize = PipsView.size
        let items = trailingItems
        timeLabel.isHidden = !items.contains { $0.view === timeLabel }
        symbolView.isHidden = !items.contains { $0.view === symbolView }
        checkView.isHidden = !items.contains { $0.view === checkView }
        recDot.isHidden = !items.contains { $0.view === recDot }
        rowIcon.isHidden = !hasIcon
        detailLabel.isHidden = notice.detail == nil
        rowView.isHidden = !showsRow

        // The right wing: its items centred together around `centreX`.
        func placeTrailing(centreX: CGFloat, midY: CGFloat) {
            var x = centreX - trailingWidth / 2
            for item in items {
                item.view.frame = NSRect(x: x, y: midY - item.size.height / 2, width: item.size.width, height: item.size.height)
                x += item.size.width + 6
            }
        }
        // Icon + title (and the detail under them) inside the row region, centred together.
        func placeRow(in region: NSRect) {
            rowView.frame = region
            let gap: CGFloat = detail.height > 0 ? 1 : 0
            let block = text.height + gap + detail.height
            let titleY = (region.height - block) / 2 + detail.height + gap
            var x = (region.width - titleGroupWidth) / 2
            if hasIcon {
                rowIcon.frame = NSRect(x: x, y: titleY + (text.height - iconSide) / 2, width: iconSide, height: iconSide)
                x += iconSide + 8
            }
            label.frame = NSRect(x: x, y: titleY, width: text.width, height: text.height)
            detailLabel.frame = NSRect(x: (region.width - detail.width) / 2, y: (region.height - block) / 2,
                                       width: detail.width, height: detail.height)
            let clipped = ceil(label.fittingSize.width) > text.width
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            fadeMask.frame = label.bounds
            label.layer?.mask = clipped ? fadeMask : nil
            CATransaction.commit()
        }

        if let notch = notchSize {
            // Wings beside the notch, title row below it. Without the row the wings sit in the
            // middle of the whole (thicker) island; they glide there as the row goes away.
            let extra = size.height - notch.height
            let folding = max(0, min(1, (extra - compactExtra) / (baseRow - compactExtra)))
            let bandMid = size.height - notch.height / 2 - compactExtra / 2 * (1 - folding)
            let wingWidth = max(0, (size.width - notch.width) / 2)
            pips.frame = NSRect(x: wingWidth / 2 - pipsSize.width / 2, y: bandMid - pipsSize.height / 2,
                                width: pipsSize.width, height: pipsSize.height)
            placeTrailing(centreX: size.width - wingWidth / 2, midY: bandMid)
            placeRow(in: NSRect(x: 0, y: 0, width: size.width, height: max(0, size.height - notch.height)))
        } else {
            // Pill: pips left, right wing right, icon + title centred between them.
            pips.frame = NSRect(x: 18, y: (size.height - pipsSize.height) / 2, width: pipsSize.width, height: pipsSize.height)
            placeTrailing(centreX: size.width - 18 - trailingWidth / 2, midY: size.height / 2)
            placeRow(in: NSRect(origin: .zero, size: size))
        }
    }

    private func springSettled() {
        if !visible { panel.orderOut(nil) }
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

    /// The island never gets shorter than this (the notch), whatever the spring does.
    var floorHeight: CGFloat = 1

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
        onStep?(Self.frame(value, floorHeight: floorHeight), openness)
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

    private static func frame(_ c: [CGFloat], floorHeight: CGFloat) -> NSRect {
        let width = max(1, c[2]), height = max(floorHeight, c[3])
        return NSRect(x: (c[0] - width / 2).rounded(), y: (c[1] - height).rounded(), width: width.rounded(), height: height.rounded())
    }
}

/// A check that draws itself inside a ring (a dictation was written, a command ran).
private final class CheckView: NSView {
    private let ring = CAShapeLayer()
    private let tick = CAShapeLayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        let bounds = CGRect(x: 0, y: 0, width: 20, height: 20)
        ring.path = CGPath(ellipseIn: bounds.insetBy(dx: 1, dy: 1), transform: nil)
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 6, y: 10.5))
        path.addLine(to: CGPoint(x: 9, y: 7.5))
        path.addLine(to: CGPoint(x: 14, y: 13))
        tick.path = path
        for layer in [ring, tick] {
            layer.frame = bounds
            layer.fillColor = nil
            layer.strokeColor = NSColor(white: 1, alpha: 0.85).cgColor
            layer.lineWidth = 1.5
            layer.lineCap = .round
            layer.lineJoin = .round
            self.layer?.addSublayer(layer)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// The ring then the tick, in 0.3 s, starting `delay` from now (as the island opens).
    func draw(after delay: TimeInterval) {
        let start = CACurrentMediaTime() + delay
        for (layer, begin, duration) in [(ring, 0.0, 0.2), (tick, 0.15, 0.15)] {
            let stroke = CABasicAnimation(keyPath: "strokeEnd")
            stroke.fromValue = 0
            stroke.toValue = 1
            stroke.duration = duration
            stroke.beginTime = start + begin
            stroke.fillMode = .backwards
            stroke.timingFunction = CAMediaTimingFunction(name: .easeOut)
            layer.add(stroke, forKey: "draw")
        }
    }
}

/// The recording dot of the folded island: red, breathing slowly.
private final class RecDotView: NSView {
    var pulsing = false {
        didSet { if pulsing != oldValue { updatePulse() } }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = Theme.ledRedNS.cgColor
        layer?.cornerRadius = 3.5
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func updatePulse() {
        layer?.removeAnimation(forKey: "breathe")
        guard pulsing else { return }
        let breathe = CABasicAnimation(keyPath: "opacity")
        breathe.fromValue = 1
        breathe.toValue = 0.35
        breathe.duration = 1.0
        breathe.autoreverses = true
        breathe.repeatCount = .infinity
        breathe.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer?.add(breathe, forKey: "breathe")
    }
}

/// Two rows of pips mirroring the mic's LEDs: red = channel (top), white = slot number in
/// binary (bottom). A lit pip is stretched; an unlit one is a dot (a bound channel is dim red,
/// a free one is nearly off, an unlit white is grey). Every pip has its own fixed cell, so the
/// recording sweep moves without shifting its neighbours. Steps with each mask, like the hardware.
private final class PipsView: NSView {
    static let dot: CGFloat = 6, cell: CGFloat = 12, gap: CGFloat = 3, rowGap: CGFloat = 4
    static let size = NSSize(width: 4 * cell + 3 * gap, height: 2 * dot + rowGap)

    var mask: UInt8 = 0 {
        didSet { if mask != oldValue { update() } }
    }
    var channels = 0 {
        didSet { if channels != oldValue { update() } }
    }

    private let red = (0..<4).map { _ in CALayer() }
    private let white = (0..<4).map { _ in CALayer() }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        for layer in red + white {
            layer.cornerRadius = Self.dot / 2
            layer.shadowOffset = .zero
            layer.shadowRadius = 3
            self.layer?.addSublayer(layer)
        }
        update()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layout() {
        super.layout()
        update()
    }

    private func update() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let ledRed = Theme.ledRedNS
        for (index, layer) in red.enumerated() {
            let lit = mask & (1 << index) != 0
            let color = lit ? ledRed : (index < channels ? ledRed.withAlphaComponent(0.45) : Theme.ledRedOffNS.withAlphaComponent(0.6))
            style(layer, color: color, lit: lit, glow: lit ? ledRed : nil)
        }
        for (index, layer) in white.enumerated() {
            let lit = mask & (1 << (4 + index)) != 0
            style(layer, color: lit ? .white : Theme.ledWhiteOffNS.withAlphaComponent(0.55), lit: lit, glow: lit ? .white : nil)
        }
        place(red, y: bounds.height - Self.dot)
        place(white, y: 0)
        CATransaction.commit()
    }

    private func style(_ layer: CALayer, color: NSColor, lit: Bool, glow: NSColor?) {
        layer.backgroundColor = color.cgColor
        layer.bounds.size = NSSize(width: lit ? Self.cell : Self.dot, height: Self.dot)
        layer.shadowColor = (glow ?? .clear).cgColor
        layer.shadowOpacity = glow == nil ? 0 : 0.9
    }

    /// Each pip centred in its cell; the row centred in the view.
    private func place(_ row: [CALayer], y: CGFloat) {
        let left = (bounds.width - Self.size.width) / 2
        for (index, layer) in row.enumerated() {
            let cellX = left + CGFloat(index) * (Self.cell + Self.gap)
            layer.frame = CGRect(x: cellX + (Self.cell - layer.bounds.width) / 2, y: y,
                                 width: layer.bounds.width, height: Self.dot)
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

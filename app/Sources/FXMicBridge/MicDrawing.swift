import FXMicCore
import SwiftUI

/// The parts of the mic a user can press (and click in the drawing).
enum MicPart: Hashable, CaseIterable {
    case handle, orange, white, grey

    var control: DeviceControl {
        switch self {
        case .handle: return .handle
        case .orange: return .orange
        case .white: return .white
        case .grey: return .grey
        }
    }
}

/// The EP-2350 FX-MIC redrawn as flat vector art (style homage, not a trace; same drawing as
/// the teaser video's fxmic-device.svg). Live: LEDs follow `mask` (logical bits 0–3 red,
/// 4–7 white), pressed controls move, the highlighted part gets an orange outline.
/// Coordinates are the SVG's (viewBox −70 0 520 760), scaled to fit.
struct MicDrawing: View {
    var mask: UInt8 = 0
    var pressed: Set<DeviceControl> = []
    var highlight: MicPart?
    var onTap: ((MicPart) -> Void)?

    private static let viewBox = CGRect(x: -70, y: 0, width: 520, height: 760)
    private static let ink = Color(nsColor: Theme.inkHex)
    @Environment(\.colorScheme) private var scheme

    /// Outlines sit on the device's light surfaces and stay ink; the cable and the selection
    /// halo sit on the window ground, so they follow light/dark.
    private var groundLine: Color { scheme == .dark ? Color(nsColor: Theme.paperHex).opacity(0.75) : MicDrawing.ink }
    private var halo: Color { scheme == .dark ? Theme.accent.opacity(0.7) : MicDrawing.ink.opacity(0.35) }

    var body: some View {
        Canvas { context, size in
            let scale = min(size.width / Self.viewBox.width, size.height / Self.viewBox.height)
            let dx = (size.width - Self.viewBox.width * scale) / 2 - Self.viewBox.minX * scale
            let dy = (size.height - Self.viewBox.height * scale) / 2
            context.translateBy(x: dx, y: dy)
            context.scaleBy(x: scale, y: scale)
            draw(in: &context)
        }
        .aspectRatio(Self.viewBox.width / Self.viewBox.height, contentMode: .fit)
        .contentShape(Rectangle())
        .onTapGesture(coordinateSpace: .local) { location in
            // The tap location is in view points: re-run the fit to get SVG coordinates.
            guard let onTap else { return }
            onTapAt(location, onTap)
        }
        .background(GeometryReader { proxy in Color.clear.preference(key: SizeKey.self, value: proxy.size) })
        .onPreferenceChange(SizeKey.self) { viewSize = $0 }
        .animation(Theme.reduceMotion ? nil : .linear(duration: 0.08), value: pressed)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("EP-2350 FX-MIC")
    }

    @State private var viewSize: CGSize = .zero

    private func onTapAt(_ point: CGPoint, _ handler: (MicPart) -> Void) {
        let size = viewSize
        guard size.width > 0 else { return }
        let scale = min(size.width / Self.viewBox.width, size.height / Self.viewBox.height)
        let x = (point.x - (size.width - Self.viewBox.width * scale) / 2) / scale + Self.viewBox.minX
        let y = (point.y - (size.height - Self.viewBox.height * scale) / 2) / scale
        let p = CGPoint(x: x, y: y)
        for part in [MicPart.orange, .white, .grey] where hitRect(part).insetBy(dx: -10, dy: -8).contains(p) {
            handler(part)
            return
        }
        if CGRect(x: -60, y: 40, width: 110, height: 230).contains(p) { handler(.handle) }
    }

    private func hitRect(_ part: MicPart) -> CGRect {
        switch part {
        case .orange: return CGRect(x: 344, y: 78, width: 34, height: 74)
        case .white: return CGRect(x: 344, y: 206, width: 34, height: 62)
        case .grey: return CGRect(x: 344, y: 392, width: 34, height: 62)
        case .handle: return CGRect(x: -46, y: 46, width: 132, height: 214)
        }
    }

    // MARK: - Drawing

    private func stroke(_ context: inout GraphicsContext, _ path: Path, width: CGFloat = 3, color: Color = MicDrawing.ink) {
        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineJoin: .round))
    }

    private func draw(in context: inout GraphicsContext) {
        // Handle: rotates towards the body while held.
        let handleAngle: Double = pressed.contains(.handle) ? -3 : -12
        var handle = context
        handle.translateBy(x: 20, y: 150)
        handle.rotate(by: .degrees(handleAngle))
        handle.translateBy(x: -20, y: -150)
        let lever = Path(roundedRect: CGRect(x: -46, y: 46, width: 132, height: 214), cornerRadius: 14)
        if highlight == .handle {
            handle.stroke(lever, with: .color(halo), lineWidth: 16)
        }
        handle.fill(lever, with: .color(Theme.accent))
        stroke(&handle, lever)

        // Curly cable.
        var cable = Path()
        cable.move(to: CGPoint(x: 200, y: 540))
        cable.addLine(to: CGPoint(x: 200, y: 558))
        var y: CGFloat = 558
        for i in 0..<7 {
            let side: CGFloat = i % 2 == 0 ? -40 : 40
            cable.addCurve(to: CGPoint(x: 200, y: y + 22), control1: CGPoint(x: 200 + side, y: y), control2: CGPoint(x: 200 + side, y: y + 22))
            y += 22
        }
        cable.addLine(to: CGPoint(x: 200, y: y + 40))
        context.stroke(cable, with: .color(groundLine), style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))

        // Side buttons (behind the body edge): pressed ones slide in.
        let buttons: [(MicPart, Color)] = [
            (.orange, Theme.accent),
            (.white, Color(red: 0xF7 / 255, green: 0xF7 / 255, blue: 0xF3 / 255)),
            (.grey, Color(red: 0xA3 / 255, green: 0xA3 / 255, blue: 0x9E / 255)),
        ]
        for (part, fill) in buttons {
            let rect = hitRect(part).offsetBy(dx: pressed.contains(part.control) ? -12 : 0, dy: 0)
            let path = Path(roundedRect: rect, cornerRadius: 8)
            if highlight == part {
                context.stroke(path, with: .color(halo), lineWidth: 16)
            }
            context.fill(path, with: .color(fill))
            stroke(&context, path)
        }

        // Body, grille panel and dot grille.
        let body = Path(roundedRect: CGRect(x: 40, y: 20, width: 320, height: 520), cornerRadius: 24)
        context.fill(body, with: .color(Color(red: 0xE6 / 255, green: 0xE6 / 255, blue: 0xE1 / 255)))
        stroke(&context, body)
        var panel = Path()
        panel.move(to: CGPoint(x: 64, y: 20))
        panel.addLine(to: CGPoint(x: 336, y: 20))
        panel.addArc(tangent1End: CGPoint(x: 360, y: 20), tangent2End: CGPoint(x: 360, y: 44), radius: 24)
        panel.addLine(to: CGPoint(x: 360, y: 318))
        panel.addLine(to: CGPoint(x: 40, y: 318))
        panel.addLine(to: CGPoint(x: 40, y: 44))
        panel.addArc(tangent1End: CGPoint(x: 40, y: 20), tangent2End: CGPoint(x: 64, y: 20), radius: 24)
        panel.closeSubpath()
        context.fill(panel, with: .color(Color(red: 0x4E / 255, green: 0x4E / 255, blue: 0x4B / 255)))
        stroke(&context, panel)
        var dots = Path()
        for row in 0..<12 {
            for column in 0..<11 {
                dots.addEllipse(in: CGRect(x: 68 + CGFloat(column) * 22 - 6.5, y: 52 + CGFloat(row) * 22 - 6.5, width: 13, height: 13))
            }
        }
        context.fill(dots, with: .color(Color(red: 0x2E / 255, green: 0x2E / 255, blue: 0x2C / 255)))

        // LED column: 4 red (mode / KITT) over 4 white (slot in binary).
        context.fill(Path(roundedRect: CGRect(x: 316, y: 44, width: 30, height: 258), cornerRadius: 15),
                     with: .color(Color(red: 0x3A / 255, green: 0x3A / 255, blue: 0x38 / 255)))
        let centres: [CGFloat] = [66, 96, 126, 156, 196, 226, 256, 286]
        for (bit, cy) in centres.enumerated() {
            let on = mask & (1 << bit) != 0
            let red = bit < 4
            let rect = CGRect(x: 331 - 8, y: cy - 8, width: 16, height: 16)
            if on {
                var glow = context
                glow.addFilter(.blur(radius: 7))
                glow.fill(Path(ellipseIn: rect.insetBy(dx: -3, dy: -3)), with: .color(red ? Theme.ledRed : .white))
            }
            let color = on ? (red ? Theme.ledRed : Theme.ledWhite) : (red ? Theme.ledRedOff : Theme.ledWhiteOff)
            context.fill(Path(ellipseIn: rect), with: .color(color))
        }

        // Lower plate: screws and the name tag.
        var line = Path()
        line.move(to: CGPoint(x: 40, y: 318))
        line.addLine(to: CGPoint(x: 360, y: 318))
        stroke(&context, line)
        for (cx, cy) in [(70.0, 348.0), (330, 348), (70, 510), (330, 510)] {
            stroke(&context, Path(ellipseIn: CGRect(x: cx - 9, y: cy - 9, width: 18, height: 18)), width: 2.5)
            var slot = Path()
            slot.move(to: CGPoint(x: cx - 6, y: cy))
            slot.addLine(to: CGPoint(x: cx + 6, y: cy))
            stroke(&context, slot, width: 2.5)
        }
        stroke(&context, Path(roundedRect: CGRect(x: 130, y: 408, width: 140, height: 40), cornerRadius: 6), width: 2.5)
        let tag = Text("CUE-2350").font(Theme.mono(15, semibold: true)).tracking(2).foregroundColor(MicDrawing.ink)
        context.draw(tag, at: CGPoint(x: 200, y: 428))
    }
}

private struct SizeKey: PreferenceKey {
    static let defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}

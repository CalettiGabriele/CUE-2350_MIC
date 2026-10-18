import AppKit
import CoreText
import SwiftUI

/// Visual identity ("Chapter 8": an unofficial chapter of the EP-2350 guide), shared by the
/// HUD, the menu bar and the SwiftUI windows. Paper / ink grounds, ONE accent (fire orange),
/// red only for LEDs and recording, Barlow lowercase display, IBM Plex Mono uppercase chrome,
/// flat surfaces with 1px rules.
enum Theme {
    // MARK: Colours

    static let inkHex = NSColor(srgbRed: 0x1A / 255, green: 0x1A / 255, blue: 0x1A / 255, alpha: 1)
    static let paperHex = NSColor(srgbRed: 0xED / 255, green: 0xED / 255, blue: 0xE8 / 255, alpha: 1)
    static let accentNS = NSColor(srgbRed: 0xF0 / 255, green: 0x5A / 255, blue: 0x28 / 255, alpha: 1)
    static let ledRedNS = NSColor(srgbRed: 0xE3 / 255, green: 0x24 / 255, blue: 0x2B / 255, alpha: 1)
    static let ledRedOffNS = NSColor(srgbRed: 0x5B / 255, green: 0x2B / 255, blue: 0x28 / 255, alpha: 1)
    static let ledWhiteOffNS = NSColor(srgbRed: 0x6E / 255, green: 0x6E / 255, blue: 0x6A / 255, alpha: 1)

    private static func dynamic(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        }
    }

    static let groundNS = dynamic(light: paperHex, dark: inkHex)
    static let inkNS = dynamic(light: inkHex, dark: paperHex)
    static let ruleNS = dynamic(light: NSColor(srgbRed: 0xC9 / 255, green: 0xC9 / 255, blue: 0xC3 / 255, alpha: 1),
                                dark: NSColor(srgbRed: 0x28 / 255, green: 0x27 / 255, blue: 0x26 / 255, alpha: 1))
    /// Grey chapter bar of the guide.
    static let barNS = dynamic(light: NSColor(srgbRed: 0x5E / 255, green: 0x5E / 255, blue: 0x5B / 255, alpha: 1),
                               dark: NSColor(srgbRed: 0x3A / 255, green: 0x3A / 255, blue: 0x38 / 255, alpha: 1))

    static let ground = Color(nsColor: groundNS)
    static let ink = Color(nsColor: inkNS)
    static let muted = Color(nsColor: NSColor(srgbRed: 0x8C / 255, green: 0x8C / 255, blue: 0x88 / 255, alpha: 1))
    static let rule = Color(nsColor: ruleNS)
    static let bar = Color(nsColor: barNS)
    static let accent = Color(nsColor: accentNS)
    static let ledRed = Color(nsColor: ledRedNS)
    static let ledRedOff = Color(nsColor: ledRedOffNS)
    static let ledWhite = Color.white
    static let ledWhiteOff = Color(nsColor: ledWhiteOffNS)

    // MARK: Type

    /// Registers the bundled fonts (Contents/Resources/Fonts). Without them (e.g. `swift run`)
    /// every role falls back to the system fonts.
    static func registerFonts() {
        guard let dir = Bundle.main.resourceURL?.appendingPathComponent("Fonts"),
              let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
        for url in files where ["woff2", "ttf", "otf"].contains(url.pathExtension) {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    enum Weight { case semibold, extrabold, black }

    /// Barlow for display: titles are written lowercase by the caller.
    static func displayNS(_ size: CGFloat, _ weight: Weight = .black) -> NSFont {
        let name: String
        let fallback: NSFont.Weight
        switch weight {
        case .semibold: (name, fallback) = ("Barlow-SemiBold", .semibold)
        case .extrabold: (name, fallback) = ("Barlow-ExtraBold", .heavy)
        case .black: (name, fallback) = ("Barlow-Black", .black)
        }
        return NSFont(name: name, size: size) ?? .systemFont(ofSize: size, weight: fallback)
    }

    /// IBM Plex Mono for chrome (kickers, numbers, labels): uppercase, tracked.
    static func monoNS(_ size: CGFloat, semibold: Bool = false) -> NSFont {
        NSFont(name: semibold ? "IBMPlexMono-SemiBold" : "IBMPlexMono-Medium", size: size)
            ?? .monospacedSystemFont(ofSize: size, weight: semibold ? .semibold : .medium)
    }

    static func display(_ size: CGFloat, _ weight: Weight = .black) -> Font { Font(displayNS(size, weight)) }
    static func mono(_ size: CGFloat, semibold: Bool = false) -> Font { Font(monoNS(size, semibold: semibold)) }

    /// Tracking for mono chrome (0.14em).
    static func monoTracking(_ size: CGFloat) -> CGFloat { size * 0.14 }

    // MARK: Motion

    /// "Paper" motion: panels, bars and callouts wipe in.
    static let paperDuration: TimeInterval = 0.22
    static let paperTiming = CAMediaTimingFunction(controlPoints: 0.22, 1, 0.36, 1)   // ≈ power3.out
    static var paperAnimation: Animation { reduceMotion ? .linear(duration: 0.12) : .timingCurve(0.22, 1, 0.36, 1, duration: paperDuration) }

    static var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    /// "((8.1))" chapter numbering.
    static func chapter(_ number: String) -> String { "((\(number)))" }
}

// MARK: - Components

/// Uppercase mono eyebrow.
struct Kicker: View {
    let text: String
    var color: Color = Theme.muted
    var size: CGFloat = 10

    var body: some View {
        Text(text.uppercased())
            .font(Theme.mono(size))
            .tracking(Theme.monoTracking(size))
            .foregroundStyle(color)
    }
}

/// 36×2 accent stub: the system's only ornament.
struct RuleStub: View {
    var body: some View { Rectangle().fill(Theme.accent).frame(width: 36, height: 2) }
}

/// Page header in the guide's style: grey chapter bar with the number, lowercase Barlow
/// title, optional mono kicker.
struct ChapterHeader: View {
    let number: String
    let title: String
    var kicker: String?
    @State private var shown = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 0) {
                Text(Theme.chapter(number))
                    .font(Theme.mono(11, semibold: true))
                    .tracking(Theme.monoTracking(11))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 10)
                    .frame(height: 22)
                    .background(Theme.bar)
                Rectangle().fill(Theme.bar).frame(height: 2)
                    .scaleEffect(x: shown ? 1 : 0, anchor: .leading)
            }
            Text(title.lowercased())
                .font(Theme.display(34))
                .tracking(-34 * 0.03)
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let kicker {
                HStack(spacing: 8) {
                    RuleStub()
                    Kicker(text: kicker)
                }
            }
        }
        .onAppear { withAnimation(Theme.paperAnimation) { shown = true } }
    }
}

/// One LED as drawn in the app: off colour, or lit with a soft glow.
struct LEDDot: View {
    let on: Bool
    let red: Bool
    var size: CGFloat = 8

    var body: some View {
        Circle()
            .fill(on ? (red ? Theme.ledRed : Theme.ledWhite) : (red ? Theme.ledRedOff : Theme.ledWhiteOff))
            .frame(width: size, height: size)
            .shadow(color: on ? (red ? Theme.ledRed : .white).opacity(0.8) : .clear, radius: on ? size * 0.6 : 0)
    }
}

/// Flat button: ink outline, accent fill when prominent, no radius.
struct FlatButtonStyle: ButtonStyle {
    var prominent = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.mono(11, semibold: true))
            .tracking(Theme.monoTracking(11))
            .textCase(.uppercase)
            .padding(.horizontal, 12)
            .frame(height: 26)
            .foregroundStyle(prominent ? Theme.inkHexColor : Theme.ink)
            .background(prominent ? Theme.accent : Color.clear)
            .overlay(Rectangle().strokeBorder(prominent ? Color.clear : Theme.ink.opacity(0.6), lineWidth: 1))
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.35)
            .scaleEffect(configuration.isPressed && !Theme.reduceMotion ? 0.96 : 1)
            .animation(.linear(duration: 0.08), value: configuration.isPressed)
    }
}

extension Theme {
    /// Ink on fire orange is absolute (never cream on orange).
    static let inkHexColor = Color(nsColor: inkHex)
}

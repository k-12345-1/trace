import SwiftUI

/// The Trace identity, ported to SwiftUI.
/// Dark-first: the hero surface is always footage of a climber in a dim gym.
enum Theme {

    // MARK: Ground and surfaces
    //
    // White and blue. The app chrome is paper: a light ground reads as a notebook
    // you write your climbing into, and it keeps every surface out of the way of
    // the one thing that is actually dark, which is footage of a gym.
    static let ground   = Color(hex: 0xFCFBF6)   // warm paper, not white
    static let surface  = Color(hex: 0xF4F2E9)
    static let surface2 = Color(hex: 0xE9E6D9)
    static let line     = Color(hex: 0xE6E2D5)
    static let lineStrong = Color(hex: 0xD2CDBC)

    /// Cards are separated by fill and a little lift, not by a drawn border.
    /// A 1 pixel outline on every surface is what makes a layout look ruled
    /// rather than composed.
    static let lift = Color(hex: 0x22269B).opacity(0.07)

    /// The ink. One blue does everything: the wordmark, the mark, the buttons,
    /// the links. A single pigment on paper is the whole idea, so a second
    /// accent would break it rather than help.
    static let blue      = Color(hex: 0x22269B)
    static let blueLight = Color(hex: 0x4A4FBE)
    static let blueWash  = Color(hex: 0x22269B).opacity(0.07)

    /// Kept so older code that asked for the banner colour still compiles.
    static let wine = blue

    // MARK: Ink
    static let ink   = Color(hex: 0x15162E)      // near-black, carrying the blue
    static let ink2  = Color(hex: 0x4C4E6B)
    static let ink3  = Color(hex: 0x8A8B9E)

    // MARK: Accent
    //
    // The same ink. Hierarchy comes from weight, size and ground rather than
    // from a second hue, which is what makes a one-pigment identity hold.
    static let accent     = Color(hex: 0x22269B)
    static let accentText = Color(hex: 0x22269B)
    static let accentWash = Color(hex: 0x22269B).opacity(0.09)

    /// Affirmative. The same blue: with no green in the palette, a cleared focus
    /// is told apart from an open one by its words and its ground, not its hue.
    static let ok = accent

    /// Severity ramp. A leak costs more or less, so it gets a ramp and not a
    /// traffic light. Status colour, deliberately outside the brand pair.
    static let ember: [Color] = [
        Color(hex: 0xE8B44A), Color(hex: 0xE09338), Color(hex: 0xD4702B),
        Color(hex: 0xC24D28), Color(hex: 0x9E2E1E)
    ]

    /// Skeleton overlay colour. Chalk, so it never competes with the accent.
    static let chalk = Color(hex: 0xF5F0EA)

    // MARK: Radius
    //
    // Generous. The old near-square corners read as instrument panel, which is
    // accurate about what the app does and wrong about how it should feel to
    // open.
    static let rSmall: CGFloat = 9     // chips and small marks
    static let r: CGFloat = 14         // fields and inline controls
    static let rCard: CGFloat = 20     // cards, photos, sheets
    static let rPill: CGFloat = 999    // buttons

    // MARK: Rhythm
    static let gutter: CGFloat = 22    // page margin
    static let gap: CGFloat = 12       // between siblings

    // MARK: Type.
    //
    // Inter for the interface, matching KAYA. Numbers stay monospaced: Inter has
    // no mono cut, and every readout in this app depends on tabular digits lining
    // up, so SF Mono keeps that job.
    static func ui(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        if let name = Fonts.name(for: weight) {
            return .custom(name, size: size)
        }
        return .system(size: size, weight: weight, design: .default)
    }

    /// Titles are set in a serif. It is the one decision that stops the app
    /// looking like every other SwiftUI app: everything else on screen is a
    /// neutral grotesque, so an old-style serif on the headings reads as a
    /// choice rather than a default. New York ships with the system, so there
    /// is nothing to bundle and nothing to license.
    static func serif(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    static func display(_ size: CGFloat = 32) -> Font { serif(size, .bold) }
    static func title(_ size: CGFloat = 28) -> Font { serif(size, .semibold) }
    static func heading(_ size: CGFloat = 19) -> Font { serif(size, .semibold) }
    static func body(_ size: CGFloat = 15) -> Font { ui(size, .regular) }
    /// Readouts. A metric should look like an instrument, not like body copy.
    static func readout(_ size: CGFloat = 27) -> Font {
        .system(size: size, weight: .medium, design: .monospaced)
    }
    static func mono(_ size: CGFloat = 12, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

// MARK: - Micro label

/// Uppercase mono with tracking. The single strongest signal that this is a technical tool.
struct MicroLabel: View {
    let text: String
    var color: Color = Theme.ink3
    var body: some View {
        Text(text.uppercased())
            .font(Theme.ui(11, .semibold))
            .tracking(0.7)
            .foregroundStyle(color)
    }
}

// MARK: - Card

/// A surface that reads as an object: filled, rounded, lifted a little, and
/// with no drawn edge.
struct CardSurface: ViewModifier {
    var radius: CGFloat = Theme.rCard
    var fill: Color = Theme.surface
    func body(content: Content) -> some View {
        content
            .background(fill)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .shadow(color: Theme.lift, radius: 10, y: 3)
    }
}

extension View {
    func card(radius: CGFloat = Theme.rCard, fill: Color = Theme.surface) -> some View {
        modifier(CardSurface(radius: radius, fill: fill))
    }
}

// MARK: - Hairline

struct Hairline: View {
    var color: Color = Theme.line
    var body: some View { Rectangle().fill(color).frame(height: 1) }
}

// MARK: - Helpers

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red:   Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8)  & 0xFF) / 255,
            blue:  Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

import SwiftUI

/// The Trace identity, ported to SwiftUI.
/// Dark-first: the hero surface is always footage of a climber in a dim gym.
enum Theme {

    // MARK: Ground and surfaces
    //
    // Four colors and nothing else: white, a light gray, a light blue and a
    // dark blue. Everything on screen is one of those, at a weight or an
    // opacity. The gray is given a blue cast so it belongs to the same family
    // rather than sitting beside it as a neutral.
    static let ground   = Color(hex: 0xFFFFFF)
    static let surface  = Color(hex: 0xF2F5F9)   // the light gray
    static let surface2 = Color(hex: 0xE5EBF2)
    static let line     = Color(hex: 0xE8EDF3)
    static let lineStrong = Color(hex: 0xCBD6E2)

    /// Cards are separated by fill and a little lift, not by a drawn border.
    /// A 1 pixel outline on every surface is what makes a layout look ruled
    /// rather than composed.
    static let lift = Color(hex: 0x0F2C5C).opacity(0.07)

    /// The two blues. Dark carries the words and the actions; light carries the
    /// washes, the highlights and the low end of the severity ramp.
    static let blue      = Color(hex: 0x0F2C5C)
    static let blueLight = Color(hex: 0x5B95D6)
    static let blueWash  = Color(hex: 0x5B95D6).opacity(0.13)

    /// Kept so older code that asked for the banner color still compiles.
    static let wine = blue

    // MARK: Ink
    //
    // Text is the dark blue rather than a black, so the page has no fifth color
    // hiding in it.
    static let ink   = Color(hex: 0x0F2C5C)
    static let ink2  = Color(hex: 0x4A6183)
    static let ink3  = Color(hex: 0x8C9CB0)

    // MARK: Accent
    //
    // The dark blue. Hierarchy comes from weight, size and ground rather than
    // from a second hue, which is what makes a small palette hold together.
    static let accent     = Color(hex: 0x0F2C5C)
    static let accentText = Color(hex: 0x1C4C8F)
    static let accentWash = Color(hex: 0x5B95D6).opacity(0.13)

    /// Affirmative. The same blue: a cleared focus is told apart from an open
    /// one by its words and its ground, not by its hue.
    static let ok = accent

    /// Severity ramp, light blue into dark blue.
    ///
    /// A leak costs more or less, so it is a magnitude, and a magnitude belongs
    /// on one hue running light to dark rather than on a traffic light. It never
    /// carries the meaning alone: every severity mark ships beside its own word.
    static let ember: [Color] = [
        Color(hex: 0xBBD4EE), Color(hex: 0x8FB6E0), Color(hex: 0x5B95D6),
        Color(hex: 0x2E639F), Color(hex: 0x0F2C5C)
    ]

    /// Overlay ink on footage, where the ground is a gym wall rather than a page.
    static let chalk = Color(hex: 0xFFFFFF)

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

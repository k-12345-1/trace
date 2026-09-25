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
    // The ground is the logo's paper, sampled off the artwork rather than
    // picked: #FAF9F4 is the average of its clean margin. Pure white beside a
    // cream print makes the print look like a sticker someone put on a screen.
    //
    // The grays are warmed to match. They used to carry a blue cast so they
    // belonged to the blue family; on cream a blue-gray reads as cold and the
    // page stops being paper, so they carry the paper's cast instead.
    static let ground   = Color(hex: 0xFAF9F4)
    static let surface  = Color(hex: 0xF1EFE7)   // the light gray
    static let surface2 = Color(hex: 0xE6E3D8)
    static let line     = Color(hex: 0xEAE7DD)
    static let lineStrong = Color(hex: 0xD2CCBD)

    /// Cards are separated by fill and a little lift, not by a drawn border.
    /// A 1 pixel outline on every surface is what makes a layout look ruled
    /// rather than composed.
    static let lift = Color(hex: 0x0F2C5C).opacity(0.07)

    /// The two blues. Dark carries the words and the actions; light carries the
    /// washes, the highlights and the low end of the severity ramp.
    static let blue      = Color(hex: 0x0F2C5C)
    // A tint of the logo's ink rather than a separate sky blue. Two blues that
    // are nearly the same hue read as a mistake; one hue at two strengths reads
    // as a choice.
    static let blueLight = Color(hex: 0x8094D0)
    static let blueWash  = Color(hex: 0x8094D0).opacity(0.16)

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
    // The ink from the logo, #0128A1, sampled off the solid of the wordmark.
    // It is what the actions and the links are set in, so the brightest thing
    // on a page is the same blue as the mark at the top of it.
    //
    // Text stays the navy. Body copy in this ultramarine would be shouting, and
    // an app is mostly body copy. White on the ink measures about twelve to
    // one, and the ink on the paper about eleven to one, so both are well clear
    // of what small text needs.
    static let accent     = Color(hex: 0x0128A1)
    static let accentText = Color(hex: 0x0128A1)
    static let accentWash = Color(hex: 0x0128A1).opacity(0.07)

    /// What a solid control is painted in.
    ///
    /// The navy, not the ultramarine. A button is the largest area of color on
    /// a page, and a large field of the logo's ink next to a bar of navy made
    /// the two read as two brands rather than one: near the same hue, far
    /// enough apart to look like a mistake. So the solids are all the navy,
    /// which the bar already was, and the ultramarine is kept for the small
    /// things it flatters: links, the words you can tap, a marked value.
    static let button = blue

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

    /// Efficiency, worst to best, in five steps.
    ///
    /// The one place in Trace that uses hue to carry meaning. Everything else
    /// is one blue running light to dark, deliberately, and this breaks that
    /// rule because red through green is the one scale a climber already reads
    /// without being taught it.
    ///
    /// Breaking the rule costs something, and it is paid for rather than
    /// ignored. Red and green are the pair most commonly confused, so the ramp
    /// is stepped in lightness as well as hue: the worst end is dark and the
    /// best end is light, which survives being seen in greyscale. And the color
    /// never carries the meaning on its own. Every place it appears, the word
    /// and the position on a five step scale appear with it.
    static let efficiency: [Color] = [
        Color(hex: 0xA3212B),   // 1, darkest
        Color(hex: 0xCE6A1E),
        Color(hex: 0xD9A409),
        Color(hex: 0x7FA53A),
        Color(hex: 0x4E9B5B)    // 5, lightest
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
    /// A gym tile. Anything drawn to the edge of one has to use this, or it is
    /// drawn outside the clip and loses its corners.
    static let rTile: CGFloat = 22
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

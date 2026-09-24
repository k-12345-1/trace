import SwiftUI

/// The Trace identity, ported to SwiftUI.
/// Dark-first: the hero surface is always footage of a climber in a dim gym.
enum Theme {

    // MARK: Ground and surfaces
    //
    // White and blue. The app chrome is paper: a light ground reads as a notebook
    // you write your climbing into, and it keeps every surface out of the way of
    // the one thing that is actually dark, which is footage of a gym.
    static let ground   = Color(hex: 0xFFFFFF)
    static let surface  = Color(hex: 0xF4F6F9)
    static let surface2 = Color(hex: 0xE8EDF3)
    static let line     = Color(hex: 0xEBEFF4)
    static let lineStrong = Color(hex: 0xD6DEE7)

    /// Cards are separated by fill and a little lift, not by a drawn border.
    /// A 1 pixel outline on every surface is what makes a layout look ruled
    /// rather than composed.
    static let lift = Color(hex: 0x16395E).opacity(0.07)

    /// The blue. Mastheads, banners, anything that needs to carry the identity
    /// rather than ask for a tap.
    static let blue      = Color(hex: 0x16395E)
    static let blueLight = Color(hex: 0x2C6396)
    static let blueWash  = Color(hex: 0x16395E).opacity(0.06)

    /// Kept so older code that asked for the banner colour still compiles.
    static let wine = blue

    // MARK: Ink
    static let ink   = Color(hex: 0x101C26)      // near-black with a blue cast
    static let ink2  = Color(hex: 0x4B5B68)
    static let ink3  = Color(hex: 0x8799A6)

    // MARK: Accent
    //
    // Green, and a deep one rather than a neon: it marks the thing to press and
    // the tab you are on, and nothing else.
    static let accent     = Color(hex: 0x17875A)
    static let accentText = Color(hex: 0x116347)  // darkened for legibility on white
    static let accentWash = Color(hex: 0x17875A).opacity(0.10)

    static let ok = Color(hex: 0x17875A)

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

    static func display(_ size: CGFloat = 32) -> Font { ui(size, .bold) }
    static func title(_ size: CGFloat = 28) -> Font { ui(size, .bold) }
    static func heading(_ size: CGFloat = 19) -> Font { ui(size, .semibold) }
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

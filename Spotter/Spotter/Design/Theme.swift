import SwiftUI

/// The Spotter identity, ported to SwiftUI.
/// Dark-first: the hero surface is always footage of a climber in a dim gym.
enum Theme {

    // MARK: Ground and surfaces
    //
    // Oxblood and vermilion, taken from the Arc'teryx knitwear palette. The ground
    // is the beanie colour taken almost to black, because the hero surface is always
    // video of a climber: a fully saturated wine ground would cast the footage and
    // fight it. The wine itself is kept for raised surfaces, where it can be seen.
    static let ground   = Color(hex: 0x140A0C)   // near-black, wine cast
    static let surface  = Color(hex: 0x1F0E12)
    static let surface2 = Color(hex: 0x2D141A)
    static let line     = Color(hex: 0x3A181E)
    static let lineStrong = Color(hex: 0x56242C)

    /// The beanie itself. Banners, washes, the app icon ground.
    static let wine = Color(hex: 0x5C1A23)

    // MARK: Ink
    static let ink   = Color(hex: 0xF2EDE8)      // warm bone, never pure white
    static let ink2  = Color(hex: 0xB3A49F)
    static let ink3  = Color(hex: 0x7C6B67)

    // MARK: Accent. The Archaeopteryx vermilion. Spent on the centre-of-mass
    // trace and almost nowhere else.
    static let accent     = Color(hex: 0xE8452A)
    static let accentText = Color(hex: 0xFF6A4D)  // lifted for legibility on the dark ground
    static let accentWash = Color(hex: 0xE8452A).opacity(0.16)

    static let ok = Color(hex: 0x74B183)

    /// Ember ramp. Leak severity is magnitude, so it gets a ramp and not a traffic
    /// light. It runs from a pale wash down into the oxblood.
    static let ember: [Color] = [
        Color(hex: 0xF7C9B4), Color(hex: 0xF09B78), Color(hex: 0xEA6F45),
        Color(hex: 0xE8452A), Color(hex: 0x9E2417)
    ]

    /// Skeleton overlay colour. Chalk, so it never competes with the accent.
    static let chalk = Color(hex: 0xF5F0EA)

    // MARK: Radius. Low radius reads as instrument.
    static let rSmall: CGFloat = 2
    static let r: CGFloat = 4

    // MARK: Type. SF Pro for UI, SF Mono for every number.
    static func display(_ size: CGFloat = 32) -> Font {
        .system(size: size, weight: .bold, design: .default)
    }
    static func heading(_ size: CGFloat = 19) -> Font {
        .system(size: size, weight: .semibold, design: .default)
    }
    static func body(_ size: CGFloat = 15) -> Font {
        .system(size: size, weight: .regular, design: .default)
    }
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
            .font(Theme.mono(10, weight: .medium))
            .tracking(1.4)
            .foregroundStyle(color)
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

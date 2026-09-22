import SwiftUI

/// The Spotter identity, ported to SwiftUI.
/// Dark-first: the hero surface is always footage of a climber in a dim gym.
enum Theme {

    // MARK: Ground and surfaces
    static let ground   = Color(hex: 0x0E1110)   // near-black with a green cast
    static let surface  = Color(hex: 0x171B19)
    static let surface2 = Color(hex: 0x212724)
    static let line     = Color(hex: 0x2C3330)
    static let lineStrong = Color(hex: 0x454E4A)

    // MARK: Ink
    static let ink   = Color(hex: 0xEDEBE4)      // warm off-white, never pure white
    static let ink2  = Color(hex: 0xA3A79F)
    static let ink3  = Color(hex: 0x6E736C)

    // MARK: Accent. Spent on the centre-of-mass trace and almost nowhere else.
    static let accent     = Color(hex: 0xFF6B2C)
    static let accentText = Color(hex: 0xFF8347)
    static let accentWash = Color(hex: 0xFF6B2C).opacity(0.13)

    static let ok = Color(hex: 0x7CC98A)

    /// Ember ramp. Leak severity is magnitude, so it gets a ramp and not a traffic light.
    static let ember: [Color] = [
        Color(hex: 0xFFD9C2), Color(hex: 0xFFB183), Color(hex: 0xFF8A4C),
        Color(hex: 0xFF6B2C), Color(hex: 0xC64414)
    ]

    /// Skeleton overlay colour. Chalk, so it never competes with the accent.
    static let chalk = Color(hex: 0xF4F3EE)

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

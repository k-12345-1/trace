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
    static let surface  = Color(hex: 0xF4F7FA)
    static let surface2 = Color(hex: 0xE7EDF4)
    static let line     = Color(hex: 0xE1E8F0)
    static let lineStrong = Color(hex: 0xC3D0DE)

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

    // MARK: Radius. Low radius reads as instrument.
    static let rSmall: CGFloat = 2
    static let r: CGFloat = 4

    // MARK: Type.
    //
    // Inter for the interface, matching KAYA. Numbers stay monospaced: Inter has
    // no mono cut, and every readout in this app depends on tabular digits lining
    // up, so SF Mono keeps that job.
    static func ui(_ size: CGFloat, _ weight: Font.Weight) -> Font {
        if let name = Fonts.name(for: weight) {
            return .custom(name, size: size)
        }
        return .system(size: size, weight: weight, design: .default)
    }

    static func display(_ size: CGFloat = 32) -> Font { ui(size, .bold) }
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

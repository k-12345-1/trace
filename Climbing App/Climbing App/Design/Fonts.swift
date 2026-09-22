import SwiftUI
import CoreText

/// Inter, bundled and registered at launch.
///
/// Registering at runtime rather than through UIAppFonts keeps the font list in
/// one place in code, next to the type scale that uses it.
enum Fonts {
    static let family = "Inter"

    private static let faces = [
        "Inter-Regular", "Inter-Medium", "Inter-SemiBold", "Inter-Bold"
    ]

    /// True once the bundled faces are available to Core Text.
    private(set) static var isRegistered = false

    static func register() {
        guard !isRegistered else { return }
        var loaded = 0
        for face in faces {
            guard let url = Bundle.main.url(forResource: face, withExtension: "ttf") else { continue }
            var error: Unmanaged<CFError>?
            if CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
                loaded += 1
            } else if let code = error?.takeUnretainedValue(),
                      CFErrorGetCode(code) == CTFontManagerError.alreadyRegistered.rawValue {
                loaded += 1
            }
        }
        isRegistered = loaded == faces.count
    }

    /// The PostScript name for a weight, or nil when Inter is unavailable and the
    /// system face should be used instead.
    static func name(for weight: Font.Weight) -> String? {
        guard isRegistered else { return nil }
        switch weight {
        case .bold, .heavy, .black: return "Inter-Bold"
        case .semibold:             return "Inter-SemiBold"
        case .medium:               return "Inter-Medium"
        default:                    return "Inter-Regular"
        }
    }
}

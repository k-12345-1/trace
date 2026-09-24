import Foundation

/// Your height and your reach.
///
/// A phone cannot know how far away you are, which is why every distance Trace
/// reports is in body lengths by default: a real number that survives the camera
/// being moved. Give it your height and it gains a scale, so the same numbers can
/// be said in metres. Give it your span and the balance envelope becomes your
/// envelope rather than a proportion borrowed from the average climber.
///
/// Stored in centimetres whichever units you type in, because the arithmetic
/// should not care what the keyboard said.
struct BodyProfile: Codable, Equatable {
    var heightCM: Double?
    var spanCM: Double?
    /// Body mass in kilogrammes, whatever units you typed.
    ///
    /// It does not move your centre of mass. Where the COM sits is a weighted
    /// average of segment positions, and Dempster's fractions are fractions, so
    /// they cancel: a 60 kg and a 90 kg climber in the same pose have the COM in
    /// the same place. What mass buys is the step after that. Once Trace knows
    /// how far the COM moved in metres, mass turns that path into joules, and
    /// the lifting you paid for stops being a ratio and becomes an amount.
    var massKG: Double?
    /// Feet and inches, purely for display. It never touches the maths.
    var usesImperial: Bool = Locale.current.measurementSystem != .metric

    static let empty = BodyProfile()

    var isEmpty: Bool { heightCM == nil && spanCM == nil && massKG == nil }
    var hasScale: Bool { (heightCM ?? 0) > 0 }
    /// Work in joules needs both: metres from the height, kilogrammes from the mass.
    var canWeighWork: Bool { hasScale && (massKG ?? 0) > 0 }

    /// Span minus height, the number climbers actually quote. Positive is a
    /// longer reach than your height, which is the one people call a plus ape.
    var apeIndexCM: Double? {
        guard let h = heightCM, let s = spanCM, h > 0, s > 0 else { return nil }
        return s - h
    }

    var apeIndexLabel: String? {
        guard let ape = apeIndexCM else { return nil }
        let rounded = (ape * 10).rounded() / 10
        if usesImperial {
            let inches = (rounded / 2.54 * 10).rounded() / 10
            return String(format: "%@%.1f in", inches >= 0 ? "+" : "", inches)
        }
        return String(format: "%@%.0f cm", rounded >= 0 ? "+" : "", rounded)
    }

    // MARK: Plausibility
    //
    // Not validation for its own sake. A mistyped height silently rescales every
    // distance in the app, so it is worth refusing the obviously impossible.

    static let heightRangeCM = 90.0...240.0
    static let spanRangeCM = 90.0...260.0
    static let massRangeKG = 25.0...200.0

    static func plausibleHeight(_ cm: Double) -> Bool { heightRangeCM.contains(cm) }
    static func plausibleSpan(_ cm: Double) -> Bool { spanRangeCM.contains(cm) }
    static func plausibleMass(_ kg: Double) -> Bool { massRangeKG.contains(kg) }

    // MARK: Unit conversion

    static let poundsPerKG = 2.2046226218

    static func kg(pounds: Double) -> Double { pounds / poundsPerKG }

    static func cm(feet: Int, inches: Double) -> Double {
        (Double(feet) * 12 + inches) * 2.54
    }

    /// Whole feet and the remaining inches, rounded to a half.
    static func feetInches(fromCM cm: Double) -> (feet: Int, inches: Double) {
        let totalInches = cm / 2.54
        var feet = Int(totalInches / 12)
        var inches = (totalInches - Double(feet) * 12)
        inches = (inches * 2).rounded() / 2
        if inches >= 12 { feet += 1; inches -= 12 }
        return (feet, inches)
    }

    /// How a stored measurement should read back on screen.
    func describe(_ cm: Double?) -> String {
        guard let cm, cm > 0 else { return "Not set" }
        if usesImperial {
            let (f, i) = Self.feetInches(fromCM: cm)
            return i == i.rounded()
                ? "\(f)′ \(Int(i))″"
                : String(format: "%d′ %.1f″", f, i)
        }
        return String(format: "%.0f cm", cm)
    }

    /// How a stored mass should read back on screen.
    func describeMass(_ kg: Double?) -> String {
        guard let kg, kg > 0 else { return "Not set" }
        if usesImperial { return String(format: "%.0f lb", kg * Self.poundsPerKG) }
        return String(format: "%.0f kg", kg)
    }
}

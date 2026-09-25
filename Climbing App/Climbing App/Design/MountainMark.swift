import SwiftUI

/// Trace's mark: the climber with her skeleton drawn over her.
///
/// It is artwork, not a drawing this file makes. The file in the asset catalog
/// is the source of truth, and `tools/MakeLogoAssets.swift` cuts the icon and
/// this mark out of it by measuring the ink rather than by hand, so a new
/// version of the artwork can be dropped in and the tool rerun.
///
/// The name is kept from the mark this replaced. Renaming it would touch every
/// screen for no gain, and what it means has not changed: this is the mark.
struct MountainMark: View {
    /// Fraction of the frame left empty around the mark.
    var inset: Double = 0.06

    var body: some View {
        GeometryReader { geo in
            Image("TraceMark")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .padding(min(geo.size.width, geo.size.height) * inset)
                .frame(width: geo.size.width, height: geo.size.height)
        }
        .accessibilityHidden(true)
    }
}

/// The name, as it was drawn.
///
/// Home used to set it in the system serif beside the mark, which put the same
/// word in two different letterforms six points apart. Nobody would name that
/// as the problem, and everybody would feel it: the masthead read as a logo
/// with a caption rather than as one thing.
struct TraceWordmark: View {
    /// The artwork's own proportions, measured off the cut file rather than
    /// guessed, so a height is all a caller ever has to give.
    static let ratio: CGFloat = 692.0 / 198.0

    var height: CGFloat = 26

    var body: some View {
        Image("TraceWordmark")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: height * Self.ratio, height: height)
            .accessibilityLabel("Trace")
    }
}

/// The mark over the wordmark, as it was drawn: one piece of artwork rather
/// than a picture with type set under it.
struct TraceLockup: View {
    var body: some View {
        Image("TraceLockup")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .accessibilityLabel("Trace")
    }
}

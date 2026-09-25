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

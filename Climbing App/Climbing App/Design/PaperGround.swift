import SwiftUI

/// The page: the logo's paper, with the logo's grain on it.
///
/// The tile is a square cut from the artwork's own clean margin and mirrored so
/// it repeats without a seam, which means the texture under the app is
/// literally the texture the mark was printed on rather than a noise function
/// that resembles it.
///
/// It is held at a low opacity on purpose. Paper is meant to be noticed the way
/// paper is noticed, which is not at all until you look for it; a grain you can
/// see from arm's length is a background image, and a background image behind
/// small text is a legibility problem rather than a texture.
struct PaperGround: View {
    /// It takes taps, the way the plain color it replaced did. It is always the
    /// bottom layer, so a tap that reaches it is a tap on empty page, and the
    /// add panel's scrim relies on exactly that to close itself.
    var body: some View {
        Theme.ground
            .overlay {
                Image("PaperGrain")
                    .resizable(resizingMode: .tile)
                    .opacity(0.55)
                    .blendMode(.multiply)
            }
            .ignoresSafeArea()
    }
}

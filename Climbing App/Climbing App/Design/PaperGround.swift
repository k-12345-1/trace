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

/// The same paper, for a header that has to be opaque over scrolling text.
///
/// A pinned header needs to hide the paragraphs passing under it, so it cannot
/// be clear, and filling it with the flat ground color leaves a visible panel
/// of smooth paper against the grained page below it. This is the page's own
/// surface, tiled from the same origin, so the seam disappears.
struct PaperBand: View {
    var body: some View {
        Theme.ground
            .overlay {
                Image("PaperGrain")
                    .resizable(resizingMode: .tile)
                    .opacity(0.55)
                    .blendMode(.multiply)
            }
            // Flattened before it meets the page. Laid over the grained page
            // without this, the multiply reaches through to the grain below
            // and the band comes out a shade darker than the paper it is
            // meant to be part of, which is the tan strip at the top of every
            // screen. The page's own ground has nothing under it but the
            // window, so it never showed the fault.
            .compositingGroup()
            .ignoresSafeArea(edges: .top)
    }
}


/// The page fading out as it passes under the clock.
///
/// This replaced a band of paper painted over the top of the page. The band
/// was the page's own ground and grain, drawn again, and on the phone it came
/// out a shade darker than the page beneath it, which is the tan strip at the
/// top of every screen. Two drawings of the same paper can disagree; one
/// cannot. So nothing is painted: the content itself is masked to fade over
/// fourteen points as it reaches the status bar, and what shows through is the
/// one ground the whole app sits on.
///
/// `amount` scales the fade from nothing (0) to the full height (1), for a
/// screen that wants the fade to arrive as something scrolls away.
struct FadesUnderTheTop: ViewModifier {
    var amount: Double = 1

    func body(content: Content) -> some View {
        content.mask {
            GeometryReader { geo in
                VStack(spacing: 0) {
                    Color.clear.frame(height: max(0, (geo.safeAreaInsets.top + 3) * amount))
                    LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                        .frame(height: 14 * amount)
                    Color.black
                }
                .ignoresSafeArea()
            }
        }
    }
}

extension View {
    func fadesUnderTheTop(_ amount: Double = 1) -> some View {
        modifier(FadesUnderTheTop(amount: amount))
    }
}

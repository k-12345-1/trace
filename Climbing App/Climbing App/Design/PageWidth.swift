import SwiftUI

extension View {

    /// Pins a scrolling page to the width of the scroll view holding it.
    ///
    /// A vertical `ScrollView` does not clip a child wider than itself. It
    /// scrolls to it: the content becomes as wide as its widest part, and the
    /// whole page then slides left and right under a thumb, over a strip of
    /// bare paper, on a screen that has no sideways to go to. It is a defect
    /// you can only feel, which is what makes it hard to find. One view
    /// somewhere in a long page taking its natural width instead of the one it
    /// was offered is enough, and any edit can introduce it.
    ///
    /// This closes the whole class of it. The content is given the container's
    /// width rather than allowed to ask for its own, so there is nowhere to
    /// scroll to. Anything too wide inside still draws wrong, which is a bug
    /// that shows in a screenshot, rather than dragging, which is one that does
    /// not.
    ///
    /// Goes on the content of a vertical scroll view, not on the scroll view:
    /// pinning the scroll view leaves its content free to outgrow it, which is
    /// the same drag with an extra step.
    func holdsThePageWidth() -> some View {
        containerRelativeFrame(.horizontal)
    }
}

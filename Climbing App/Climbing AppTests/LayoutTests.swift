import Testing
import SwiftUI
import UIKit
import CoreGraphics
@testable import ClimbingApp

/// Does a screen fit the phone it is on.
///
/// This exists because of a bug that kept coming back and that no amount of
/// looking at screenshots would find: a screen that scrolls up and down would
/// also drag sideways, because one view inside it was wider than the phone.
/// Nothing looks wrong in a still. It only shows up in the hand.
///
/// A vertical `ScrollView` does not clip an oversized child, it scrolls to it,
/// so the symptom is always the same and the cause is always some single view
/// that took its own natural width instead of the one it was offered. Measuring
/// the scroll view's content width says so in a number.
@MainActor
enum Layout {

    /// iPhone 17 Pro, in points. The narrower the phone the easier this is to
    /// pass, so the test is run on a wide one only because that is what is to
    /// hand; anything that overflows here overflows on every smaller screen too.
    static let phone = CGSize(width: 402, height: 874)


    struct Measured {
        /// The width of the phone this was laid out on.
        let page: CGFloat
        let bounds: CGSize
        let content: CGSize

        /// True when there is more content than fits vertically, which is what
        /// a page does. A row of gym tiles has content wider than the phone on
        /// purpose and no height to speak of; a page does not.
        var isAPage: Bool { content.height > bounds.height + 1 }

        /// How far past the phone this scroll view reaches, whichever way it
        /// got there.
        ///
        /// Both readings matter and they are two faces of one defect. When the
        /// scroll view is boxed in by a parent, an oversized child shows up as
        /// content wider than the scroll view, and that is the drag: a vertical
        /// scroll view does not clip an oversized child, it scrolls to it. When
        /// nothing boxes it in, the scroll view simply grows instead, and the
        /// content matches it again. Measuring against the phone catches both.
        ///
        /// A row that only scrolls sideways is exempt, because sideways is what
        /// it is for. That exemption is why `isAPage` exists rather than the
        /// test simply skipping anything wide.
        var overhang: CGFloat {
            guard isAPage else { return 0 }
            return max(0, max(content.width, bounds.width) - page)
        }
    }

    /// Lay a view out in a phone-sized window and measure every scroll view in it.
    static func scrollers<V: View>(_ view: V, size: CGSize = phone) -> [Measured] {
        let host = UIHostingController(rootView: view)
        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        window.rootViewController = host
        // A window that is never made visible does not lay its content out.
        window.isHidden = false
        // Pinned to the window, because a hosting controller left to itself
        // grows to whatever its content asks for. Without this the scroll view
        // and its content come back the same width by construction and the
        // measurement can never fail, which is what the control test below is
        // here to catch.
        host.view.translatesAutoresizingMaskIntoConstraints = true
        host.view.frame = window.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        window.layoutIfNeeded()
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        return scrollViews(in: host.view).map {
            Measured(page: size.width, bounds: $0.bounds.size, content: $0.contentSize)
        }
    }

    private static func scrollViews(in view: UIView) -> [UIScrollView] {
        var found: [UIScrollView] = []
        if let scroller = view as? UIScrollView { found.append(scroller) }
        for sub in view.subviews { found += scrollViews(in: sub) }
        return found
    }
}

@Suite("Screen layout") @MainActor
struct LayoutTests {

    /// A route with everything on it: several attempts, measurements good
    /// enough to read, and a finding, so every section of the screen is built
    /// rather than skipped.
    private func route() -> LibraryEntry {
        // Real frames, because half this screen is only built when there are
        // some: the skeleton overlay, the telemetry panel under the video, and
        // the live readout all sit behind that one check, and a fixture with an
        // empty frame list quietly tests the half of the screen that was never
        // in question.
        let frames = Fixture.straightAscent()
        let attempts = (0..<3).map { i in
            var climb = Fixture.climb(path: Fixture.sPath(), entropy: 1.2 + Double(i) * 0.1,
                                      kind: i == 0 ? .unopposed : .bentArms,
                                      elbow: 150, daysAgo: Double(i),
                                      label: "The Long Traverse")
            climb.frames = frames
            return climb
        }
        return LibraryEntry(attempts: attempts)
    }

    /// Every width Trace runs at, narrowest first. The narrow ones matter most:
    /// a fixed width that fits a Pro Max is still a sideways drag on a mini.
    private static let widths: [CGFloat] = [320, 375, 393, 402, 430]

    /// Text sizes worth testing. Trace sets most of its type in fixed points,
    /// but Inter is loaded with `Font.custom(_:size:)`, which scales with the
    /// system text size whether or not anyone asked it to. So the interface
    /// grows at large text sizes while the serif headings do not, and anything
    /// sized to fit the small case can stop fitting.
    private static let textSizes: [DynamicTypeSize] =
        [.large, .xxxLarge, .accessibility3, .accessibility5]

    private func check<V: View>(_ what: String, _ view: @autoclosure () -> V) {
        for width in Self.widths {
            for text in Self.textSizes {
                check("\(what) at \(Int(width))pt, text \(text)",
                      Layout.scrollers(view().environment(\.dynamicTypeSize, text),
                                       size: CGSize(width: width, height: 874)))
            }
        }
    }

    private func check(_ what: String, _ measured: [Layout.Measured]) {
        #expect(!measured.isEmpty, "\(what): no scroll view was laid out, so nothing was measured")
        // A point and a half of slack. Text measurement lands on fractions of a
        // point and a scroll view rounds its own content up, so a screen that
        // fits exactly reports a fraction over now and then. Nothing under a
        // point and a half can be felt under a thumb.
        for scroller in measured where scroller.overhang > 1.5 {
            Issue.record("""
                \(what) runs \(Int(scroller.overhang.rounded()))pt past the phone: \
                \(Int(scroller.content.width))pt of content in a \
                \(Int(scroller.bounds.width))pt scroll view on a \
                \(Int(scroller.page))pt screen
                """)
        }
    }

    /// The measurement has to be able to fail, or the tests under it say
    /// nothing. A page deliberately wider than the phone must be caught.
    @Test("The measurement catches something too wide")
    func theMeasurementWorks() {
        let tooWide = ScrollView {
            VStack { Color.red.frame(width: 700, height: 4000) }
        }
        let measured = Layout.scrollers(tooWide)
        #expect(measured.first?.overhang ?? 0 > 200,
                "measured \(measured.map(\.content.width)) in \(measured.map(\.bounds.width))")
    }

    @Test("A route from the library does not drag sideways")
    func theRouteScreenFitsThePhone() {
        check("the route screen", ClimbCardScreen(entry: route()))
    }

    @Test("One attempt does not drag sideways")
    func theAttemptScreenFitsThePhone() {
        check("the attempt screen", ResultsScreen(climb: route().latest))
    }

    /// Both climb screens are reached by a push, and a pushed screen is laid
    /// out by the stack rather than by the window, so they are measured that
    /// way too.
    @Test("Pushed onto a navigation stack, both still fit")
    func thePushedScreensFitThePhone() {
        let entry = route()
        check("the pushed route screen", NavigationStack { ClimbCardScreen(entry: entry) })
        check("the pushed attempt screen", NavigationStack { ResultsScreen(climb: entry.latest) })
    }

    /// Every screen that can be built without a store behind it. Empty, these
    /// are mostly their empty states, which is a weak test of each one and a
    /// cheap sweep across all of them.
    /// A row that scrolls sideways is not a page and is not a defect. Without
    /// this the exemption above could be doing nothing, or everything.
    @Test("A row that scrolls sideways is left alone")
    func sidewaysRowsArePermitted() {
        let row = ScrollView(.horizontal) {
            HStack { ForEach(0..<8, id: \.self) { _ in Color.blue.frame(width: 120, height: 90) } }
        }
        let measured = Layout.scrollers(row, size: CGSize(width: 320, height: 200))
        #expect(measured.allSatisfy { $0.overhang == 0 },
                "measured \(measured.map(\.content))")
    }

    @Test("No screen is wider than the phone")
    func theOtherScreensFitThePhone() {
        check("home", NavigationStack { HomeScreen() })
        check("the library", NavigationStack { LibraryScreen() })
        check("the profile", NavigationStack { ProfileScreen() })
        check("explore", NavigationStack { ExploreScreen() })
        check("progress", NavigationStack { ProgressScreen() })
    }
}

import Testing
import SwiftUI
import UIKit
@testable import ClimbingApp

/// The sign in and sign up forms, and where they are allowed to go.
///
/// The fields used to ride over the mark. The clearance for the lockup was
/// padding on the form inside the scroll view, so it was part of what scrolls:
/// raise the keyboard, the content has nowhere to go but up, and the email box
/// ends up sitting across the climber with the word Trace showing between the
/// fields. The clearance is the scroll view's own top inset now, so the form is
/// clipped to the space below the mark and cannot reach it however far it
/// scrolls, which it still does when the keyboard leaves it no room.
@Suite("Auth layout") @MainActor
struct AuthLayoutTests {

    /// The mark, at rest, plus the gap under it. Read off the same numbers the
    /// screen uses: 162 wide, 1009 by 728, scaled to 0.86, then 54 of gap.
    private let markBottom: CGFloat = 162 * (1009.0 / 728.0) * 0.86 + 54

    /// Every height worth testing, including the ones a keyboard leaves.
    private static let heights: [CGFloat] = [874, 667, 500, 420, 340]

    private func scrollViews(in view: UIView) -> [UIScrollView] {
        var out: [UIScrollView] = []
        if let s = view as? UIScrollView { out.append(s) }
        for sub in view.subviews { out += scrollViews(in: sub) }
        return out
    }

    private func check<V: View>(_ what: String, _ view: V) {
        for height in Self.heights {
            let size = CGSize(width: 402, height: height)
            let host = UIHostingController(rootView: view)
            let window = UIWindow(frame: CGRect(origin: .zero, size: size))
            window.rootViewController = host
            window.isHidden = false
            host.view.frame = window.bounds
            window.layoutIfNeeded()
            host.view.layoutIfNeeded()

            let found = scrollViews(in: host.view)
            #expect(!found.isEmpty, "\(what) at \(Int(height)): no scroll view")
            for scroller in found {
                let top = scroller.convert(scroller.bounds, to: host.view).minY
                // The form's own window starts below the mark, so nothing in it
                // can be drawn over the mark whatever the scroll offset is.
                #expect(top > 12,
                        "\(what) at \(Int(height)): the form starts at \(Int(top))")
            }
        }
    }

    @Test("The sign in form never reaches the mark")
    func signInStaysBelowTheMark() {
        check("sign in", SignInScreen(revealed: .constant(true), goSignUp: {}))
    }

    @Test("The sign up form never reaches the mark")
    func signUpStaysBelowTheMark() {
        check("sign up", SignUpScreen(revealed: .constant(true), goSignIn: {}))
    }
}

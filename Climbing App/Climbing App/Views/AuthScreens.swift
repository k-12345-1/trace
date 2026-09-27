import SwiftUI

/// Signing in and signing up, built on the Lineage Health pattern.
///
/// Two screens rather than one with a toggle. Sign in leads, sign up is one tap
/// away, and both are laid out identically: the mark starts centered at full
/// size, lifts to a fixed spot near the top after a beat, and the form fades in
/// underneath it. Because both screens settle the mark in the same place, moving
/// between them does not move the logo, which is the whole point of doing it
/// this way rather than pushing a different screen.
///
/// There is no way past this screen without an account. Trace still keeps every
/// measurement on the device; the account is identity, and now it is required.

// MARK: - Shared shell

/// The splash geometry. Everything on either screen sits in this frame.
/// The lockup's drawn size on the auth screens, and the gap under it.
///
/// Its own type because `AuthShell` is generic and a generic type may not hold
/// stored statics. The artwork is 728 by 1009, so at 162 wide it stands 224.5
/// tall, and the 0.86 it settles to after the reveal makes that 193. Written
/// out rather than measured, because the layout has to know it before the view
/// is drawn.
private enum Lockup {
    static let width: CGFloat = 162
    static let rest: CGFloat = 0.86
    static var full: CGFloat { width * (1009.0 / 728.0) }
    static var height: CGFloat { full * rest }
    static let gapBelow: CGFloat = 54

    /// How far down to nudge the centered stack so the **ink** is centered.
    ///
    /// The form's measured height runs a little past its last line of text, so
    /// centering the frames leaves that invisible slack as extra white below
    /// the visible bottom, and the artwork's top edge is a thin wisp of wall so
    /// the ink starts a little after the frame does. Both push the same way.
    ///
    /// Tuned against screenshots rather than derived: the stack moves point for
    /// point with this, and twelve is where the white above and below the ink
    /// came out equal.
    static let opticalShift: CGFloat = 12
}

private struct AuthShell<Content: View>: View {
    @Binding var revealed: Bool
    @ViewBuilder var content: Content

    /// How tall the form turned out to be, so the whole stack can be centered.
    @State private var formHeight: CGFloat = 0

    /// Where the stack starts, with the leftover split evenly above and below.
    ///
    /// It used to be two fixed numbers, which put the lockup under the status
    /// bar with three hundred points of nothing beneath the form. Centering it
    /// needs the form's height, and the form's height depends on which of the
    /// two screens is in it, so it is measured rather than guessed.
    private func stackTop(_ geo: GeometryProxy) -> CGFloat {
        let stack = Lockup.height + Lockup.gapBelow + formHeight
        let free = geo.size.height - stack
        // The safe areas are white too.
        //
        // `geo` measures the space between the status bar and the home
        // indicator, so splitting `free` in half evens out the layout and not
        // the page: the status bar's sixty points sit above the result and the
        // home indicator's thirty below it, leaving the stack visibly high.
        // Carrying the difference here balances what is actually seen.
        let lean = (geo.safeAreaInsets.bottom - geo.safeAreaInsets.top) / 2
        return max(12, free / 2 + lean + Lockup.opticalShift)
    }

    var body: some View {
        GeometryReader { geo in
            let top = stackTop(geo)
            ZStack(alignment: .top) {
                PaperGround()

                LogoLockup()
                    .scaleEffect(revealed ? Lockup.rest : 1, anchor: .top)
                    .position(x: geo.size.width / 2,
                              y: revealed
                                 ? top + Lockup.full / 2
                                 : geo.size.height / 2)
                    .allowsHitTesting(false)

                // A ScrollView, but one that only scrolls when it has to.
                //
                // The form is shorter than the screen, so on a normal phone it
                // never scrolls: dragging the email and password fields around
                // was the scroll view bouncing against its own limits, which
                // reads as the page coming loose. `basedOnSize` stops the bounce
                // until the content genuinely overflows, which is the keyboard
                // on a small screen, and then scrolling is what you want.
                // The clearance for the mark is the scroll view's own top
                // inset, not padding on the form inside it.
                //
                // As padding on the content it was part of what scrolls, so
                // raising the keyboard slid the fields up over the lockup and
                // the word Trace came through between them. As an inset on the
                // scroll view, the form is clipped to the space below the mark
                // and cannot reach it however far it scrolls, which it still
                // does when the keyboard leaves it no room.
                ScrollView {
                    content
                        .frame(width: min(320, geo.size.width - 44))
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                            formHeight = $0
                        }
                        .padding(.bottom, 40)
                        .frame(maxWidth: .infinity)
                }
                .padding(.top, top + Lockup.height + Lockup.gapBelow)
                .scrollBounceBehavior(.basedOnSize)
                .scrollDismissesKeyboard(.interactively)
                .scrollIndicators(.hidden)
                .opacity(revealed ? 1 : 0)
                .offset(y: revealed ? 0 : 12)
                .allowsHitTesting(revealed)
            }
        }
        .preferredColorScheme(.light)
        .onAppear {
            guard !revealed else { return }
            // The mark holds the screen on its own for a beat before the form
            // arrives under it. Long enough to read as an opening rather than
            // a slow load, short enough that it is not in the way.
            withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.9).delay(1.5)) {
                revealed = true
            }
        }
    }
}

/// The mark over the wordmark, centered. This is what animates.
private struct LogoLockup: View {
    var body: some View {
        // The mark and the word are one piece of artwork, so they are drawn
        // together rather than assembled out of a picture and a typeface that
        // is not the one the word was set in.
        TraceLockup()
            .frame(width: Lockup.width)
    }
}

// MARK: - Pieces shared by both forms

private struct AuthField: View {
    let label: String
    @Binding var text: String
    var placeholder: String
    var keyboard: UIKeyboardType = .default
    var secure: Bool = false
    var contentType: UITextContentType?
    var focused: Bool
    var onSubmit: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label)
                .font(Theme.ui(13.5, .semibold))
                .foregroundStyle(Theme.ink2)
            Group {
                if secure {
                    SecureField("", text: $text,
                                prompt: Text(placeholder).foregroundStyle(Theme.ink3))
                } else {
                    TextField("", text: $text,
                              prompt: Text(placeholder).foregroundStyle(Theme.ink3))
                }
            }
            .font(Theme.ui(16))
            .foregroundStyle(Theme.ink)
            .keyboardType(keyboard)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .textContentType(contentType)
            .padding(.horizontal, 16).padding(.vertical, 14)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.r, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.r, style: .continuous)
                .stroke(focused ? Theme.accent : .clear, lineWidth: 1.5))
            .onSubmit(onSubmit)
        }
    }
}

/// The primary pill: dimmed until the form is fillable, like the reference's
/// Continue button, which stays inert until a choice has been made.
private struct AuthButton: View {
    let title: String
    let busyTitle: String
    let busy: Bool
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(busy ? busyTitle : title)
                .font(Theme.ui(15.5, .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(enabled ? Theme.button : Theme.button.opacity(0.3))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!enabled || busy)
    }
}

/// "New to Trace? Sign up →", set the way the reference sets it: the question in
/// muted ink, the action in the accent.
private struct CrossLink: View {
    let question: String
    let action: String
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 5) {
                Text(question)
                    .font(Theme.ui(13.5))
                    .foregroundStyle(Theme.ink3)
                Text(action)
                    .font(Theme.ui(13.5, .semibold))
                    .foregroundStyle(Theme.accentText)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// A message about the attempt, faded in rather than snapped in.
///
/// It sits below the button that produced it, so nothing above it ever moves.
private struct AuthMessageSlot: View {
    let error: String?
    let notice: String?

    var body: some View {
        ZStack {
            if let error {
                AuthMessage(text: error, isError: true)
            } else if let notice {
                AuthMessage(text: notice, isError: false)
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .animation(.easeInOut(duration: 0.18), value: error)
        .animation(.easeInOut(duration: 0.18), value: notice)
    }
}


/// A way in that needs nobody's permission.
///
/// An account in Trace is identity and nothing else. No climb, clip, route or
/// measurement is ever stored on a server, so signing in unlocks no feature and
/// signing out loses nothing. Apple's 5.1.1(i) says an app may not require
/// registration unless account-based features are core to it, and by that test
/// Trace's are not: they are a name on a phone.
///
/// It is also the difference between a reviewer getting into the app and not.
/// Sign-up on this project waits for a confirmation email, and an app whose
/// front door depends on a message arriving is an app that fails review on the
/// day the mail is slow.
private struct SkipAccount: View {
    @ObservedObject private var store = Store.shared
    @State private var naming = false
    @State private var name = ""

    var body: some View {
        Button { naming = true } label: {
            Text("Use Trace without an account")
                .font(Theme.ui(13.5, .semibold))
                .foregroundStyle(Theme.ink3)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .alert("What should Trace call you?", isPresented: $naming) {
            TextField("Name", text: $name)
            Button("Start climbing") { store.continueLocally(name: name) }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Everything stays on this phone either way. An account only puts a name to it.")
        }
    }
}

/// Agreeing to something you cannot read is not agreeing. Both documents open
/// from here, before the account exists.
private struct LegalFooter: View {
    @State private var showing: Document?

    private enum Document: String, Identifiable {
        case terms, privacy
        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 5) {
            // Legible, not fine print. This line is the only notice a person
            // gets that they are agreeing to something, so setting it at the
            // smallest size in the app would be the one piece of type where
            // being hard to read is a convenience to us.
            Text("By continuing you agree to our")
                .font(Theme.ui(13))
                .foregroundStyle(Theme.ink2)
            HStack(spacing: 5) {
                link("Terms", .terms)
                Text("and").font(Theme.ui(13)).foregroundStyle(Theme.ink2)
                link("Privacy Policy", .privacy)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 12)
        // Full screen rather than a sheet. A document you are being asked to
        // agree to should not arrive as a card with the form still showing
        // behind it.
        .fullScreenCover(item: $showing) { which in
            which == .terms ? LegalScreen.terms(insideApp: false)
                            : LegalScreen.privacy(insideApp: false)
        }
    }

    private func link(_ title: String, _ which: Document) -> some View {
        Button { showing = which } label: {
            Text(title)
                .font(Theme.ui(13, .semibold))
                .foregroundStyle(Theme.accentText)
                .underline()
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// With no red in the palette, a problem cannot be signalled by coloring the
/// sentence. It gets an icon and a panel instead, which is a stronger signal
/// anyway: it changes the shape of the screen rather than a few pixels of hue.
private struct AuthMessage: View {
    let text: String
    var isError: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(isError ? Theme.blue : Theme.blueLight)
            Text(text)
                .font(Theme.ui(13))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isError ? Theme.surface2 : Theme.accentWash)
        .clipShape(RoundedRectangle(cornerRadius: Theme.r, style: .continuous))
    }
}

// MARK: - Sign in

/// The screen the app opens on. Sign in leads because most launches are a
/// returning climber, not a new one.
struct SignInScreen: View {
    @ObservedObject private var store = Store.shared
    @Binding var revealed: Bool
    let goSignUp: () -> Void

    @State private var email = ""
    @State private var password = ""
    @State private var busy = false
    @State private var error: String?
    @State private var notice: String?
    @FocusState private var focus: Field?

    private enum Field { case email, password }

    private var canSubmit: Bool {
        !email.trimmingCharacters(in: .whitespaces).isEmpty && !password.isEmpty && !busy
    }

    var body: some View {
        AuthShell(revealed: $revealed) {
            VStack(spacing: 14) {
                AuthField(label: "Email", text: $email, placeholder: "you@email.com",
                          keyboard: .emailAddress, contentType: .emailAddress,
                          focused: focus == .email)
                    .focused($focus, equals: .email)

                AuthField(label: "Password", text: $password, placeholder: "Your password",
                          secure: true, contentType: .password,
                          focused: focus == .password, onSubmit: submit)
                    .focused($focus, equals: .password)

                AuthButton(title: "Sign in", busyTitle: "Signing you in…",
                           busy: busy, enabled: canSubmit, action: submit)
                    .padding(.top, 4)

                // Under the button rather than over it. A message that appears
                // above the control you just pressed pushes that control out
                // from under your finger, which is the lurch on the way in.
                AuthMessageSlot(error: error, notice: notice)

                Button { resetPassword() } label: {
                    Text("Forgot password?")
                        .font(Theme.ui(13, .semibold))
                        .foregroundStyle(Theme.ink3)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(busy)

                CrossLink(question: "New to Trace?", action: "Sign up →", onTap: goSignUp)

                SkipAccount()

                LegalFooter()
            }
        }
    }

    private func submit() {
        guard canSubmit else { return }
        focus = nil
        busy = true; error = nil; notice = nil

        // The demo pair, in development builds only.
        //
        // It existed because the app was unreachable without it. `LocalStartScreen`
        // is that way in now, and this screen only appears once there is a real
        // server to answer to, so in a shipped build a credential pair that signs
        // itself in would be a back door around that server rather than a way
        // past a missing one.
        #if DEBUG
        if DemoAccount.matches(email: email, password: password) {
            store.signedInAsDemo()
            busy = false
            return
        }
        #endif

        Task {
            do {
                let session = try await AuthClient.signIn(email: email, password: password)
                store.signedIn(session: session)
            } catch let e as AuthClient.AuthError {
                error = e.errorDescription
            } catch {
                self.error = error.localizedDescription
            }
            busy = false
        }
    }

    private func resetPassword() {
        guard AuthClient.validateEmail(email) else {
            error = AuthClient.AuthError.invalidEmail.errorDescription
            return
        }
        busy = true; error = nil; notice = nil
        Task {
            do {
                try await AuthClient.sendPasswordReset(email: email)
                notice = "If that email has an account, a reset link is on its way."
            } catch let e as AuthClient.AuthError {
                error = e.errorDescription
            } catch {
                self.error = error.localizedDescription
            }
            busy = false
        }
    }
}

// MARK: - Sign up

struct SignUpScreen: View {
    @ObservedObject private var store = Store.shared
    @Binding var revealed: Bool
    let goSignIn: () -> Void

    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var busy = false
    @State private var error: String?
    @FocusState private var focus: Field?

    private enum Field { case name, email, password }

    private var canSubmit: Bool {
        AuthClient.validateEmail(email) && AuthClient.validatePassword(password) && !busy
    }

    var body: some View {
        AuthShell(revealed: $revealed) {
            VStack(spacing: 14) {
                AuthField(label: "Name", text: $name,
                          placeholder: "Name", contentType: .name,
                          focused: focus == .name)
                    .focused($focus, equals: .name)
                    .textInputAutocapitalization(.words)

                AuthField(label: "Email", text: $email, placeholder: "you@email.com",
                          keyboard: .emailAddress, contentType: .emailAddress,
                          focused: focus == .email)
                    .focused($focus, equals: .email)

                AuthField(label: "Password", text: $password,
                          placeholder: "At least \(AuthClient.minimumPasswordLength) characters",
                          secure: true, contentType: .newPassword,
                          focused: focus == .password, onSubmit: submit)
                    .focused($focus, equals: .password)

                AuthButton(title: "Create account", busyTitle: "Creating your account…",
                           busy: busy, enabled: canSubmit, action: submit)
                    .padding(.top, 4)

                AuthMessageSlot(error: error, notice: nil)

                CrossLink(question: "Already have an account?", action: "Sign in →",
                          onTap: goSignIn)

                LegalFooter()
            }
        }
    }

    private func submit() {
        guard canSubmit else { return }
        focus = nil
        busy = true; error = nil
        Task {
            do {
                let session = try await AuthClient.signUp(email: email, password: password)
                store.signedIn(session: session, name: name)
            } catch let e as AuthClient.AuthError {
                error = e.errorDescription
            } catch {
                self.error = error.localizedDescription
            }
            busy = false
        }
    }
}

// MARK: - Starting without an account

/// The way in while there is no authentication server.
///
/// Trace needs to know who is using the phone, and until something issues
/// accounts the only honest answer is "you are". So this screen asks for a name
/// and nothing else: no email to confirm, no password to check against a server
/// that would refuse the request, and no credentials stored anywhere.
///
/// It exists because the alternative was worse than unfinished. Sign in and sign
/// up were both on screen with no server behind them, so a new climber typed an
/// email, pressed Create account, and was told accounts are not switched on.
/// That is a dead end on the first screen, and a form that cannot succeed should
/// not be shown at all.
///
/// The account this makes is a real one as far as the rest of the app is
/// concerned, and it is the same `Account.local` a signed-in climber's phone
/// would fall back to. When a server does exist, `AuthClient.isConfigured` turns
/// true, the two credential screens appear in place of this one, and nothing
/// here needs revisiting.
struct LocalStartScreen: View {
    @ObservedObject private var store = Store.shared
    @State private var revealed = false
    @State private var name = ""
    @FocusState private var naming: Bool

    var body: some View {
        AuthShell(revealed: $revealed) {
            VStack(spacing: 14) {
                // The name is optional, which the field says rather than
                // implies: an asterisk on everything else would be the only
                // other way to make "optional" legible, and there is nothing
                // else on this screen to mark.
                AuthField(label: "What should Trace call you?", text: $name,
                          placeholder: "Name", contentType: .name,
                          focused: naming, onSubmit: start)
                    .focused($naming)

                AuthButton(title: "Start climbing", busyTitle: "Starting…",
                           busy: false, enabled: true, action: start)
                    .padding(.top, 4)

                Text("Everything Trace records stays on this phone: your climbs, your clips, the walls you scan. There is nothing to sign in to and nothing to sign up for.")
                    .font(Theme.ui(13))
                    .foregroundStyle(Theme.ink2)
                    .lineSpacing(3)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)

                LegalFooter()
            }
        }
    }

    private func start() {
        naming = false
        store.continueLocally(name: name)
    }
}

// MARK: - Which one is showing

/// Holds the reveal state across the three screens so the mark settles once and
/// then stays put while you move between them.
struct WelcomeScreen: View {
    private enum Page { case signIn, signUp }
    @State private var page: Page = .signIn
    @State private var revealed = false

    var body: some View {
        Group {
            switch page {
            case .signIn:
                SignInScreen(revealed: $revealed, goSignUp: { go(.signUp) })
            case .signUp:
                SignUpScreen(revealed: $revealed, goSignIn: { go(.signIn) })
            }
        }
        .transition(.opacity)
    }

    private func go(_ next: Page) {
        withAnimation(.easeInOut(duration: 0.2)) { page = next }
    }
}

// MARK: - Stay signed in

/// Asked once, straight after signing in.
///
/// It is a real question rather than a courtesy: answering no means nothing is
/// written to this phone at all, so the next launch starts at sign-in. That is
/// the right default for a shared or borrowed handset, and the wrong one for
/// the phone in your chalk bag, which is why it is asked rather than assumed.
struct StaySignedInScreen: View {
    @ObservedObject private var store = Store.shared
    @State private var revealed = true

    var body: some View {
        ZStack {
            PaperGround()
            VStack(spacing: 0) {
                Spacer(minLength: 0)

                VStack(spacing: 16) {
                    MountainMark(inset: 0)
                        .frame(width: 96, height: 96)

                    Text("Stay signed in?")
                        .font(Theme.serif(30, .semibold))
                        .foregroundStyle(Theme.ink)
                        .multilineTextAlignment(.center)

                    Text("Say yes and Trace opens straight into your climbs next time. Say no and it asks for your password again.")
                        .font(Theme.ui(15))
                        .foregroundStyle(Theme.ink2)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                VStack(spacing: 10) {
                    Button { store.keepSignedIn(true) } label: {
                        Text("Keep me signed in")
                            .font(Theme.ui(16, .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Theme.button)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    Button { store.keepSignedIn(false) } label: {
                        Text("Ask me every time")
                            .font(Theme.ui(16, .semibold))
                            .foregroundStyle(Theme.ink)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Theme.surface)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: 340)
            .padding(.horizontal, Theme.gutter)
            .padding(.top, 80)
            .padding(.bottom, 44)
        }
        .preferredColorScheme(.light)
    }
}

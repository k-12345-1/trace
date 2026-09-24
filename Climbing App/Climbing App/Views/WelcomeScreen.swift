import SwiftUI

/// Sign in, or make an account, or neither.
///
/// The third option is not a cop-out. Trace stores everything on the phone, so an
/// account genuinely is optional, and a screen that pretended otherwise would be
/// lying to get an email address.
struct WelcomeScreen: View {
    @ObservedObject private var store = Store.shared

    enum Mode { case signIn, signUp }
    @State private var mode: Mode = .signIn
    @State private var email = ""
    @State private var password = ""
    @State private var name = ""
    @State private var busy = false
    @State private var error: String?
    @State private var notice: String?
    @State private var showLocal = false
    @FocusState private var focus: Field?

    enum Field { case email, password, name }

    private var canSubmit: Bool {
        AuthClient.validateEmail(email) && AuthClient.validatePassword(password) && !busy
    }

    var body: some View {
        ZStack {
            Theme.ground.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    masthead
                    if showLocal { localForm } else { accountForm }
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.bottom, 44)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .preferredColorScheme(.light)
    }

    // MARK: Masthead

    private var masthead: some View {
        VStack(alignment: .leading, spacing: 14) {
            // The icon itself, so the sign-in screen and the home screen icon
            // are recognisably the same object.
            HStack(spacing: 12) {
                MountainMark(color: .white, inset: 0.16)
                    .frame(width: 46, height: 46)
                    .background(Theme.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                Text("Trace")
                    .font(Theme.serif(28, .semibold))
                    .foregroundStyle(Theme.blue)
            }
            .padding(.bottom, 6)

            Text("Watches you climb.\nTells you one thing.")
                .font(Theme.title(34))
                .foregroundStyle(Theme.ink)
                .lineSpacing(2)
            Text("Your clips, your wall photos and your history stay on this phone. An account is identity, not storage.")
                .font(Theme.ui(15))
                .foregroundStyle(Theme.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 48)
        .padding(.bottom, 30)
    }

    // MARK: Email and password

    private var accountForm: some View {
        VStack(alignment: .leading, spacing: 18) {
            modeToggle

            if !AuthClient.isConfigured { notConnected }

            field("Email", text: $email, field: .email,
                  placeholder: "you@example.com", keyboard: .emailAddress)
            secureField

            if mode == .signUp {
                Text("At least \(AuthClient.minimumPasswordLength) characters.")
                    .font(Theme.ui(13))
                    .foregroundStyle(Theme.ink3)
            }

            if let error { message(error, tone: Theme.ember[4]) }
            if let notice { message(notice, tone: Theme.accentText) }

            Button(action: submit) {
                HStack(spacing: 9) {
                    if busy { ProgressView().tint(.white).scaleEffect(0.8) }
                    Text(mode == .signIn ? "Sign in" : "Create account")
                        .font(Theme.ui(16, .semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Theme.accent)
                .clipShape(Capsule())
                .opacity(canSubmit ? 1 : 0.35)
            }
            .buttonStyle(.plain)
            .disabled(!canSubmit)

            if mode == .signIn {
                Button("Forgot your password?") { resetPassword() }
                    .font(Theme.ui(14, .medium))
                    .foregroundStyle(Theme.accentText)
                    .frame(maxWidth: .infinity)
                    .disabled(busy)
            }

            divider

            FlatButton(title: "Use Trace without an account") {
                withAnimation(.easeInOut(duration: 0.2)) { showLocal = true }
            }
        }
    }

    /// Two segments on a light grey track, the selected one filled in the dark
    /// blue. The same shape language as the bar, rather than the stock control.
    private var modeToggle: some View {
        HStack(spacing: 4) {
            segment("Sign in", .signIn)
            segment("Create account", .signUp)
        }
        .padding(4)
        .background(Theme.surface)
        .clipShape(Capsule())
    }

    private func segment(_ title: String, _ m: Mode) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) { mode = m }
            error = nil; notice = nil
        } label: {
            Text(title)
                .font(Theme.ui(15, .semibold))
                .foregroundStyle(mode == m ? .white : Theme.ink2)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(mode == m ? Theme.blue : .clear, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: No account

    private var localForm: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                SectionTitle("Nothing changes, really")
                Text("Every measurement Trace makes happens on this phone, so it all works without an account. You lose one thing: if you replace this phone, the history does not follow you.")
                    .font(Theme.ui(15))
                    .foregroundStyle(Theme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            field("What should I call you?", text: $name, field: .name,
                  placeholder: "Katie", keyboard: .default)

            Button {
                store.continueLocally(name: name)
            } label: {
                Text("Start climbing")
                    .font(Theme.ui(16, .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Theme.accent)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showLocal = false }
            } label: {
                Text("Back to sign in")
                    .font(Theme.ui(14, .medium))
                    .foregroundStyle(Theme.ink3)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Pieces

    private var notConnected: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "info.circle")
                .font(.system(size: 17))
                .foregroundStyle(Theme.blueLight)
            VStack(alignment: .leading, spacing: 4) {
                Text("Not connected yet")
                    .font(Theme.ui(15, .semibold))
                    .foregroundStyle(Theme.ink)
                Text("No server is configured, so sign in will not work on this build. Everything else does. Carry on without an account below.")
                    .font(Theme.ui(13.5))
                    .foregroundStyle(Theme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.accentWash)
        .clipShape(RoundedRectangle(cornerRadius: Theme.rCard, style: .continuous))
    }

    private func field(_ label: String, text: Binding<String>, field: Field,
                       placeholder: String, keyboard: UIKeyboardType) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel(label)
            TextField("", text: text, prompt: Text(placeholder).foregroundStyle(Theme.ink3))
                .font(Theme.ui(16))
                .foregroundStyle(Theme.ink)
                .keyboardType(keyboard)
                .textInputAutocapitalization(field == .name ? .words : .never)
                .autocorrectionDisabled()
                .textContentType(field == .email ? .emailAddress : .name)
                .focused($focus, equals: field)
                .padding(.horizontal, 17).padding(.vertical, 16)
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: Theme.r, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.r, style: .continuous)
                    .stroke(focus == field ? Theme.accent : .clear, lineWidth: 1.5))
        }
    }

    private var secureField: some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel("Password")
            SecureField("", text: $password,
                        // The length requirement lives under the field, where it
                        // stays visible once typing has cleared the placeholder.
                        prompt: Text(mode == .signUp ? "Choose a password" : "Your password")
                            .foregroundStyle(Theme.ink3))
                .font(Theme.ui(16))
                .foregroundStyle(Theme.ink)
                .textContentType(mode == .signUp ? .newPassword : .password)
                .focused($focus, equals: .password)
                .padding(.horizontal, 17).padding(.vertical, 16)
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: Theme.r, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.r, style: .continuous)
                    .stroke(focus == .password ? Theme.accent : .clear, lineWidth: 1.5))
                .onSubmit(submit)
        }
    }

    /// Sentence case, like every other label in the app. The uppercase mono that
    /// used to sit here belonged to the instrument panel the app no longer is.
    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(Theme.ui(14, .semibold))
            .foregroundStyle(Theme.ink2)
    }

    private func message(_ text: String, tone: Color) -> some View {
        Text(text)
            .font(Theme.ui(14))
            .foregroundStyle(tone)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var divider: some View {
        HStack(spacing: 14) {
            Hairline()
            Text("or")
                .font(Theme.ui(13))
                .foregroundStyle(Theme.ink3)
            Hairline()
        }
        .padding(.vertical, 2)
    }

    // MARK: Actions

    private func submit() {
        guard canSubmit else { return }
        focus = nil
        busy = true; error = nil; notice = nil

        Task {
            do {
                let session = mode == .signIn
                    ? try await AuthClient.signIn(email: email, password: password)
                    : try await AuthClient.signUp(email: email, password: password)
                store.signedIn(session: session, name: name)
            } catch let e as AuthClient.AuthError {
                // A sign-up awaiting email confirmation is a success, so it is
                // shown in the affirmative rather than as a failure.
                if case .needsConfirmation = e {
                    notice = e.errorDescription
                    mode = .signIn
                } else {
                    error = e.errorDescription
                }
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

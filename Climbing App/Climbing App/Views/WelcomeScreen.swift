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
                .padding(.bottom, 40)
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
            MountainMark(color: .white, inset: 0.12)
                .frame(width: 60, height: 60)
                .background(Theme.blue)
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                .padding(.bottom, 4)
            Text("Trace")
                .font(Theme.ui(20, .bold))
                .foregroundStyle(Theme.ink)
            Text("Watches you climb.\nTells you one thing.")
                .font(Theme.title(34))
                .foregroundStyle(Theme.ink)
                .lineSpacing(2)
            Text("Your clips, your wall photos and your history stay on this phone. An account is identity, not storage.")
                .font(Theme.ui(15))
                .foregroundStyle(Theme.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 54)
        .padding(.bottom, 32)
    }

    // MARK: Email and password

    private var accountForm: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("", selection: $mode) {
                Text("Sign in").tag(Mode.signIn)
                Text("Create account").tag(Mode.signUp)
            }
            .pickerStyle(.segmented)
            .onChange(of: mode) { _, _ in error = nil; notice = nil }

            if !AuthClient.isConfigured { notConnected }

            field("Email", text: $email, field: .email,
                  placeholder: "you@example.com", keyboard: .emailAddress)
            secureField

            if mode == .signUp {
                Text("At least \(AuthClient.minimumPasswordLength) characters.")
                    .font(Theme.body(11.5))
                    .foregroundStyle(Theme.ink3)
            }

            if let error { message(error, tone: Theme.accentText) }
            if let notice { message(notice, tone: Theme.ok) }

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
                .opacity(canSubmit ? 1 : 0.4)
            }
            .buttonStyle(.plain)
            .disabled(!canSubmit)

            if mode == .signIn {
                Button("Forgot your password?") { resetPassword() }
                    .font(Theme.body(12.5))
                    .foregroundStyle(Theme.ink3)
                    .disabled(busy)
            }

            divider

            Button {
                withAnimation(.easeInOut(duration: 0.18)) { showLocal = true }
            } label: {
                Text("Use Trace without an account")
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

    // MARK: No account

    private var localForm: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 7) {
                MicroLabel(text: "No account")
                Text("Nothing changes, really")
                    .font(Theme.heading(19))
                    .foregroundStyle(Theme.ink)
                Text("Every measurement Trace makes happens on this phone, so it all works without an account. You lose one thing: if you replace this phone, the history does not follow you.")
                    .font(Theme.body(14))
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
                withAnimation(.easeInOut(duration: 0.18)) { showLocal = false }
            } label: {
                Text("Back to sign in")
                    .font(Theme.ui(15, .semibold))
                    .foregroundStyle(Theme.ink3)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Pieces

    private var notConnected: some View {
        VStack(alignment: .leading, spacing: 6) {
            MicroLabel(text: "Not connected yet", color: Theme.accentText)
            Text("No server is configured, so sign in will not work on this build. Everything else does. Carry on without an account below.")
                .font(Theme.body(12.5))
                .foregroundStyle(Theme.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.blueWash)
        .clipShape(RoundedRectangle(cornerRadius: Theme.r, style: .continuous))
    }

    private func field(_ label: String, text: Binding<String>, field: Field,
                       placeholder: String, keyboard: UIKeyboardType) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            MicroLabel(text: label)
            TextField("", text: text, prompt: Text(placeholder).foregroundStyle(Theme.ink3))
                .font(Theme.body(16))
                .foregroundStyle(Theme.ink)
                .keyboardType(keyboard)
                .textInputAutocapitalization(field == .name ? .words : .never)
                .autocorrectionDisabled()
                .textContentType(field == .email ? .emailAddress : .name)
                .focused($focus, equals: field)
                .padding(.horizontal, 16).padding(.vertical, 15)
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: Theme.r, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.r, style: .continuous)
                    .stroke(focus == field ? Theme.accent : .clear, lineWidth: 1.5))
        }
    }

    private var secureField: some View {
        VStack(alignment: .leading, spacing: 7) {
            MicroLabel(text: "Password")
            SecureField("", text: $password,
                        prompt: Text(mode == .signUp ? "At least 8 characters" : "Your password")
                            .foregroundStyle(Theme.ink3))
                .font(Theme.body(16))
                .foregroundStyle(Theme.ink)
                .textContentType(mode == .signUp ? .newPassword : .password)
                .focused($focus, equals: .password)
                .padding(.horizontal, 16).padding(.vertical, 15)
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: Theme.r, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.r, style: .continuous)
                    .stroke(focus == .password ? Theme.accent : .clear, lineWidth: 1.5))
                .onSubmit(submit)
        }
    }

    private func message(_ text: String, tone: Color) -> some View {
        Text(text)
            .font(Theme.body(13))
            .foregroundStyle(tone)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var divider: some View {
        HStack(spacing: 12) {
            Hairline()
            MicroLabel(text: "or")
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

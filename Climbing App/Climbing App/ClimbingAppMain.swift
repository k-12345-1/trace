import SwiftUI

@main
struct TraceApp: App {
    init() { Fonts.register() }

    var body: some Scene {
        WindowGroup { AppEntry() }
    }
}

/// Three states, in order: no account, an account that has not yet said whether
/// it wants to be remembered, and an account that is through.
struct AppEntry: View {
    @ObservedObject private var store = Store.shared

    private enum Stage: Equatable { case welcome, askStaySignedIn, app }

    private var stage: Stage {
        guard store.account != nil else { return .welcome }
        return store.staySignedIn == nil ? .askStaySignedIn : .app
    }

    var body: some View {
        Group {
            switch stage {
            // Which welcome depends on whether anything can issue an account.
            // With no auth server there is nothing to sign in to, and showing a
            // sign-in form that cannot succeed is a dead end on the first
            // screen rather than a promise of things to come.
            case .welcome:
                if AuthClient.isConfigured {
                    WelcomeScreen().transition(.opacity)
                } else {
                    LocalStartScreen().transition(.opacity)
                }
            case .askStaySignedIn:  StaySignedInScreen().transition(.opacity)
            case .app:              MainTabs().transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.22), value: stage)
        .task { await store.refreshSessionIfNeeded() }
    }
}

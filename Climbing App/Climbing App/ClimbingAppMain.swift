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
            case .welcome:          WelcomeScreen().transition(.opacity)
            case .askStaySignedIn:  StaySignedInScreen().transition(.opacity)
            case .app:              MainTabs().transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.22), value: stage)
        .task { await store.refreshSessionIfNeeded() }
    }
}

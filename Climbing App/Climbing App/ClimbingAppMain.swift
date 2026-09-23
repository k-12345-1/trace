import SwiftUI

@main
struct TraceApp: App {
    init() { Fonts.register() }

    var body: some Scene {
        WindowGroup { AppEntry() }
    }
}

/// First launch lands on the welcome screen. After that the account is on the
/// phone and the app opens straight into the climbs.
struct AppEntry: View {
    @ObservedObject private var store = Store.shared

    var body: some View {
        Group {
            if store.account == nil {
                WelcomeScreen()
                    .transition(.opacity)
            } else {
                MainTabs()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.22), value: store.account == nil)
        .task { await store.refreshSessionIfNeeded() }
    }
}

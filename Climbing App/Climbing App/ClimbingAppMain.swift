import SwiftUI

@main
struct TraceApp: App {
    init() { Fonts.register() }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

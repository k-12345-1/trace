import SwiftUI

@main
struct SpotterApp: App {
    init() { Fonts.register() }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

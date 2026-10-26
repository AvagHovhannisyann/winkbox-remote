import SwiftUI

@main
struct WinkRemoteApp: App {
    @StateObject private var tv = TV()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(tv)
                .preferredColorScheme(.dark)
        }
    }
}

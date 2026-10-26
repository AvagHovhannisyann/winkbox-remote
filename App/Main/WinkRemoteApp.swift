import SwiftUI

@main
struct WinkRemoteApp: App {
    @StateObject private var tv = TV()
    @StateObject private var assistant = Assistant()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(tv)
                .environmentObject(assistant)
                .preferredColorScheme(.dark)
        }
    }
}

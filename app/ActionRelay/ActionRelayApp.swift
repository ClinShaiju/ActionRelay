import SwiftUI

@main
struct ActionRelayApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

struct RootView: View {
    var body: some View {
        TabView {
            StatusView()
                .tabItem { Label("Status", systemImage: "dot.radiowaves.left.and.right") }
            ConfigView()
                .tabItem { Label("Action", systemImage: "bolt") }
            PairingView()
                .tabItem { Label("Pairing", systemImage: "link") }
        }
    }
}

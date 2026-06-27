import SwiftUI

extension Notification.Name {
    static let pairingImported = Notification.Name("pairingImported")
}

@main
struct ActionRelayApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                // Share-sheet "Open in ActionRelay" path — robust to the file
                // picker greying out iCloud/undownloaded files.
                .onOpenURL { url in
                    let msg = PairingImport.save(from: url)
                    NotificationCenter.default.post(
                        name: .pairingImported, object: nil, userInfo: ["message": msg])
                }
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

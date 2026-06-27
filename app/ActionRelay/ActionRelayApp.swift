import SwiftUI
import UserNotifications
import UIKit

extension Notification.Name {
    static let pairingImported = Notification.Name("pairingImported")
}

@main
struct ActionRelayApp: App {
    init() { UNUserNotificationCenter.current().delegate = NotificationRouter.shared }

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

/// Handles taps on the background-Shortcut fallback notification: tapping it
/// brings the app foreground and runs the Shortcut URL (which now succeeds).
/// Also shows our notifications while the app is foreground so they're tappable.
final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationRouter()

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if let s = response.notification.request.content.userInfo["shortcutURL"] as? String,
           let url = URL(string: s) {
            UIApplication.shared.open(url)
        }
        completionHandler()
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
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

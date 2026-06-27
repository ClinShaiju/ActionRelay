import Foundation
import UserNotifications

/// Fires the user's configured action for a classified gesture (§8.3).
/// Notification + webhook. Runs in the app process now (no NE), so a future
/// `openURL`/Shortcut dispatch is actually possible here — unlike from an NE.
struct Dispatcher {
    let config: AppConfig

    func dispatch(_ gesture: Gesture) {
        let name = label(gesture)
        switch config.target {
        case .notification: notify(name)
        case .webhook: postWebhook(name)
        }
    }

    func label(_ g: Gesture) -> String {
        switch g {
        case .press: return "press"
        case .hold: return "hold"
        case .double: return "double"
        }
    }

    private func notify(_ gesture: String) {
        let content = UNMutableNotificationContent()
        content.title = "Action Button"
        content.body = "Detected: \(gesture)"
        content.sound = .default
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    private func postWebhook(_ gesture: String) {
        guard let url = URL(string: config.webhookURL), !config.webhookURL.isEmpty else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(
            withJSONObject: ["gesture": gesture, "ts": Date().timeIntervalSince1970])
        URLSession.shared.dataTask(with: req).resume()
    }
}

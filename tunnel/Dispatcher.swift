import Foundation
import UserNotifications

/// Fires the user's configured action for a classified gesture (§8.3).
/// Runs inside the NE, so: notifications work, webhooks work (must bypass the
/// tunnel route), but `openURL`/Shortcut-launch do NOT — see §8.3 workarounds.
struct Dispatcher {
    let config: AppConfig

    func dispatch(_ gesture: Gesture) {
        let name = label(gesture)
        record(name)
        switch config.target {
        case .notification:
            notify(name)
        case .webhook:
            postWebhook(name)
        }
    }

    private func label(_ g: Gesture) -> String {
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
        let req = UNNotificationRequest(
            identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }

    private func postWebhook(_ gesture: String) {
        guard let url = URL(string: config.webhookURL), !config.webhookURL.isEmpty
        else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(
            withJSONObject: ["gesture": gesture, "ts": Date().timeIntervalSince1970])
        // ponytail: fire-and-forget. The NE must exclude this destination from the
        // tunnel route (§5) or the POST loops back into the loopback VPN.
        URLSession.shared.dataTask(with: req).resume()
    }

    private func record(_ gesture: String) {
        var s = RelayStatus.load()
        s.lastEvent = "\(gesture) @ \(ISO8601DateFormatter().string(from: Date()))"
        s.save()
    }
}

import Foundation
import UserNotifications
import AVFoundation
import UIKit

/// Fires the user's configured action for a classified gesture (§8.3). Runs in
/// the app process (no NE), so openURL/Shortcut dispatch is possible here.
struct Dispatcher {
    let config: AppConfig

    func dispatch(_ gesture: Gesture) {
        let name = label(gesture)
        switch config.target {
        case .notification: notify(name)
        case .webhook: postWebhook(name)
        case .flashlight: toggleTorch()
        case .shortcut: runShortcut(name)
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

    /// Toggle the rear torch. No capture session, so no camera permission needed.
    private func toggleTorch() {
        guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else { return }
        do {
            try device.lockForConfiguration()
            device.torchMode = (device.torchMode == .on) ? .off : .on
            device.unlockForConfiguration()
        } catch { /* torch busy/unavailable */ }
    }

    /// Run a named Shortcut via the shortcuts:// URL scheme. The gesture is passed
    /// as text input. ponytail: openURL from a backgrounded app can be refused by
    /// iOS — works reliably foregrounded; if it no-ops in the background, pair it
    /// with a notification the user taps. Upgrade path: App Intents donation.
    private func runShortcut(_ gesture: String) {
        let name = config.shortcutName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        var comps = URLComponents()
        comps.scheme = "shortcuts"
        comps.host = "run-shortcut"
        comps.queryItems = [
            URLQueryItem(name: "name", value: name),
            URLQueryItem(name: "input", value: "text"),
            URLQueryItem(name: "text", value: gesture),
        ]
        guard let url = comps.url else { return }
        DispatchQueue.main.async { UIApplication.shared.open(url) }
    }
}

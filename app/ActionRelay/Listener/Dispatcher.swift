import Foundation
import Darwin
import UserNotifications
import AVFoundation
import UIKit

/// Fires the per-gesture action (§8.3). Runs in the app process (no NE), so
/// openURL/Shortcut dispatch is possible. Config is loaded fresh per fire, so
/// action edits apply on the next press without restarting the listener.
/// Returns an error string to surface in the UI, or nil on success.
struct Dispatcher {
    @discardableResult
    func dispatch(_ gesture: Gesture) -> String? {
        let action = AppConfig.load().action(for: gesture)
        let name = label(gesture)
        switch action.target {
        case .none:           return nil
        case .notification:   notify(name); return nil
        case .flashlight:     return toggleTorch()
        case .mediaPlayPause: return MediaRemote.command(MediaRemote.togglePlayPause)
        case .mediaNext:      return MediaRemote.command(MediaRemote.next)
        case .mediaPrevious:  return MediaRemote.command(MediaRemote.previous)
        case .shortcut:       return runShortcut(name, action.shortcutName)
        case .webhook:        return postWebhook(name, action.webhookURL)
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

    private func postWebhook(_ gesture: String, _ webhookURL: String) -> String? {
        guard let url = URL(string: webhookURL), !webhookURL.isEmpty else { return "Webhook: no URL set." }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(
            withJSONObject: ["gesture": gesture, "ts": Date().timeIntervalSince1970])
        URLSession.shared.dataTask(with: req).resume()
        return nil
    }

    /// Toggle the rear torch. No capture session needed; works backgrounded.
    private func toggleTorch() -> String? {
        guard let device = AVCaptureDevice.default(for: .video) else { return "No camera device." }
        guard device.hasTorch, device.isTorchAvailable else { return "Torch unavailable right now." }
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            if device.torchMode == .on { device.torchMode = .off }
            else { try device.setTorchModeOn(level: 1.0) }
            return nil
        } catch { return "Torch: \(error.localizedDescription)" }
    }

    /// Run a named Shortcut. Foreground → open directly. Background → iOS refuses
    /// openURL, so post a one-tap notification that runs it (the only way to
    /// launch a Shortcut from the background). Media/flashlight need no tap.
    private func runShortcut(_ gesture: String, _ name: String) -> String? {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty else { return "Shortcut: no name set." }
        var comps = URLComponents()
        comps.scheme = "shortcuts"
        comps.host = "run-shortcut"
        comps.queryItems = [
            URLQueryItem(name: "name", value: n),
            URLQueryItem(name: "input", value: "text"),
            URLQueryItem(name: "text", value: gesture),
        ]
        guard let url = comps.url else { return "Shortcut: bad name." }

        if UIApplication.shared.applicationState == .active {
            UIApplication.shared.open(url)
        } else if !Self.openURLFromBackground(url) {
            // Private launch unavailable → one-tap notification fallback.
            let content = UNMutableNotificationContent()
            content.title = "Run “\(n)”"
            content.body = "Tap to run this Shortcut (\(gesture))."
            content.sound = .default
            content.userInfo = ["shortcutURL": url.absoluteString]
            UNUserNotificationCenter.current().add(
                UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        }
        return nil
    }

    /// Launch a URL from the background via the private LSApplicationWorkspace —
    /// UIApplication.open is refused when backgrounded, but a sideloaded app can
    /// usually reach the Shortcuts URL this way. Returns whether we invoked it
    /// (not whether the OS ultimately honored it). Private API; sideload-only.
    private static func openURLFromBackground(_ url: URL) -> Bool {
        guard let cls = NSClassFromString("LSApplicationWorkspace") as? NSObject.Type else { return false }
        let wsSel = NSSelectorFromString("defaultWorkspace")
        guard cls.responds(to: wsSel),
              let ws = cls.perform(wsSel)?.takeUnretainedValue() as? NSObject else { return false }
        let openSel = NSSelectorFromString("openURL:")
        guard ws.responds(to: openSel) else { return false }
        ws.perform(openSel, with: url)
        return true
    }
}

/// System-wide media transport via the private MediaRemote framework. Controls
/// whatever app is currently playing (Apple Music, Spotify, …) and works from
/// the background — unlike Shortcuts. Private API, fine for a sideloaded app.
enum MediaRemote {
    static let play: Int32 = 0, pause: Int32 = 1, togglePlayPause: Int32 = 2
    static let stop: Int32 = 3, next: Int32 = 4, previous: Int32 = 5

    private typealias SendFn = @convention(c) (Int32, CFDictionary?) -> Bool
    private static let send: SendFn? = {
        guard let h = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY),
              let s = dlsym(h, "MRMediaRemoteSendCommand") else { return nil }
        return unsafeBitCast(s, to: SendFn.self)
    }()

    @discardableResult
    static func command(_ code: Int32) -> String? {
        guard let send else { return "MediaRemote unavailable." }
        return send(code, nil) ? nil : "Media command rejected (nothing playing?)."
    }
}

import Foundation

/// Identifiers shared by the app and the PacketTunnel extension.
/// The App Group is the only channel between the two processes (§5).
enum AppIDs {
    // ponytail: hardcoded here, not a build setting — change in one place if the
    // bundle id changes. The real TEAMID prefix is applied by the entitlements
    // at sign time; the literal string only has to match across both targets.
    static let appGroup = "group.com.clinshaiju.actionrelay"
    static let tunnelBundleID = "com.clinshaiju.actionrelay.tunnel"
}

/// Shared container for the pairing file, config, and event log.
enum SharedStore {
    static var container: URL? {
        FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: AppIDs.appGroup)
    }

    static var pairingFile: URL? { container?.appendingPathComponent("pairing.plist") }
    static var configFile: URL? { container?.appendingPathComponent("config.json") }
    static var eventLog: URL? { container?.appendingPathComponent("events.log") }

    static var defaults: UserDefaults? { UserDefaults(suiteName: AppIDs.appGroup) }
}

/// What to do when a gesture fires (§8.3). Notification is always available;
/// webhook must bypass the tunnel route.
enum DispatchTarget: String, Codable, CaseIterable, Identifiable {
    case notification
    case webhook
    var id: String { rawValue }
}

/// User configuration, persisted as JSON in the App Group container.
struct AppConfig: Codable, Equatable {
    var target: DispatchTarget = .notification
    var webhookURL: String = ""

    // Classifier tunables (§8.1), patchable without a rebuild.
    var pressMaxMs: UInt64 = 350
    var holdMinMs: UInt64 = 600
    var doubleWindowMs: UInt64 = 350

    static func load() -> AppConfig {
        guard let url = SharedStore.configFile,
              let data = try? Data(contentsOf: url),
              let cfg = try? JSONDecoder().decode(AppConfig.self, from: data)
        else { return AppConfig() }
        return cfg
    }

    func save() {
        guard let url = SharedStore.configFile,
              let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

/// Tunnel/listener status surfaced to the dashboard (§5). Written by the NE,
/// read by the app, via App Group UserDefaults.
struct RelayStatus: Codable, Equatable {
    var tunnelUp: Bool = false
    var pairingValid: Bool = false
    var lastHeartbeat: Date? = nil
    var lastEvent: String? = nil

    static func load() -> RelayStatus {
        guard let d = SharedStore.defaults,
              let data = d.data(forKey: "status"),
              let s = try? JSONDecoder().decode(RelayStatus.self, from: data)
        else { return RelayStatus() }
        return s
    }

    func save() {
        guard let d = SharedStore.defaults,
              let data = try? JSONEncoder().encode(self) else { return }
        d.set(data, forKey: "status")
    }
}

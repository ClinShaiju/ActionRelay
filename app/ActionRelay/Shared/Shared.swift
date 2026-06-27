import Foundation

/// Single-process storage in the app's own Documents container. No App Group —
/// that's a restricted entitlement an import-only cert can't provision, and with
/// no NE there's no second process to share with (docs/integration.md).
enum Store {
    static var dir: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    static var configFile: URL { dir.appendingPathComponent("config.json") }
    static var pairingFile: URL { dir.appendingPathComponent("pairing.plist") }
}

/// Shared pairing-import logic — used by both the in-app file picker and the
/// share-sheet "Open in ActionRelay" path (ActionRelayApp.onOpenURL). Validates
/// it's a real pairing record, then saves to the app container.
enum PairingImport {
    @discardableResult
    static func save(from src: URL) -> String {
        let scoped = src.startAccessingSecurityScopedResource()
        defer { if scoped { src.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: src)
            guard let plist = try PropertyListSerialization.propertyList(
                    from: data, options: [], format: nil) as? [String: Any],
                  plist["HostID"] != nil || plist["DeviceCertificate"] != nil else {
                return "Not a valid pairing record (missing HostID/DeviceCertificate)."
            }
            try data.write(to: Store.pairingFile, options: .atomic)
            return "Imported."
        } catch {
            return "Import failed: \(error.localizedDescription)"
        }
    }

    static var present: Bool { FileManager.default.fileExists(atPath: Store.pairingFile.path) }
}

/// What to do when a gesture fires (§8.3).
enum DispatchTarget: String, Codable, CaseIterable, Identifiable {
    case notification
    case webhook
    var id: String { rawValue }
}

/// User configuration, persisted as JSON in the app container.
struct AppConfig: Codable, Equatable {
    var target: DispatchTarget = .notification
    var webhookURL: String = ""

    // Classifier tunables (§8.1), patchable without a rebuild.
    var pressMaxMs: UInt64 = 350
    var holdMinMs: UInt64 = 600
    var doubleWindowMs: UInt64 = 350

    static func load() -> AppConfig {
        guard let data = try? Data(contentsOf: Store.configFile),
              let cfg = try? JSONDecoder().decode(AppConfig.self, from: data)
        else { return AppConfig() }
        return cfg
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: Store.configFile, options: .atomic)
    }
}

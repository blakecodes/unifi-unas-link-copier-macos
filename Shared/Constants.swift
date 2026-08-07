import Foundation

enum UNASLinkConstants {
    static let appGroup = "group.com.example.UNASLink"
    static let configurationChanged = Notification.Name("com.example.UNASLink.configurationChanged")
    static let urlScheme = "unaslink"
    static let keychainService = "com.example.UNASLink.session"
    static let keychainAccount = "TOKEN"
}

struct UNASConfiguration: Codable, Equatable {
    var serverURL: String = "https://unas.local"
    var mountRoot: String = "/Volumes/Shared_Drive"
    var driveRoot: String = "/shared/Shared_Drive"
    var allowSelfSignedCertificate: Bool = true

    var normalizedServerURL: URL? {
        let trimmed = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return URL(string: trimmed)
    }

    static func load() -> UNASConfiguration {
        guard
            let data = UserDefaults(suiteName: UNASLinkConstants.appGroup)?.data(forKey: "configuration"),
            let value = try? JSONDecoder().decode(UNASConfiguration.self, from: data)
        else { return UNASConfiguration() }
        return value
    }

    func save() throws {
        let data = try JSONEncoder().encode(self)
        guard let defaults = UserDefaults(suiteName: UNASLinkConstants.appGroup) else {
            throw ConfigurationError.unavailableSharedDefaults
        }
        defaults.set(data, forKey: "configuration")
        DistributedNotificationCenter.default().post(name: UNASLinkConstants.configurationChanged, object: nil)
    }

    func drivePath(for finderURL: URL) throws -> String {
        let root = URL(fileURLWithPath: mountRoot).standardizedFileURL
        let selected = finderURL.standardizedFileURL
        let rootComponents = root.pathComponents
        let selectedComponents = selected.pathComponents

        guard selectedComponents.count >= rootComponents.count,
              Array(selectedComponents.prefix(rootComponents.count)) == rootComponents else {
            throw ConfigurationError.outsideConfiguredMount
        }

        let relative = selectedComponents.dropFirst(rootComponents.count)
        let base = driveRoot.hasSuffix("/") ? String(driveRoot.dropLast()) : driveRoot
        return relative.reduce(base) { partial, component in
            partial + "/" + component
        }
    }
}

enum ConfigurationError: LocalizedError {
    case unavailableSharedDefaults
    case outsideConfiguredMount

    var errorDescription: String? {
        switch self {
        case .unavailableSharedDefaults:
            return "The shared app-group configuration is unavailable. Check signing and App Group capabilities."
        case .outsideConfiguredMount:
            return "The selected file is outside the configured UNAS mount."
        }
    }
}

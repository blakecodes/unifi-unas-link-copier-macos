import AppKit
import Foundation
import ServiceManagement
import UserNotifications

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()
    private static let showInDockKey = "showInDock"
    private static let loginItemPathKey = "loginItemBundlePath"

    @Published var configuration = UNASConfiguration.load()
    @Published var statusMessage = "Configure your UNAS mount, then sign in."
    @Published var isWorking = false
    @Published var showingLogin = false
    @Published var lastCopiedLink: URL?
    @Published var launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
    @Published var showInDock = UserDefaults.standard.bool(forKey: AppState.showInDockKey)

    var sessionSummary: String {
        guard let token = try? KeychainStore.loadSessionToken(),
              let claims = try? JWTClaims.decode(from: token) else {
            return "Not signed in"
        }
        if claims.isExpired { return "Session expired" }
        return "Signed in until \(claims.expirationDate.formatted(date: .abbreviated, time: .shortened))"
    }

    init() {
    }

    func saveConfiguration() {
        do {
            try configuration.save()
            statusMessage = "Configuration saved."
            objectWillChange.send()
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func beginLogin() {
        guard configuration.normalizedServerURL != nil else {
            statusMessage = "Enter a valid UNAS URL first."
            return
        }
        saveConfiguration()
        showingLogin = true
    }

    func didCaptureSession() {
        showingLogin = false
        statusMessage = "UNAS session saved securely in Keychain."
        objectWillChange.send()
    }

    func signOut() {
        KeychainStore.deleteSessionToken()
        statusMessage = "Local UNAS session removed."
        objectWillChange.send()
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        let service = SMAppService.mainApp
        do {
            if enabled {
                try service.register()
                UserDefaults.standard.set(Bundle.main.bundlePath, forKey: Self.loginItemPathKey)
            } else {
                try service.unregister()
                UserDefaults.standard.removeObject(forKey: Self.loginItemPathKey)
            }
            launchAtLoginEnabled = service.status == .enabled
            statusMessage = launchAtLoginEnabled
                ? "UNAS Link will launch in the menu bar when you sign in to your Mac."
                : "Launch at login disabled."
        } catch {
            launchAtLoginEnabled = service.status == .enabled
            statusMessage = "Could not update Launch at Login: \(error.localizedDescription)"
            if service.status == .requiresApproval {
                SMAppService.openSystemSettingsLoginItems()
            }
        }
    }

    func reconcileLaunchAtLoginLocation() {
        let service = SMAppService.mainApp
        guard service.status == .enabled else { return }

        let currentPath = URL(fileURLWithPath: Bundle.main.bundlePath).standardizedFileURL.path
        let recordedPath = UserDefaults.standard.string(forKey: Self.loginItemPathKey)
        guard recordedPath != currentPath else { return }

        do {
            try service.unregister()
            try service.register()
            UserDefaults.standard.set(currentPath, forKey: Self.loginItemPathKey)
            launchAtLoginEnabled = service.status == .enabled
        } catch {
            launchAtLoginEnabled = service.status == .enabled
            statusMessage = "Launch at Login needs to be enabled again: \(error.localizedDescription)"
        }
    }

    func setShowInDock(_ enabled: Bool) {
        showInDock = enabled
        UserDefaults.standard.set(enabled, forKey: Self.showInDockKey)
        applyDockVisibility()
        statusMessage = enabled
            ? "UNAS Link is now visible in the Dock and application switcher."
            : "UNAS Link is now available only from the menu bar."
    }

    func applyDockVisibility() {
        NSApplication.shared.setActivationPolicy(showInDock ? .regular : .accessory)
    }

    func handleIncomingURL(_ url: URL) {
        guard url.scheme == UNASLinkConstants.urlScheme,
              url.host == "copy",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let path = components.queryItems?.first(where: { $0.name == "path" })?.value else {
            statusMessage = "Received an invalid Finder request."
            return
        }
        copyLink(for: URL(fileURLWithPath: path))
    }

    func copyLink(for finderURL: URL) {
        guard !isWorking else { return }
        isWorking = true
        statusMessage = "Creating link for \(finderURL.lastPathComponent)…"

        Task {
            defer { isWorking = false }
            do {
                let drivePath = try configuration.drivePath(for: finderURL)
                let client = UNASAPIClient(configuration: configuration)
                let link = try await client.copyableLink(for: drivePath)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(link.absoluteString, forType: .string)
                lastCopiedLink = link
                statusMessage = "Copied \(link.absoluteString)"
                notify(title: "UNAS link copied", body: "\(finderURL.lastPathComponent) is ready in your clipboard.")
            } catch {
                statusMessage = error.localizedDescription
                notify(title: "Could not copy UNAS link", body: error.localizedDescription)
                if case UNASAPIError.notAuthenticated = error { showingLogin = true }
                if case UNASAPIError.sessionExpired = error { showingLogin = true }
            }
        }
    }

    private func notify(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}

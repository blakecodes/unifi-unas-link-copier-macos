import Cocoa
import FinderSync

final class FinderSync: FIFinderSync {
    override init() {
        super.init()
        refreshMonitoredDirectories()
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(configurationChanged),
            name: UNASLinkConstants.configurationChanged,
            object: nil
        )
    }

    deinit {
        DistributedNotificationCenter.default().removeObserver(self)
    }

    @objc private func configurationChanged() {
        refreshMonitoredDirectories()
    }

    private func refreshMonitoredDirectories() {
        let configuration = UNASConfiguration.load()
        let root = URL(fileURLWithPath: configuration.mountRoot).standardizedFileURL
        FIFinderSyncController.default().directoryURLs = [root]
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        guard menuKind == .contextualMenuForItems,
              let items = FIFinderSyncController.default().selectedItemURLs(),
              items.count == 1 else { return nil }

        let menu = NSMenu(title: "UNAS Link")
        let item = NSMenuItem(
            title: "Copy UNAS Share Link",
            action: #selector(copyShareLink(_:)),
            keyEquivalent: ""
        )
        item.target = self
        menu.addItem(item)
        return menu
    }

    @objc private func copyShareLink(_ sender: Any?) {
        guard let fileURL = FIFinderSyncController.default().selectedItemURLs()?.first else { return }

        var components = URLComponents()
        components.scheme = UNASLinkConstants.urlScheme
        components.host = "copy"
        components.queryItems = [URLQueryItem(name: "path", value: fileURL.path)]
        guard let requestURL = components.url else { return }

        let containingAppURL = Bundle.main.bundleURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        NSWorkspace.shared.open(
            [requestURL],
            withApplicationAt: containingAppURL,
            configuration: configuration
        ) { _, _ in }
    }
}

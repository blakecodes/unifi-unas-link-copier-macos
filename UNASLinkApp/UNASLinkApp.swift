import SwiftUI

private struct MenuBarMenu: View {
    @ObservedObject var state: AppState
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Text(state.sessionSummary)
        Divider()
        Button {
            NSApplication.shared.activate(ignoringOtherApps: true)
            openSettings()
        } label: {
            Label("Open UNAS Link Settings…", systemImage: "gearshape")
        }
        Toggle(
            "Launch at Login",
            isOn: Binding(
                get: { state.launchAtLoginEnabled },
                set: { state.setLaunchAtLogin($0) }
            )
        )
        Toggle(
            "Show in Dock",
            isOn: Binding(
                get: { state.showInDock },
                set: { state.setShowInDock($0) }
            )
        )
        Divider()
        Button("Quit UNAS Link") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}

@main
struct UNASLinkApp: App {
    @StateObject private var state = AppState.shared
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarMenu(state: state)
        } label: {
            Image("MenuBarIcon")
                .renderingMode(.template)
        }

        Settings {
            ContentView()
                .environmentObject(state)
        }
    }
}

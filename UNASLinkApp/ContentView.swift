import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        Form {
            Section("App Behavior") {
                Toggle(
                    "Launch UNAS Link at login",
                    isOn: Binding(
                        get: { state.launchAtLoginEnabled },
                        set: { state.setLaunchAtLogin($0) }
                    )
                )
                Toggle(
                    "Show UNAS Link in the Dock",
                    isOn: Binding(
                        get: { state.showInDock },
                        set: { state.setShowInDock($0) }
                    )
                )
                Text("When hidden from the Dock, closing this window keeps UNAS Link available from the menu bar.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("UNAS Connection") {
                TextField("Server URL", text: $state.configuration.serverURL)
                    .textFieldStyle(.roundedBorder)
                Toggle("Allow the configured UNAS host's self-signed certificate", isOn: $state.configuration.allowSelfSignedCertificate)
                HStack {
                    Button("Save Configuration") { state.saveConfiguration() }
                    Button("Sign In to UNAS…") { state.beginLogin() }
                    Button("Forget Session") { state.signOut() }
                }
                LabeledContent("Session", value: state.sessionSummary)
            }

            Section("Finder Path Mapping") {
                TextField("Mounted Finder folder", text: $state.configuration.mountRoot)
                    .textFieldStyle(.roundedBorder)
                TextField("UNAS Drive API root", text: $state.configuration.driveRoot)
                    .textFieldStyle(.roundedBorder)
                Text("Example: /Volumes/Shared_Drive/Public/file.zip becomes /shared/Shared_Drive/Public/file.zip")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Status") {
                Text(state.statusMessage)
                    .textSelection(.enabled)
                if let link = state.lastCopiedLink {
                    Link(link.absoluteString, destination: link)
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 680, minHeight: 430)
        .sheet(isPresented: $state.showingLogin) {
            VStack(spacing: 0) {
                HStack {
                    Text("Sign in directly to your UNAS")
                        .font(.headline)
                    Spacer()
                    Button("Cancel") { state.showingLogin = false }
                }
                .padding()
                Divider()
                LoginWebView(
                    configuration: state.configuration,
                    onSessionCaptured: state.didCaptureSession,
                    onError: { state.statusMessage = $0 }
                )
            }
            .frame(minWidth: 900, minHeight: 680)
        }
    }
}

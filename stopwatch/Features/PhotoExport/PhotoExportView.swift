import SwiftUI

struct PhotoExportView: View {
    @StateObject private var server = PhotoExportServer()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var copied = false

    var body: some View {
        NavigationStack {
            Form {
                Section("iPhone → Mac") {
                    Text("Start sharing here. The Mac script connects to this iPhone and downloads the day you choose.")
                    if server.running {
                        Text(server.connectionURL).font(.footnote.monospaced()).textSelection(.enabled)
                        ShareLink("Share connection URL", item: server.connectionURL)
                        Button(copied ? "Copied to clipboard" : "Copy connection URL") {
                            UIPasteboard.general.string = server.connectionURL
                            copied = true
                        }
                        Button("Stop sharing", role: .destructive) { server.stop() }
                    } else {
                        Button("Start sharing") { server.start() }.disabled(server.starting)
                    }
                }
                Section("On your Mac") {
                    Text("python3 ~/Xcode/iphone-photo-export.py 2026-09-19")
                        .font(.footnote.monospaced()).textSelection(.enabled)
                    Text("Replace the date, then paste this iPhone’s connection URL when the script asks. Files go into Downloads/YYMMDD-iphone-media.")
                }
                Section("Status") { Text(server.status).textSelection(.enabled) }
                Section {
                    Text("Keep this screen open and both devices on the same trusted Wi-Fi. Sharing stops when the app goes into the background. The Mac initiates every connection.")
                    Text("Copies originals, including Live Photo video components. Your library is unchanged. Full Photos access is required; locked Hidden and Recently Deleted items may be inaccessible. iCloud-only originals may need downloading first.")
                    Text("The URL contains a private session key. Transfers use local HTTP without encryption; use trusted Wi-Fi.")
                }
            }
            .navigationTitle("Photos to Mac")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { server.stop(); dismiss() } } }
            .onDisappear { server.stop() }
            .onChange(of: server.connectionURL) { _, _ in copied = false }
            .onChange(of: scenePhase) { _, phase in if phase == .background { server.stop() } }
        }
    }
}

#if os(macOS)
import SwiftUI

struct TCIconPreferences: View {
    @EnvironmentObject private var appDelegate: AppDelegate
    @AppStorage("TCApplicationIcon", store: UserDefaults.ghostty) private var selection = "BluePrompt"

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Application Icon").font(.title2)
            Picker("Icon", selection: $selection) {
                Text("Blue Terminal Prompt").tag("BluePrompt")
                Text("Original Ghostty-TC").tag("GhosttyTC")
            }
            HStack(spacing: 24) {
                iconPreview("BluePrompt")
                iconPreview("GhosttyTC")
            }
            Text("Your selection is saved and applies immediately.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(width: 400)
        .onChange(of: selection) { _ in appDelegate.applyTCApplicationIcon() }
    }

    @ViewBuilder
    private func iconPreview(_ name: String) -> some View {
        if let url = Bundle.main.url(forResource: name + "-choice", withExtension: "icns"),
           let image = NSImage(contentsOf: url) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: 96, height: 96)
        }
    }
}
#endif

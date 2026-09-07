import SwiftUI

struct SettingsView: View {
    @AppStorage(Preferences.Key.pollInterval) private var pollInterval = 0.5
    @AppStorage(Preferences.Key.hoverDelay) private var hoverDelay = 150.0
    @AppStorage(Preferences.Key.thumbnailMode) private var thumbnailMode = false
    @AppStorage(Preferences.Key.showSourceApp) private var showSourceApp = true

    var body: some View {
        Form {
            Section {
                Picker("Poll interval", selection: $pollInterval) {
                    ForEach(Preferences.pollIntervalChoices, id: \.self) { seconds in
                        Text(seconds.formatted(.number.precision(.fractionLength(0...2))) + " s").tag(seconds)
                    }
                }
                Picker("Hover delay", selection: $hoverDelay) {
                    ForEach(Preferences.hoverDelayChoices, id: \.self) { milliseconds in
                        Text("\(Int(milliseconds)) ms").tag(milliseconds)
                    }
                }
            } footer: {
                Text("How often Clipbit checks the clipboard, and how long the pointer must rest on the icon before the preview appears.")
            }

            Section {
                Toggle("Thumbnail mode", isOn: $thumbnailMode)
                Toggle("Show source app in preview", isOn: $showSourceApp)
            } footer: {
                Text("Thumbnail mode replaces the menu bar symbol with a tiny copy of the image on the clipboard.")
            }
        }
        .formStyle(.grouped)
        .frame(width: 400)
        .fixedSize()
    }
}

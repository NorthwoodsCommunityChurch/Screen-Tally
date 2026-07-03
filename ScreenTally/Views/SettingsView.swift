import SwiftUI

struct SettingsView: View {
    @State private var settings = AppSettings.shared

    var body: some View {
        Form {
            Section("TSL Connection") {
                HStack {
                    Text("Port:")
                    TextField("Port", value: $settings.port, format: .number.grouping(.never))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                }
                Text("The Carbonite should be configured to connect to this port.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Border Display") {
                Toggle("Show border on Preview", isOn: $settings.showBorderOnPreview)

                Picker("Border thickness:", selection: $settings.borderThickness) {
                    Text("4 points").tag(4)
                    Text("8 points").tag(8)
                    Text("12 points").tag(12)
                    Text("16 points").tag(16)
                }
            }

            Section("General") {
                Toggle("Open at Login", isOn: $settings.launchAtLogin)
            }

            Section("About") {
                Text("Screen Tally displays a colored border around your screen based on tally data from a Ross Carbonite switcher.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 400, height: 300)
    }
}

#Preview {
    SettingsView()
}

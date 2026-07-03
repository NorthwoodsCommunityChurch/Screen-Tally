import SwiftUI

struct MenuBarView: View {
    let tslListener: TSLListener
    @State private var settings = AppSettings.shared
    @State private var updateManager = UpdateManager.shared
    @State private var showingSourcePicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text("Screen Tally")
                    .font(.headline)
                Spacer()
                connectionIndicator
            }

            Divider()

            // Connection Status
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Status:")
                        .foregroundStyle(.secondary)
                    Text(statusText)
                        .foregroundStyle(statusColor)
                }

                if tslListener.isConnected, let peer = tslListener.connectedPeer {
                    Text("Connected: \(peer)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let error = tslListener.lastError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Divider()

            // Current Tally Display
            if !settings.monitoredSourceIndices.isEmpty {
                HStack {
                    Text("Tally:")
                        .foregroundStyle(.secondary)
                    Text(tslListener.monitoredTally.label)
                        .foregroundStyle(tslListener.monitoredTally.swiftUIColor)
                        .fontWeight(.semibold)
                    if settings.monitoredSourceIndices.count > 1 {
                        Text("(\(settings.monitoredSourceIndices.count) sources)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Source Picker
            HStack {
                Text("Sources:")
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    showingSourcePicker = true
                } label: {
                    HStack(spacing: 4) {
                        if settings.monitoredSourceIndices.isEmpty {
                            Text("None selected")
                                .foregroundStyle(.secondary)
                        } else {
                            Text("\(settings.monitoredSourceIndices.count) selected")
                        }
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.bordered)
                .disabled(tslListener.sortedSources.isEmpty)
            }
            .popover(isPresented: $showingSourcePicker, arrowEdge: .trailing) {
                SourcePickerPopover(
                    sources: tslListener.sortedSources,
                    selectedIndices: $settings.monitoredSourceIndices
                )
            }

            if tslListener.sortedSources.isEmpty {
                if tslListener.isConnected {
                    Text("Waiting for tally data...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Connect to see available sources")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            // Port Configuration
            HStack {
                Text("Port:")
                    .foregroundStyle(.secondary)
                TextField("Port", value: $settings.port, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                Button("Restart") {
                    tslListener.restart()
                }
                .buttonStyle(.bordered)
            }

            Divider()

            // Quick Settings
            Toggle("Show border on Preview", isOn: $settings.showBorderOnPreview)
                .toggleStyle(.checkbox)

            Toggle("Open at Login", isOn: $settings.launchAtLogin)
                .toggleStyle(.checkbox)

            HStack {
                Text("Border thickness:")
                    .foregroundStyle(.secondary)
                Picker("", selection: $settings.borderThickness) {
                    Text("4pt").tag(4)
                    Text("8pt").tag(8)
                    Text("12pt").tag(12)
                    Text("16pt").tag(16)
                }
                .labelsHidden()
                .frame(width: 80)
            }

            // Screen Picker
            HStack {
                Text("Display:")
                    .foregroundStyle(.secondary)
                Picker("", selection: $settings.selectedScreenIndex) {
                    ForEach(Array(NSScreen.screens.enumerated()), id: \.offset) { index, screen in
                        Text(screenName(for: screen, index: index)).tag(index)
                    }
                }
                .labelsHidden()
            }

            Divider()

            // Update Section
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Version \(Version.current)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if updateManager.isChecking {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Button("Check") {
                            Task { await updateManager.checkForUpdates(force: true) }
                        }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(.blue)
                    }
                }

                if let version = updateManager.availableVersion {
                    HStack {
                        Text("Update available: \(version)")
                            .font(.caption)
                            .foregroundStyle(.orange)
                        Spacer()
                        if updateManager.isUpdating {
                            ProgressView()
                                .controlSize(.small)
                            Text("Installing...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Button("Install") {
                                Task { await updateManager.applyUpdate() }
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                    }
                }

                if let error = updateManager.lastError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Divider()

            // Debug Controls
            VStack(alignment: .leading, spacing: 8) {
                Text("Debug")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    Button {
                        settings.debugTallyOverride = .program
                    } label: {
                        Text("Red")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)

                    Button {
                        settings.debugTallyOverride = .preview
                    } label: {
                        Text("Green")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)

                    Button {
                        settings.debugTallyOverride = nil
                    } label: {
                        Text("Clear")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }

                if settings.debugTallyOverride != nil {
                    Text("Debug override active")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding()
        .frame(width: 280)
        .onAppear {
            Task { await updateManager.checkForUpdates() }
        }
    }

    private var connectionIndicator: some View {
        Circle()
            .fill(tslListener.isConnected ? Color.green : (tslListener.isListening ? Color.yellow : Color.red))
            .frame(width: 10, height: 10)
    }

    private var statusText: String {
        if tslListener.isConnected {
            return "Connected"
        } else if tslListener.isListening {
            return "Listening..."
        } else {
            return "Not listening"
        }
    }

    private var statusColor: Color {
        if tslListener.isConnected {
            return .green
        } else if tslListener.isListening {
            return .yellow
        } else {
            return .red
        }
    }

    private func screenName(for screen: NSScreen, index: Int) -> String {
        let name = screen.localizedName
        let isMain = screen == NSScreen.main
        if isMain {
            return "\(name) (Main)"
        }
        return name
    }
}

// MARK: - Source Picker Popover

private struct SourcePickerPopover: View {
    let sources: [SourceInfo]
    @Binding var selectedIndices: Set<Int>
    @State private var searchText = ""

    private var filteredSources: [SourceInfo] {
        if searchText.isEmpty {
            return sources
        }
        return sources.filter { source in
            source.displayName.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Select Sources")
                    .font(.headline)
                Spacer()
                if !selectedIndices.isEmpty {
                    Button("Clear All") {
                        selectedIndices = []
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.blue)
                }
            }
            .padding()

            // Search field
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search sources...", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)
            .padding(.horizontal)
            .padding(.bottom, 8)

            Divider()

            // Source list
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if filteredSources.isEmpty {
                        Text("No sources match \"\(searchText)\"")
                            .foregroundStyle(.secondary)
                            .padding()
                    } else {
                        ForEach(filteredSources) { source in
                            SourceToggleRow(
                                source: source,
                                isSelected: selectedIndices.contains(source.index),
                                onToggle: {
                                    if selectedIndices.contains(source.index) {
                                        selectedIndices.remove(source.index)
                                    } else {
                                        selectedIndices.insert(source.index)
                                    }
                                }
                            )
                            .padding(.horizontal)
                            .padding(.vertical, 4)

                            if source.id != filteredSources.last?.id {
                                Divider()
                                    .padding(.leading)
                            }
                        }
                    }
                }
            }
            .frame(minHeight: 200, maxHeight: 400)
        }
        .frame(width: 300)
    }
}

// MARK: - Source Toggle Row

private struct SourceToggleRow: View {
    let source: SourceInfo
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? .blue : .secondary)
                    .font(.system(size: 16))

                Text(source.displayName)
                    .foregroundStyle(.primary)
                    .font(.body)

                Spacer()

                if source.tally != .clear {
                    Circle()
                        .fill(source.tally.swiftUIColor)
                        .frame(width: 10, height: 10)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

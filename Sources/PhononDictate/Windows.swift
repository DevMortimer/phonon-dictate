import AppKit
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: Settings
    @ObservedObject var engine: Engine
    let store: Store
    let showHistory: () -> Void
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Section("Dictation") {
                LabeledContent("Shortcut") {
                    ShortcutRecorder(shortcut: $settings.shortcut, capturing: $settings.capturingShortcut)
                }
                Text("Press the shortcut to start recording and again to stop. Esc cancels. The text goes to the clipboard.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Storage") {
                Picker("Keep recordings", selection: $settings.recordingRetentionDays) {
                    ForEach(Settings.retentionChoices, id: \.self) { Text(Settings.retentionLabel($0)).tag($0) }
                }
                Picker("Keep history", selection: $settings.historyRetentionDays) {
                    ForEach(Settings.retentionChoices, id: \.self) { Text(Settings.retentionLabel($0)).tag($0) }
                }
                HStack {
                    Button("Open Recordings Folder") { NSWorkspace.shared.open(store.recordingsDir) }
                    Button("Show History") { showHistory() }
                }
            }
            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in setLaunchAtLogin(on) }
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
            }
            Section("Model") {
                LabeledContent("Model", value: "Phonon-2 (FermionResearch)")
                LabeledContent("Status", value: engine.state.description)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize()
    }

    private func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = error.localizedDescription
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

/// A button that records the next key combination as the new shortcut.
struct ShortcutRecorder: View {
    @Binding var shortcut: Shortcut
    @Binding var capturing: Bool
    @State private var monitor: Any?

    var body: some View {
        Button(capturing ? "Press a shortcut…" : shortcut.display) {
            capturing ? stop() : start()
        }
        .onDisappear { stop() }
    }

    private func start() {
        capturing = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53, Shortcut.carbonModifiers(event.modifierFlags) == 0 { // Esc
                stop()
            } else if let s = Shortcut(event: event) {
                shortcut = s
                stop()
            } else {
                NSSound.beep()
            }
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        capturing = false
    }
}

struct HistoryView: View {
    @ObservedObject var store: Store
    @State private var query = ""
    @State private var confirmClear = false

    private var entries: [HistoryEntry] {
        let all = store.history.reversed()
        return query.isEmpty ? Array(all) : all.filter { $0.text.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        Group {
            if entries.isEmpty {
                ContentUnavailableView(query.isEmpty ? "No transcripts yet" : "No matches",
                                       systemImage: "text.bubble")
            } else {
                List(entries) { entry in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(entry.text).textSelection(.enabled)
                        HStack {
                            Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                            Text(OverlayView.elapsed(entry.duration))
                            Spacer()
                            if let audio = store.audioURL(for: entry) {
                                Button("Show Recording") { NSWorkspace.shared.activateFileViewerSelecting([audio]) }
                            }
                            Button("Copy") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(entry.text, forType: .string)
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .buttonStyle(.borderless)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .searchable(text: $query)
        .toolbar {
            Button("Clear History") { confirmClear = true }
                .disabled(store.history.isEmpty)
        }
        .confirmationDialog("Delete all transcripts?", isPresented: $confirmClear) {
            Button("Delete All", role: .destructive) { store.clearHistory() }
        } message: {
            Text("Recordings stay in the recordings folder until their retention period ends.")
        }
        .frame(minWidth: 480, minHeight: 360)
    }
}

import AppKit
import AVFoundation
import Carbon.HIToolbox

/// Runs one dictation: record, transcribe in a fresh worker, copy, save to history.
final class DictationController: ObservableObject {
    enum Phase { case idle, recording, transcribing }

    @Published private(set) var phase: Phase = .idle

    private let store: Store
    private let engine: Engine
    private let settings: Settings
    private let recorder = Recorder()
    private let overlay = OverlayController()
    private let escapeKey = HotKey(id: 2)
    private var worker: Worker?
    private var file: URL?
    private var startedAt = Date()

    init(store: Store, engine: Engine, settings: Settings) {
        self.store = store
        self.engine = engine
        self.settings = settings
        recorder.onLevel = { [weak self] level in self?.overlay.model.push(level) }
    }

    func toggle() {
        switch phase {
        case .idle: start()
        case .recording: stop()
        case .transcribing: break
        }
    }

    func start() {
        guard phase == .idle else { return }
        guard engine.state == .ready else {
            overlay.flash(engine.state.description, symbol: "hourglass")
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            begin()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async {
                    if granted { self.begin() } else { self.overlay.flash("Microphone access denied", symbol: "mic.slash.fill") }
                }
            }
        default:
            overlay.flash("Allow microphone access in System Settings", symbol: "mic.slash.fill", seconds: 3)
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
        }
    }

    private func begin() {
        guard phase == .idle else { return }
        let url = store.newRecordingURL()
        do {
            try recorder.start(url: url)
        } catch {
            overlay.flash(error.localizedDescription)
            return
        }
        // Start the worker now, so the model loads while the user speaks.
        do {
            worker = try engine.startWorker()
        } catch {
            recorder.stop()
            try? FileManager.default.removeItem(at: url)
            overlay.flash("Cannot start the speech engine")
            return
        }
        file = url
        startedAt = Date()
        phase = .recording
        overlay.showRecording()
        escapeKey.register(keyCode: UInt32(kVK_Escape), modifiers: 0) { [weak self] in self?.cancel() }
    }

    func stop() {
        guard phase == .recording, let file, let worker else { return }
        escapeKey.unregister()
        let duration = recorder.stop()
        if duration < 0.3 {
            cancel()
            return
        }
        phase = .transcribing
        overlay.showTranscribing()
        worker.transcribe(file) { [weak self] result in
            guard let self else { return }
            self.worker = nil
            self.file = nil
            self.phase = .idle
            switch result {
            case .success(let raw):
                let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                if text.isEmpty {
                    self.overlay.flash("No speech detected", symbol: "waveform.slash", seconds: 1.5)
                } else {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    self.store.add(HistoryEntry(date: self.startedAt, text: text, audioFile: file.lastPathComponent, duration: duration))
                    self.overlay.flash("Copied to clipboard", symbol: "checkmark.circle.fill", seconds: 1.2)
                }
            case .failure(let error):
                NSLog("PhononDictate: transcription failed: \(error.localizedDescription)")
                self.overlay.flash("Transcription failed. See worker.log", seconds: 3)
            }
            self.applyRetention()
        }
    }

    /// Stops recording, discards the audio, and kills the worker.
    func cancel() {
        guard phase == .recording else { return }
        escapeKey.unregister()
        recorder.stop()
        worker?.cancel()
        worker = nil
        if let file { try? FileManager.default.removeItem(at: file) }
        file = nil
        phase = .idle
        overlay.hide()
    }

    func applyRetention() {
        store.applyRetention(recordingDays: settings.recordingRetentionDays, historyDays: settings.historyRetentionDays)
    }
}

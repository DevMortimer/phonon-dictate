import Foundation

struct HistoryEntry: Codable, Identifiable, Equatable {
    var id = UUID()
    var date: Date
    var text: String
    /// File name in the recordings folder. The file can be gone after its retention period.
    var audioFile: String?
    var duration: Double
}

/// Recordings and transcript history in ~/Library/Application Support/Phonon Dictate.
final class Store: ObservableObject {
    let root: URL
    let recordingsDir: URL
    private let historyURL: URL

    @Published private(set) var history: [HistoryEntry] = []

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        root = support.appendingPathComponent("Phonon Dictate", isDirectory: true)
        recordingsDir = root.appendingPathComponent("recordings", isDirectory: true)
        historyURL = root.appendingPathComponent("history.json")
        try? FileManager.default.createDirectory(at: recordingsDir, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: historyURL) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            history = (try? decoder.decode([HistoryEntry].self, from: data)) ?? []
        }
    }

    func newRecordingURL() -> URL {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return recordingsDir.appendingPathComponent("\(f.string(from: Date())).wav")
    }

    func audioURL(for entry: HistoryEntry) -> URL? {
        guard let name = entry.audioFile else { return nil }
        let url = recordingsDir.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func add(_ entry: HistoryEntry) {
        history.append(entry)
        save()
    }

    func clearHistory() {
        history.removeAll()
        save()
    }

    /// Deletes recordings and history entries older than their retention period. 0 days keeps forever.
    func applyRetention(recordingDays: Int, historyDays: Int) {
        let now = Date()
        if historyDays > 0 {
            let cutoff = now.addingTimeInterval(-Double(historyDays) * 86_400)
            let kept = history.filter { $0.date >= cutoff }
            if kept.count != history.count {
                history = kept
                save()
            }
        }
        if recordingDays > 0 {
            let cutoff = now.addingTimeInterval(-Double(recordingDays) * 86_400)
            let fm = FileManager.default
            let files = (try? fm.contentsOfDirectory(at: recordingsDir, includingPropertiesForKeys: [.creationDateKey])) ?? []
            for url in files {
                let created = (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? now
                if created < cutoff { try? fm.removeItem(at: url) }
            }
        }
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted]
        guard let data = try? encoder.encode(history) else { return }
        try? data.write(to: historyURL, options: .atomic)
    }
}

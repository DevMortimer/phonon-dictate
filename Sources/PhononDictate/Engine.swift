import Foundation

/// The Python environment that runs Phonon-2, and the one-shot worker processes.
final class Engine: ObservableObject {
    enum State: Equatable {
        case checking
        case installing(String)
        case ready
        case failed(String)

        var description: String {
            switch self {
            case .checking: return "Checking the speech model…"
            case .installing(let step): return step
            case .ready: return "Ready"
            case .failed(let message): return "Setup failed: \(message)"
            }
        }
    }

    @Published private(set) var state: State = .checking

    private let envDir: URL
    private let marker: URL
    private let setupLog: URL
    let workerLog: URL
    private var python: URL { envDir.appendingPathComponent("bin/python") }
    private var workerScript: URL? { Bundle.main.url(forResource: "worker", withExtension: "py") }
    private var requirements: URL? { Bundle.main.url(forResource: "requirements", withExtension: "txt") }

    init(root: URL) {
        envDir = root.appendingPathComponent("python", isDirectory: true)
        marker = envDir.appendingPathComponent(".phonon-dictate-requirements")
        setupLog = root.appendingPathComponent("setup.log")
        workerLog = root.appendingPathComponent("worker.log")
    }

    /// Creates the virtual environment and downloads the model when the pinned requirements changed.
    func setup() {
        guard let requirements, let workerScript, let wanted = try? String(contentsOf: requirements, encoding: .utf8) else {
            state = .failed("The app bundle is missing worker.py or requirements.txt.")
            return
        }
        if (try? String(contentsOf: marker, encoding: .utf8)) == wanted, FileManager.default.isExecutableFile(atPath: python.path) {
            state = .ready
            return
        }
        guard let uv = Engine.findUV() else {
            state = .failed("uv is not installed. Run: brew install uv")
            return
        }
        FileManager.default.createFile(atPath: setupLog.path, contents: nil)
        let steps: [(String, URL, [String])] = [
            ("Creating the Python environment…", uv, ["venv", "--python", "3.12", envDir.path]),
            ("Installing the speech engine…", uv, ["pip", "install", "--python", python.path, "-r", requirements.path]),
            ("Downloading Phonon-2…", python, [workerScript.path, "--prepare"]),
        ]
        let envDir = envDir, marker = marker, setupLog = setupLog
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            try? FileManager.default.removeItem(at: envDir)
            for (label, exe, args) in steps {
                DispatchQueue.main.async { self?.state = .installing(label) }
                let status = Engine.run(exe, args, log: setupLog)
                if status != 0 {
                    DispatchQueue.main.async { self?.state = .failed("\(label) exited with \(status). See \(setupLog.path)") }
                    return
                }
            }
            try? wanted.write(to: marker, atomically: true, encoding: .utf8)
            DispatchQueue.main.async { self?.state = .ready }
        }
    }

    /// Starts a worker. It loads the model at once and waits for an audio path on stdin.
    func startWorker() throws -> Worker {
        guard let workerScript else { throw WorkerError.failed("worker.py is missing.") }
        return try Worker(python: python, script: workerScript, log: workerLog)
    }

    private static func findUV() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = ["/opt/homebrew/bin/uv", "/usr/local/bin/uv", "\(home)/.local/bin/uv", "\(home)/.cargo/bin/uv"]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }.map { URL(fileURLWithPath: $0) }
    }

    private static func run(_ exe: URL, _ args: [String], log: URL) -> Int32 {
        let p = Process()
        p.executableURL = exe
        p.arguments = args
        p.environment = ProcessInfo.processInfo.environment.merging(["HF_HUB_DISABLE_PROGRESS_BARS": "1"]) { $1 }
        guard let handle = try? FileHandle(forWritingTo: log) else { return -1 }
        handle.seekToEndOfFile()
        handle.write(Data("$ \(exe.path) \(args.joined(separator: " "))\n".utf8))
        p.standardOutput = handle
        p.standardError = handle
        do { try p.run() } catch { return -1 }
        p.waitUntilExit()
        try? handle.close()
        return p.terminationStatus
    }
}

enum WorkerError: LocalizedError {
    case failed(String)

    var errorDescription: String? {
        if case .failed(let message) = self { return message }
        return nil
    }
}

/// One Python process for one transcription. The process exit unloads the model.
final class Worker {
    private let process = Process()
    private let stdin = Pipe()
    private let stdout = Pipe()

    init(python: URL, script: URL, log: URL) throws {
        process.executableURL = python
        process.arguments = [script.path]
        process.environment = ProcessInfo.processInfo.environment.merging([
            "HF_HUB_OFFLINE": "1",
            "HF_HUB_DISABLE_PROGRESS_BARS": "1",
            "PYTHONUNBUFFERED": "1",
        ]) { $1 }
        process.standardInput = stdin
        process.standardOutput = stdout
        if !FileManager.default.fileExists(atPath: log.path) {
            FileManager.default.createFile(atPath: log.path, contents: nil)
        }
        if let handle = try? FileHandle(forWritingTo: log) {
            handle.seekToEndOfFile()
            process.standardError = handle
        }
        try process.run()
    }

    /// Sends the audio file to the worker. `completion` runs on the main queue.
    func transcribe(_ file: URL, completion: @escaping (Result<String, Error>) -> Void) {
        // Throws instead of raising when the worker already exited. main.swift ignores SIGPIPE.
        try? stdin.fileHandleForWriting.write(contentsOf: Data((file.path + "\n").utf8))
        try? stdin.fileHandleForWriting.close()
        let process = process, stdout = stdout
        DispatchQueue.global(qos: .userInitiated).async {
            let data = stdout.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let line = String(decoding: data, as: UTF8.self)
                .split(separator: "\n").last.map(String.init) ?? ""
            let json = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any]
            let result: Result<String, Error>
            if let text = json?["text"] as? String {
                result = .success(text)
            } else if let error = json?["error"] as? String {
                result = .failure(WorkerError.failed(error))
            } else {
                result = .failure(WorkerError.failed("The worker exited with status \(process.terminationStatus)."))
            }
            DispatchQueue.main.async { completion(result) }
        }
    }

    func cancel() {
        try? stdin.fileHandleForWriting.close()
        if process.isRunning { process.terminate() }
    }
}

import AVFoundation

enum RecorderError: LocalizedError {
    case noInput
    case converter

    var errorDescription: String? {
        switch self {
        case .noInput: return "No microphone input is available."
        case .converter: return "Cannot convert the microphone format."
        }
    }
}

/// Records the default microphone to a 16 kHz mono 16-bit WAV file and reports the input level.
final class Recorder {
    /// Normalized input level 0...1, called on the main queue about 20 times per second.
    var onLevel: ((Float) -> Void)?

    private let engine = AVAudioEngine()
    private let queue = DispatchQueue(label: "PhononDictate.recorder")
    private let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
    private var file: AVAudioFile?
    private var converter: AVAudioConverter?
    private var frames: AVAudioFramePosition = 0

    func start(url: URL) throws {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw RecorderError.noInput }
        guard let converter = AVAudioConverter(from: format, to: target) else { throw RecorderError.converter }
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        queue.sync {
            self.file = file
            self.converter = converter
            self.frames = 0
        }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.queue.async { self?.process(buffer) }
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            queue.sync { self.file = nil }
            throw error
        }
    }

    /// Stops recording, closes the file, and returns the recorded duration in seconds.
    @discardableResult
    func stop() -> TimeInterval {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        return queue.sync {
            file = nil // closes the file
            converter = nil
            return Double(frames) / target.sampleRate
        }
    }

    private func process(_ buffer: AVAudioPCMBuffer) {
        guard let file, let converter else { return }

        if let data = buffer.floatChannelData, buffer.frameLength > 0 {
            let n = Int(buffer.frameLength)
            var sum: Float = 0
            for i in 0..<n { sum += data[0][i] * data[0][i] }
            let db = 20 * log10(max(sqrt(sum / Float(n)), 1e-7))
            let level = min(max((db + 55) / 45, 0), 1)
            DispatchQueue.main.async { self.onLevel?(level) }
        }

        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * target.sampleRate / buffer.format.sampleRate) + 64
        guard let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return }
        var consumed = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if consumed {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, out.frameLength > 0 else { return }
        do {
            try file.write(from: out)
            frames += AVAudioFramePosition(out.frameLength)
        } catch {
            NSLog("PhononDictate: write failed: \(error)")
        }
    }
}

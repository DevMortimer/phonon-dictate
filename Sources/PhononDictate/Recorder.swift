import Accelerate
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
    /// Voice level and frequency bands for each audio buffer, called on the main queue.
    var onMeter: ((Meter) -> Void)?

    private let engine = AVAudioEngine()
    private let queue = DispatchQueue(label: "PhononDictate.recorder")
    private let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
    private var file: AVAudioFile?
    private var converter: AVAudioConverter?
    private var frames: AVAudioFramePosition = 0
    private let fftSize = 1024
    private lazy var fft = vDSP.FFT(log2n: 10, radix: .radix2, ofType: DSPSplitComplex.self)
    private lazy var window = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized, count: fftSize, isHalfWindow: false)

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
            let meter = measure(UnsafeBufferPointer(start: data[0], count: Int(buffer.frameLength)), sampleRate: buffer.format.sampleRate)
            DispatchQueue.main.async { self.onMeter?(meter) }
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

    /// Loudness, plus how the energy splits between low (80-300 Hz), mid (300-2000 Hz) and high (2-6 kHz) bands.
    private func measure(_ samples: UnsafeBufferPointer<Float>, sampleRate: Double) -> Meter {
        let rms = vDSP.rootMeanSquare(samples)
        let db = 20 * log10(max(rms, 1e-7))
        let level = min(max((db + 55) / 45, 0), 1)
        guard samples.count >= fftSize, let fft else { return Meter(level: level, low: level, mid: level, high: 0) }

        let windowed = vDSP.multiply(Array(samples.suffix(fftSize)), window)
        let half = fftSize / 2
        var real = [Float](repeating: 0, count: half)
        var imag = [Float](repeating: 0, count: half)
        var power = [Float](repeating: 0, count: half)
        real.withUnsafeMutableBufferPointer { re in
            imag.withUnsafeMutableBufferPointer { im in
                var split = DSPSplitComplex(realp: re.baseAddress!, imagp: im.baseAddress!)
                windowed.withUnsafeBytes { vDSP_ctoz($0.bindMemory(to: DSPComplex.self).baseAddress!, 2, &split, 1, vDSP_Length(half)) }
                fft.forward(input: split, output: &split)
                vDSP.squareMagnitudes(split, result: &power)
            }
        }
        let binHz = sampleRate / Double(fftSize)
        func band(_ lo: Double, _ hi: Double) -> Float {
            let a = max(1, Int(lo / binHz)), b = min(half - 1, Int(hi / binHz))
            return a < b ? vDSP.sum(power[a...b]) : 0
        }
        let low = band(80, 300), mid = band(300, 2000), high = band(2000, 6000)
        let total = max(low + mid + high, 1e-12)
        return Meter(level: level,
                     low: level * min(1, (low / total).squareRoot() * 1.2),
                     mid: level * min(1, (mid / total).squareRoot() * 1.2),
                     high: level * min(1, (high / total).squareRoot() * 2.5))
    }
}

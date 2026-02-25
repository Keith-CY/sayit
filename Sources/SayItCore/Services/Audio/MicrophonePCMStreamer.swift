@preconcurrency import AVFoundation
import Foundation

final class MicrophonePCMStreamer: @unchecked Sendable {
    typealias AudioChunkHandler = @Sendable (Data) -> Void

    private let targetSampleRate: Int
    private let channelCount: Int
    private var engine: AVAudioEngine?
    private var converter: AVAudioConverter?
    private var inputFormat: AVAudioFormat?
    private var outputFormat: AVAudioFormat?

    init(sampleRate: Int = 24_000, channelCount: Int = 1) {
        self.targetSampleRate = sampleRate
        self.channelCount = channelCount
    }

    func start(onChunk: @escaping AudioChunkHandler) throws {
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: Double(targetSampleRate),
            channels: AVAudioChannelCount(channelCount),
            interleaved: true
        ) else {
            throw SayItError.unavailable("Unable to create target audio format")
        }

        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            throw SayItError.unavailable("Unable to create audio converter")
        }

        self.engine = engine
        self.converter = converter
        self.inputFormat = inputFormat
        self.outputFormat = outputFormat

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 2048, format: inputFormat) { [weak self] buffer, _ in
            self?.process(buffer: buffer, onChunk: onChunk)
        }

        engine.prepare()
        try engine.start()
    }

    func stop() {
        guard let engine else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        self.engine = nil
        self.converter = nil
        self.inputFormat = nil
        self.outputFormat = nil
    }

    private func process(buffer: AVAudioPCMBuffer, onChunk: @escaping AudioChunkHandler) {
        guard let converter = converter, let inputFormat = inputFormat, let outputFormat = outputFormat else { return }
        let frameRatio = outputFormat.sampleRate / inputFormat.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * frameRatio + 8)
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else { return }

        let didProvideInput = DidProvideInputFlag()
        var conversionError: NSError?
        let status = converter.convert(to: outputBuffer, error: &conversionError) { _, statusPtr in
            if didProvideInput.value {
                statusPtr.pointee = .noDataNow
                return nil
            }
            didProvideInput.value = true
            statusPtr.pointee = .haveData
            return buffer
        }

        guard status != .error, conversionError == nil, let channel = outputBuffer.int16ChannelData else { return }
        let sampleCount = Int(outputBuffer.frameLength)
        guard sampleCount > 0 else { return }
        let byteCount = sampleCount * MemoryLayout<Int16>.size
        let data = Data(bytes: channel[0], count: byteCount)
        onChunk(data)
    }
}

private final class DidProvideInputFlag: @unchecked Sendable {
    var value = false
}

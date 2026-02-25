@preconcurrency import AVFoundation
import Foundation

enum AudioPCM16Converter {
    static func loadMono16kFloatPCM(from fileURL: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: fileURL)
        let sourceFormat = file.processingFormat

        guard
            let targetFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: 16_000,
                channels: 1,
                interleaved: false
            )
        else {
            throw SayItError.unavailable("Failed to create 16k mono target format")
        }

        guard let converter = AVAudioConverter(from: sourceFormat, to: targetFormat) else {
            throw SayItError.unavailable("Failed to create audio converter")
        }

        let sourceFrames = max(1, min(file.length, AVAudioFramePosition(UInt32.max)))
        guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: AVAudioFrameCount(sourceFrames)) else {
            throw SayItError.unavailable("Failed to allocate input audio buffer")
        }
        try file.read(into: inputBuffer)

        let ratio = targetFormat.sampleRate / sourceFormat.sampleRate
        let outputFrameCapacity = AVAudioFrameCount((Double(inputBuffer.frameLength) * ratio).rounded(.up)) + 512
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: max(outputFrameCapacity, 1024)) else {
            throw SayItError.unavailable("Failed to allocate output audio buffer")
        }

        let state = InputState()
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            if state.providedInput {
                outStatus.pointee = .endOfStream
                return nil
            }
            state.providedInput = true
            outStatus.pointee = .haveData
            return inputBuffer
        }

        var pcm: [Float] = []
        var conversionError: NSError?

        while true {
            let status = converter.convert(to: outputBuffer, error: &conversionError, withInputFrom: inputBlock)
            if let conversionError {
                throw SayItError.unavailable("Audio convert error: \(conversionError.localizedDescription)")
            }

            switch status {
            case .haveData:
                guard let channel = outputBuffer.floatChannelData?.pointee else { continue }
                pcm.append(contentsOf: UnsafeBufferPointer(start: channel, count: Int(outputBuffer.frameLength)))
                outputBuffer.frameLength = 0
            case .inputRanDry, .endOfStream:
                return pcm
            case .error:
                throw SayItError.unavailable("Audio convert error")
            @unknown default:
                throw SayItError.unavailable("Unknown audio converter status")
            }
        }
    }
}

private final class InputState: @unchecked Sendable {
    var providedInput = false
}

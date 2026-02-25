@preconcurrency import AVFoundation
import Foundation
import SayItCore

struct MicrophoneSignal: Sendable {
    let level: Float
    let bands: [Float]

    static func zeros(count: Int) -> MicrophoneSignal {
        MicrophoneSignal(level: 0, bands: Array(repeating: 0, count: max(1, count)))
    }
}

final class MicrophoneLevelMonitor: @unchecked Sendable {
    typealias LevelHandler = @MainActor (MicrophoneSignal) -> Void

    private var engine: AVAudioEngine?
    private let stateLock = NSLock()
    private var levelHandler: LevelHandler?
    private var latestSignal: MicrophoneSignal = .zeros(count: 18)
    private var lastEmitUptime: TimeInterval = 0
    private let emitIntervalSec: TimeInterval = 1.0 / 30.0

    func start(onLevel: @escaping LevelHandler) async throws {
        try await ensureMicrophonePermission()
        stop()

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        initializeState(handler: onLevel)

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }
            let signal = Self.computeSignal(from: buffer, bandCount: 18)
            self.enqueue(signal: signal)
        }

        engine.prepare()
        try engine.start()
        self.engine = engine
    }

    func stop() {
        guard let engine else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        self.engine = nil

        resetState()
    }

    private func enqueue(signal: MicrophoneSignal) {
        var shouldEmit = false
        var handler: LevelHandler?
        var snapshot = signal

        stateLock.lock()
        latestSignal = signal
        snapshot = latestSignal
        handler = levelHandler
        let uptime = ProcessInfo.processInfo.systemUptime
        if uptime - lastEmitUptime >= emitIntervalSec {
            lastEmitUptime = uptime
            shouldEmit = true
        }
        stateLock.unlock()

        guard shouldEmit, let handler else { return }
        Task { @MainActor in
            handler(snapshot)
        }
    }

    private func initializeState(handler: @escaping LevelHandler) {
        stateLock.lock()
        defer { stateLock.unlock() }
        levelHandler = handler
        latestSignal = .zeros(count: 18)
        lastEmitUptime = 0
    }

    private func resetState() {
        stateLock.lock()
        defer { stateLock.unlock() }
        levelHandler = nil
        latestSignal = .zeros(count: 18)
        lastEmitUptime = 0
    }

    private static func computeSignal(from buffer: AVAudioPCMBuffer, bandCount: Int) -> MicrophoneSignal {
        guard let channelData = buffer.floatChannelData?[0] else {
            return .zeros(count: bandCount)
        }
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else {
            return .zeros(count: bandCount)
        }

        var sum: Float = 0
        var bandSums = Array(repeating: Float(0), count: max(1, bandCount))
        var bandCounts = Array(repeating: Float(0), count: max(1, bandCount))

        for index in 0..<frameLength {
            let sample = channelData[index]
            sum += sample * sample

            let amplitude = abs(sample)
            let bandIndex = min((index * bandSums.count) / frameLength, bandSums.count - 1)
            bandSums[bandIndex] += amplitude
            bandCounts[bandIndex] += 1
        }

        let rms = sqrt(sum / Float(frameLength))
        let db = 20 * log10(max(rms, 0.000_01))
        let level = normalizedLevel(fromDecibels: db)

        let bands: [Float] = zip(bandSums, bandCounts).map { sum, count in
            guard count > 0 else { return 0 }
            let average = sum / count
            let scaled = min(max(average * 6.5, 0), 1)
            return powf(scaled, 0.72)
        }
        return MicrophoneSignal(level: level, bands: bands)
    }

    private static func normalizedLevel(fromDecibels db: Float) -> Float {
        let minDb: Float = -55
        let clamped = max(min(db, 0), minDb)
        let linear = (clamped - minDb) / -minDb
        return min(max(powf(linear, 1.35), 0), 1)
    }

    private func ensureMicrophonePermission() async throws {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return
        case .notDetermined:
            let granted = await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { access in
                    continuation.resume(returning: access)
                }
            }
            guard granted else {
                throw SayItError.authentication("Microphone permission denied")
            }
        case .restricted, .denied:
            throw SayItError.authentication("Microphone permission is restricted or denied")
        @unknown default:
            throw SayItError.authentication("Unknown microphone authorization status")
        }
    }
}

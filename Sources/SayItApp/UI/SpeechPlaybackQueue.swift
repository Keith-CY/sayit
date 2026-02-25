import AVFoundation
import Foundation
import SayItCore

@MainActor
final class SpeechPlaybackQueue: NSObject, AVAudioPlayerDelegate {
    private var queue: [TTSAudio] = []
    private var player: AVAudioPlayer?
    private let onStateChanged: ((Int) -> Void)?

    init(onStateChanged: ((Int) -> Void)? = nil) {
        self.onStateChanged = onStateChanged
        super.init()
    }

    var pendingCount: Int {
        queue.count + (player == nil ? 0 : 1)
    }

    func enqueue(_ audio: TTSAudio) throws {
        queue.append(audio)
        try playIfNeeded()
        onStateChanged?(pendingCount)
    }

    func clear() {
        queue.removeAll()
        player?.stop()
        player = nil
        onStateChanged?(pendingCount)
    }

    private func playIfNeeded() throws {
        guard player == nil, !queue.isEmpty else { return }
        let next = queue.removeFirst()
        let audioPlayer = try AVAudioPlayer(data: next.data)
        audioPlayer.delegate = self
        audioPlayer.prepareToPlay()
        audioPlayer.play()
        player = audioPlayer
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.player = nil
            try? self.playIfNeeded()
            self.onStateChanged?(self.pendingCount)
        }
    }
}

import Foundation

/// Service that keeps optional media pause/resume behavior during transcription.
/// controlled pause/resume functionality during transcription.
///
/// This service ensures we only pause media if it's currently playing,
/// and only resume if we were the ones who paused it.
@MainActor
final class MediaPlaybackService {
    static let shared = MediaPlaybackService()

    private init() {}

    // MARK: - Public API

    /// Pauses system media playback if something is currently playing.
    ///
    /// - Returns: `true` if we successfully paused playback, `false` if nothing was playing
    ///   or if media control is disabled.
    func pauseIfPlaying() async -> Bool {
        DebugLogger.shared.debug(
            "MediaPlaybackService: Media control disabled; skip pausing playback",
            source: "MediaPlaybackService"
        )
        return false
    }

    /// Resumes media playback only if we were the ones who paused it.
    ///
    /// - Parameter wePaused: `true` if `pauseIfPlaying()` returned `true` for this session.
    func resumeIfWePaused(_ wePaused: Bool) async {
        guard wePaused else {
            DebugLogger.shared.debug(
                "MediaPlaybackService: We didn't pause media, not resuming",
                source: "MediaPlaybackService"
            )
            return
        }

        DebugLogger.shared.info(
            "MediaPlaybackService: Resuming media playback (we paused it)",
            source: "MediaPlaybackService"
        )
        DebugLogger.shared.debug(
            "MediaPlaybackService: Media resume command is disabled",
            source: "MediaPlaybackService"
        )
    }
}

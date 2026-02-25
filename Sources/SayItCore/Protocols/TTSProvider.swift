import Foundation

public protocol TTSProvider: Sendable {
    var id: String { get }
    func synthesize(_ request: TTSRequest) async throws -> TTSAudio
}

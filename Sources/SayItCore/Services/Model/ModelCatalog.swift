import Foundation

public enum LocalModelEngine: String, Codable, Sendable, CaseIterable {
    case whisper
    case parakeet
    case moonshine
}

public struct LocalModelDescriptor: Codable, Sendable, Identifiable {
    public var id: String { "\(engine.rawValue):\(name)" }
    public var engine: LocalModelEngine
    public var name: String
    public var remoteURL: URL
    public var sha256: String
    public var sizeBytes: Int64

    public init(engine: LocalModelEngine, name: String, remoteURL: URL, sha256: String, sizeBytes: Int64) {
        self.engine = engine
        self.name = name
        self.remoteURL = remoteURL
        self.sha256 = sha256
        self.sizeBytes = sizeBytes
    }
}

public enum ModelCatalog {
    public static func defaults() -> [LocalModelDescriptor] {
        [
            LocalModelDescriptor(
                engine: .whisper,
                name: "ggml-medium.bin",
                remoteURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium.bin")!,
                sha256: "",
                sizeBytes: 1_533_763_059
            ),
            LocalModelDescriptor(
                engine: .whisper,
                name: "ggml-small.bin",
                remoteURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin")!,
                sha256: "",
                sizeBytes: 487_601_967
            ),
            LocalModelDescriptor(
                engine: .whisper,
                name: "ggml-base.bin",
                remoteURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin")!,
                sha256: "",
                sizeBytes: 147_951_465
            ),
            LocalModelDescriptor(
                engine: .parakeet,
                name: "parakeet-v3-int8.tar.gz",
                remoteURL: URL(string: "https://blob.handy.computer/parakeet-v3-int8.tar.gz")!,
                sha256: "",
                sizeBytes: 478_517_071
            ),
            LocalModelDescriptor(
                engine: .moonshine,
                name: "moonshine-base.tar.gz",
                remoteURL: URL(string: "https://blob.handy.computer/moonshine-base.tar.gz")!,
                sha256: "",
                sizeBytes: 57_901_034
            )
        ]
    }
}

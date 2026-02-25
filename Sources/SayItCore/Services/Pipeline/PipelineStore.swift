import Foundation

public final class PipelineStore {
    private let url: URL

    public init(url: URL? = nil) {
        self.url = url ?? Self.defaultURL()
    }

    public static func defaultURL() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let folder = appSupport.appendingPathComponent("SayIt", isDirectory: true)
        return folder.appendingPathComponent("pipelines.json")
    }

    public func load() throws -> [TextPipeline] {
        let fileManager = FileManager.default
        let folder = url.deletingLastPathComponent()
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)

        guard fileManager.fileExists(atPath: url.path) else {
            let defaults = DefaultPipelines.all()
            try save(defaults)
            return defaults
        }

        let data = try Data(contentsOf: url)
        if data.isEmpty {
            let defaults = DefaultPipelines.all()
            try save(defaults)
            return defaults
        }

        if let pipelines = try? JSONDecoder().decode([TextPipeline].self, from: data), !pipelines.isEmpty {
            return pipelines
        }

        if let document = try? JSONDecoder().decode(PipelineDocument.self, from: data), !document.pipelines.isEmpty {
            return document.pipelines
        }

        let defaults = DefaultPipelines.all()
        try save(defaults)
        return defaults
    }

    public func save(_ pipelines: [TextPipeline]) throws {
        let fileManager = FileManager.default
        let folder = url.deletingLastPathComponent()
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        let data = try JSONEncoder.pretty.encode(pipelines)
        try data.write(to: url, options: .atomic)
    }

    public func upsert(_ pipeline: TextPipeline) throws {
        var pipelines = try load()
        if let index = pipelines.firstIndex(where: { $0.id == pipeline.id }) {
            pipelines[index] = pipeline
        } else {
            pipelines.append(pipeline)
        }
        try save(pipelines)
    }

    public func remove(id: UUID) throws {
        var pipelines = try load()
        pipelines.removeAll { $0.id == id }
        try save(pipelines)
    }

    public func find(id: UUID?) throws -> TextPipeline? {
        guard let id else { return nil }
        return try load().first(where: { $0.id == id })
    }

    public func path() -> URL {
        url
    }
}

private struct PipelineDocument: Codable {
    let pipelines: [TextPipeline]
}

private extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

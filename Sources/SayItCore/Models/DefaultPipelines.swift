import Foundation

public enum DefaultPipelines {
    public static let cleanID = UUID(uuidString: "7BD1D3B8-2545-4A67-86E1-D7E24299B701")!
    public static let codeCommentID = UUID(uuidString: "963A52DA-CF53-4C9D-B2D2-B4C8BCF8D9C8")!

    public static func clean() -> TextPipeline {
        TextPipeline(
            id: cleanID,
            name: "Clean Transcript",
            stages: [
                PipelineStage(type: .fillerRemoval),
                PipelineStage(type: .whitespaceNormalize),
                PipelineStage(type: .smartPunctuation)
            ]
        )
    }

    public static func codeComment(style: String = "swift") -> TextPipeline {
        TextPipeline(
            id: style == "swift" ? codeCommentID : UUID(),
            name: "Code Comment Template",
            stages: [
                PipelineStage(type: .fillerRemoval),
                PipelineStage(type: .whitespaceNormalize),
                PipelineStage(type: .codeCommentTemplate, config: ["style": style])
            ]
        )
    }

    public static func all() -> [TextPipeline] {
        [clean(), codeComment()]
    }
}

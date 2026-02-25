import Foundation

public protocol RefineProvider: Sendable {
    var id: String { get }
    func refine(_ request: RefineRequest) async throws -> RefineResult
}

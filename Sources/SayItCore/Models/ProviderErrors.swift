import Foundation

public struct ProviderHTTPError: Error, Sendable {
    public var providerID: String
    public var statusCode: Int
    public var message: String

    public init(providerID: String, statusCode: Int, message: String) {
        self.providerID = providerID
        self.statusCode = statusCode
        self.message = message
    }
}

public struct ProviderTimeoutError: Error, Sendable {
    public var providerID: String
    public var message: String

    public init(providerID: String, message: String = "timeout") {
        self.providerID = providerID
        self.message = message
    }
}

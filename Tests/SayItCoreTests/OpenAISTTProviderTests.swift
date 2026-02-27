import Foundation
@testable import SayItCore
import XCTest

final class OpenAISTTProviderTests: XCTestCase {
    func testNormalizedChatGPTBaseURLFallsBackToDefault() {
        XCTAssertEqual(
            OpenAISTTProvider.normalizedChatGPTBaseURL(from: nil).absoluteString,
            "https://chatgpt.com/backend-api"
        )
    }

    func testNormalizedChatGPTBaseURLAddsBackendAPIWhenMissing() {
        XCTAssertEqual(
            OpenAISTTProvider.normalizedChatGPTBaseURL(from: "https://chatgpt.com").absoluteString,
            "https://chatgpt.com/backend-api"
        )

        XCTAssertEqual(
            OpenAISTTProvider.normalizedChatGPTBaseURL(from: "https://chat.openai.com/").absoluteString,
            "https://chat.openai.com/backend-api"
        )
    }

    func testNormalizedChatGPTBaseURLKeepsExistingBackendAPI() {
        XCTAssertEqual(
            OpenAISTTProvider.normalizedChatGPTBaseURL(from: "https://chatgpt.com/backend-api").absoluteString,
            "https://chatgpt.com/backend-api"
        )
    }

    func testChatGPTTranscribeURLAppendsEndpoint() {
        XCTAssertEqual(
            OpenAISTTProvider.chatGPTTranscribeURL(baseURL: "https://chatgpt.com/backend-api").absoluteString,
            "https://chatgpt.com/backend-api/transcribe"
        )
    }
}

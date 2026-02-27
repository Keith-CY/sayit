import Foundation
@testable import SayItCore
import XCTest

final class ModelCatalogTests: XCTestCase {
    func testDefaultsIncludeWhisperAndParakeet() {
        let descriptors = ModelCatalog.defaults()

        XCTAssertFalse(descriptors.isEmpty)

        let names = Set(descriptors.map(\.name))
        XCTAssertTrue(names.contains("ggml-small.bin"))
        XCTAssertTrue(names.contains("ggml-base.bin"))
        XCTAssertTrue(names.contains("parakeet-v3-int8.tar.gz"))

        let engines = Set(descriptors.map(\.engine))
        XCTAssertTrue(engines.contains(.whisper))
        XCTAssertTrue(engines.contains(.parakeet))
    }

    func testDescriptorIDsAreUnique() {
        let descriptors = ModelCatalog.defaults()
        let ids = descriptors.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
    }
}

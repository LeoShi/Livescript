import XCTest
@testable import LivescriptCore

final class ModelStoragePathsTests: XCTestCase {
    func testDefaultModelsDirectoryUsesWorkspaceModels() {
        let path = ModelStoragePaths.defaultModelsDirectory
        XCTAssertTrue(path.hasSuffix("/workspace/models"))
        XCTAssertFalse(path.contains("~"))
    }

    func testDefaultSenseVoiceDirectoryIsNestedUnderModelsRoot() {
        let senseVoice = ModelStoragePaths.defaultSenseVoiceDirectory
        XCTAssertTrue(senseVoice.hasSuffix("/workspace/models/sensevoice"))
    }
}

import XCTest
@testable import Core

final class CloudWatcherTests: XCTestCase {
    @MainActor
    func testNothingToWatchOutsideICloud() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("core-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try FileStore.create(at: root, owner: "me")
        XCTAssertNil(CloudWatcher(store: store) {})
    }
}

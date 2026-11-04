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

    func testStateCountsMediaOnly() {
        let state = CloudState([
            .init(isMedia: false, uploaded: false, downloaded: true),                     // an event file, still going up
            .init(isMedia: true, uploaded: false, downloaded: true),                      // a photo written here
            .init(isMedia: true, uploaded: false, downloaded: true, trouble: "Not enough storage"),
            .init(isMedia: true, uploaded: true, downloaded: false),                      // a photo from the other device
            .init(isMedia: true, uploaded: true, downloaded: true),
        ])
        XCTAssertEqual(state, CloudState(media: 4, leaving: 2, arriving: 1, trouble: "Not enough storage"))
        XCTAssertFalse(state.settled)
        XCTAssertTrue(CloudState([.init(isMedia: true, uploaded: true, downloaded: true)]).settled)
        XCTAssertTrue(CloudState([]).settled)
    }
}

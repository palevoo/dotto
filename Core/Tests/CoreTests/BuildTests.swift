import XCTest
@testable import Core

/// What an app says of the build it is, read from what `App/Scripts/stamp.sh` put in its
/// Info.plist.
final class BuildTests: XCTestCase {
    func testACommitIsSaidWithAPlusWhenTheTreeHadChanges() {
        XCTAssertEqual(Build.commit(in: ["DottoCommit": "2176dbd", "DottoChanged": "no"]), "2176dbd")
        XCTAssertEqual(Build.commit(in: ["DottoCommit": "2176dbd", "DottoChanged": "yes"]), "2176dbd+")
        XCTAssertNil(Build.commit(in: [:]))
    }

    func testABuildNumberIsTheMomentOfItsCommit() throws {
        let moment = try XCTUnwrap(Build.moment(of: "202611151445"))
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let parts = utc.dateComponents([.year, .month, .day, .hour, .minute], from: moment)
        XCTAssertEqual([parts.year, parts.month, parts.day, parts.hour, parts.minute], [2026, 11, 15, 14, 45])
        // Outside a git checkout the number stays as the project set it, and names no moment.
        XCTAssertNil(Build.moment(of: "1"))
        XCTAssertNil(Build.moment(of: nil))
    }
}

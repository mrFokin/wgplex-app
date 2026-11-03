import XCTest
@testable import WgplexKit

final class VersionTests: XCTestCase {
    func testVersionIsSet() {
        XCTAssertFalse(appVersion.isEmpty)
    }
}

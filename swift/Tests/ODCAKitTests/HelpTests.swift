import XCTest
@testable import ODCAKit

/// PT-35: the help text is the shared golden copy, byte for byte (R-U9).
final class HelpTests: XCTestCase {
    func testHelpTextMatchesTheSharedCopy() throws {
        let file = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("conformance/help.txt")
        XCTAssertEqual(helpText, try String(contentsOf: file, encoding: .utf8))
        XCTAssertTrue(helpText.hasSuffix("\n"))
    }
}

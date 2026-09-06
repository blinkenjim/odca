import XCTest
@testable import ODCAKit

/// PT-35: the help texts are the shared golden copies, byte for byte (R-U9).
final class HelpTests: XCTestCase {
    func conformance(_ name: String) throws -> String {
        let file = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("conformance/\(name)")
        return try String(contentsOf: file, encoding: .utf8)
    }

    func testHelpTextsMatchTheSharedCopies() throws {
        XCTAssertEqual(helpOdca, try conformance("help-odca.txt"))
        XCTAssertEqual(helpOdcaSelect, try conformance("help-odca-select.txt"))
        XCTAssertTrue(helpOdca.hasSuffix("\n") && helpOdcaSelect.hasSuffix("\n"))
    }
}

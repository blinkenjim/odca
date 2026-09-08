import XCTest
@testable import ODCAKit

/// Play scripts (TESTS.md layer 1 script cases and PT-38; REQTS R-X7, R-X1).
final class ShowTests: XCTestCase {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    var cases: URL { root.appendingPathComponent("conformance/scripts") }
    let pair = Pair(rule: String(repeating: "0", count: 20), colorset: "ODCA default",
                    colors: ["#121218", "#EBEBE1", "#FFA136", "#409CFF"])

    func testScriptCasesMatchTheGoldenOutput() throws {  // layer 1: the parser's JSON, byte for byte
        let names = try FileManager.default.contentsOfDirectory(atPath: cases.path)
            .filter { $0.hasSuffix(".play") }.map { String($0.dropLast(5)) }.sorted()
        XCTAssertGreaterThan(names.count, 10)
        for name in names {
            let text = try String(contentsOf: cases.appendingPathComponent("\(name).play"), encoding: .utf8)
            let golden = try String(contentsOf: cases.appendingPathComponent("\(name).json"), encoding: .utf8)
            XCTAssertEqual(Show.parseJSON(text) + "\n", golden, name)
        }
    }

    func testTheGeneratedParserIsTheSameOnBothSides() throws {  // the two checked-in copies of script/regen's output
        let ours = root.appendingPathComponent("swift/Sources/CShow")
        let theirs = root.appendingPathComponent("python/odca/cshow")
        for name in ["show.lex.c", "show.lex.h", "show.tab.c", "show.tab.h", "show_internal.h", "include/show.h"] {
            XCTAssertEqual(try Data(contentsOf: ours.appendingPathComponent(name)),
                           try Data(contentsOf: theirs.appendingPathComponent(name)), name)
        }
    }

    func testParseGivesStatementsOrAPositionedError() throws {  // PT-38, R-X7
        XCTAssertEqual(try Show.parse("import a.odca\nplay\n"),
                       [.import(line: 1, file: "a.odca"), .play(line: 2)])
        XCTAssertEqual(try Show.parse("shuffle\n"), [.shuffle(line: 1)])
        XCTAssertEqual(try Show.parse("# only a comment"), [])
        XCTAssertThrowsError(try Show.parse("import a.odca\nplay\nplay\n")) { e in
            XCTAssertEqual(e as? ShowError, ShowError("3:1: play given twice"))
        }
        XCTAssertThrowsError(try Show.parse("import a.odca\nplay\nshuffle\n")) { e in
            XCTAssertEqual(e as? ShowError, ShowError("3:1: shuffle after play"))
        }
    }

    func testAScriptPlaysWhatItImports() throws {  // PT-38, R-X7
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("odca-show-\(UUID().uuidString)")
        let sub = dir.appendingPathComponent("sub")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        Store.saveOdcaFile([pair], to: dir.appendingPathComponent("one.odca"))
        Store.saveOdcaFile([pair, pair], to: sub.appendingPathComponent("two pairs.odca"))
        let scriptURL = sub.appendingPathComponent("show.play")
        func write(_ text: String) throws { try text.write(to: scriptURL, atomically: true, encoding: .utf8) }
        func script(_ text: String) throws -> (pairs: [Pair], shuffle: Bool) {
            try write(text)
            return try Show.loadScript(scriptURL)
        }
        var loaded = try script("import ../one.odca   # relative to the script\nimport \"two pairs.odca\"\nplay\n")
        XCTAssertEqual(loaded.pairs, [pair, pair, pair])
        XCTAssertFalse(loaded.shuffle)
        loaded = try script("import ../one.odca\nshuffle\n")  // R-X7: the pairs shuffled per pass
        XCTAssertEqual(loaded.pairs, [pair])
        XCTAssertTrue(loaded.shuffle)
        loaded = try script("import ../one.odca\n")  // imports without play: nothing plays
        XCTAssertEqual(loaded.pairs, [])
        loaded = try script("shuffle\n")  // a play word without imports: nothing to play
        XCTAssertEqual(loaded.pairs, [])
        func failure(_ text: String) throws -> String? {
            try write(text)
            do { _ = try Show.loadScript(scriptURL) } catch let e as ShowError { return e.description }
            return nil
        }
        XCTAssertEqual(try failure("import gone.odca\nplay\n"), "\(scriptURL.path):1: cannot read gone.odca")
        try "hello\n".write(to: sub.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)
        XCTAssertEqual(try failure("\n\nimport notes.txt\nplay\n"), "\(scriptURL.path):3: notes.txt is not an odca file")
        XCTAssertEqual(try failure("import ../one.odca\nshuffle\nimport ../one.odca\n"), "\(scriptURL.path):3:1: import after shuffle")
        let missing = dir.appendingPathComponent("missing.play")
        XCTAssertThrowsError(try Show.loadScript(missing)) { e in
            XCTAssertEqual(e as? ShowError, ShowError("\(missing.path): cannot read"))
        }
    }

    func testTheShowIsOneSegmentPerFile() throws {  // PT-38, R-X1
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("odca-show-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        Store.saveOdcaFile([pair], to: dir.appendingPathComponent("one.odca"))
        let script = dir.appendingPathComponent("show.play")
        try "import one.odca\nimport one.odca\nplay\n".write(to: script, atomically: true, encoding: .utf8)
        let empty = dir.appendingPathComponent("empty.odca")
        try "{\"pairs\": []}".write(to: empty, atomically: true, encoding: .utf8)
        let shuffled = dir.appendingPathComponent("shuffled.play")
        try "import one.odca\nshuffle\n".write(to: shuffled, atomically: true, encoding: .utf8)
        let show = try Show.load([script, dir.appendingPathComponent("one.odca"), empty, shuffled])
        XCTAssertEqual(show, [Segment(file: "show.play", pairs: [pair, pair]),  // a script: what it plays
                              Segment(file: "one.odca", pairs: [pair]),  // an odca file: import it, play it
                              Segment(file: "empty.odca", pairs: []),
                              Segment(file: "shuffled.play", pairs: [pair], shuffle: true)])  // R-X7
        let other = dir.appendingPathComponent("show.txt")
        try "import one.odca\nplay\n".write(to: other, atomically: true, encoding: .utf8)
        XCTAssertEqual(try Show.load([other])[0].pairs, [pair])  // any other extension is a script
        XCTAssertThrowsError(try Show.load([dir.appendingPathComponent("missing.odca")]))
    }
}

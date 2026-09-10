import XCTest
@testable import ODCAKit

/// odca-evolve (TESTS.md PT-40, PT-41, PT-43; REQTS section 4e, R-P3).
final class EvolveTests: XCTestCase {
    let kills3 = try! Rule(states: [3] + [UInt8](repeating: 1, count: 19))  // a 3 survives only between 3s
    let allZero = try! Rule(id: String(repeating: "0", count: 20))

    func seed(_ text: String, _ generations: Int, _ end: String = "state 3 extinct") -> Seed {
        Seed(row: text.map { UInt8($0.wholeNumberValue!) }, generations: generations, end: end)
    }

    func scratch() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("odca-evolve-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func testLifetimeStopsAtExtinctionOrTheCapOrWhenAsked() {  // PT-40, R-E2
        let block = seed("3333333311111111", 0).row
        XCTAssertEqual(Evolve.lifetime(rule: kills3, row: block, cap: 100), seed("3333333311111111", 4))
        XCTAssertEqual(Evolve.lifetime(rule: kills3, row: block, cap: 3), seed("3333333311111111", 3, "survived"))
        XCTAssertEqual(Evolve.lifetime(rule: allZero, row: seed("012301230123", 0).row, cap: 40)?.end, "survived")
        var looks = 0
        let abandoned = Evolve.lifetime(rule: allZero, row: seed("012301230123", 0).row, cap: 1_000_000) {
            looks += 1
            return true
        }
        XCTAssertNil(abandoned)  // a row abandoned at the first look
        XCTAssertEqual(looks, 1)
        XCTAssertNil(Evolve.lifetime(rule: kills3, row: [3, 1], cap: 10))  // narrower than any row
    }

    func testMergeAndRankKeepTheLongestTen() {  // PT-41, R-E3
        let a = (0..<12).map { n -> Seed in  // twelve distinct rows: n in binary, 0 -> 1, 1 -> 3
            let bits = String(n, radix: 2)
            let text = String(repeating: "1", count: 8 - bits.count) + bits.map { $0 == "0" ? "1" : "3" }.joined()
            return seed(text, n * 10)
        }
        let merged = Evolve.merge(a)
        XCTAssertEqual(merged.count, Evolve.keep)
        XCTAssertEqual(merged.map(\.generations), [110, 100, 90, 80, 70, 60, 50, 40, 30, 20])  // longest first
        XCTAssertEqual(Evolve.merge(merged, merged), merged)  // identical rows once
        let tie = [seed("11111113", 5), seed("11111131", 5)]
        XCTAssertEqual(Evolve.merge(tie.reversed()).map(\.rowText), ["11111113", "11111131"])  // ties by row
        XCTAssertEqual(Evolve.rank(of: seed("33333333", 200), among: merged), 0)  // would lead
        XCTAssertEqual(Evolve.rank(of: seed("33333333", 55), among: merged), 6)  // between 60 and 50
        XCTAssertNil(Evolve.rank(of: seed("33333333", 20), among: merged))  // equal to the shortest: not longer
        XCTAssertNil(Evolve.rank(of: seed("33333333", 10), among: merged))
        XCTAssertEqual(Evolve.rank(of: seed("33333333", 10), among: Array(merged.prefix(9))), 9)  // room for a tenth
        XCTAssertNil(Evolve.rank(of: merged[3], among: merged))  // already there
        let byRule: Seeds = ["r": [8: [seed("11111111", 1)]]]
        let more: Seeds = ["r": [8: [seed("33333333", 9)], 9: [seed("111111111", 2)]], "s": [8: [seed("13131313", 3)]]]
        let both = Evolve.merge(byRule, more)
        XCTAssertEqual(both["r"]?[8]?.map(\.generations), [9, 1])
        XCTAssertEqual(both["r"]?[9]?.count, 1)
        XCTAssertEqual(both["s"]?[8]?.count, 1)
    }

    func testSearchKeepsTheLongestTenAndReportsEachJoin() {  // PT-41, R-E2, R-E3, R-E4
        let search = SeedSearch(rule: kills3, cells: 12, cap: 50, workers: 2, kept: [seed("333333333333", 6, "survived")])
        var reported: [(Seed, Int)] = []
        let lock = NSLock()
        search.onKept = { seed, rank in lock.lock(); reported.append((seed, rank)); lock.unlock() }
        var ticks = 0
        let kept = search.run(until: Date().addingTimeInterval(1.5)) { remaining in
            ticks += 1
            XCTAssertLessThanOrEqual(remaining, 1.5)
        }
        XCTAssertGreaterThan(search.tried, 10)  // twelve cells die fast: thousands of rows in a second
        XCTAssertGreaterThanOrEqual(ticks, 1)
        XCTAssertLessThanOrEqual(kept.count, Evolve.keep)
        XCTAssertEqual(kept.map(\.generations), kept.map(\.generations).sorted(by: >))  // longest first
        XCTAssertEqual(kept.first?.rowText, "333333333333")  // the seed already in the file stays on top
        XCTAssertEqual(Set(kept.map(\.rowText)).count, kept.count)  // no row twice
        for (seed, rank) in reported {  // every join reported with a rank inside the ten
            XCTAssertTrue((1...Evolve.keep).contains(rank))
            XCTAssertEqual(seed.row.count, 12)
            XCTAssertTrue(seed.end.hasSuffix("extinct") || seed.end == "survived")
        }
        XCTAssertTrue(reported.contains { $0.0.row == kept.last!.row })  // the last of the ten arrived by a join
        XCTAssertTrue(search.stopped)
        // stop() ends a run early, and a row of immortals (all-zero never goes extinct) is abandoned, not waited for.
        let immortal = SeedSearch(rule: allZero, cells: 12, cap: 100_000_000, workers: 2)
        let started = Date()
        let ended = immortal.run(until: Date().addingTimeInterval(30)) { _ in immortal.stop() }
        XCTAssertLessThan(Date().timeIntervalSince(started), 5)
        XCTAssertEqual(ended, [])  // nothing finished, nothing kept
    }

    func testSeedsRoundTripAndLayout() throws {  // PT-43, R-P3
        let dir = try scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("pairs.odca")
        let pair = Pair(name: "pair-0000", rule: kills3.id, colorset: "ODCA default",
                        colors: ["#121218", "#EBEBE1", "#FFA136", "#409CFF"])
        let seeds: Seeds = [kills3.id: [8: [seed("31111111", 1), seed("33331111", 3)]],
                            allZero.id: [8: [seed("01230123", 50, "survived")]]]
        Store.saveOdcaFile([pair], seeds: seeds, to: file)
        // What Python's json.dumps(indent=1) writes for the same content, byte for byte.
        let reference = """
{
 "pairs": [
  {
   "name": "pair-0000",
   "rule": "31111111111111111111",
   "colorset": "ODCA default",
   "colors": [
    "#121218",
    "#EBEBE1",
    "#FFA136",
    "#409CFF"
   ]
  }
 ],
 "seeds": {
  "00000000000000000000": {
   "8": [
    {
     "row": "01230123",
     "generations": 50,
     "end": "survived"
    }
   ]
  },
  "31111111111111111111": {
   "8": [
    {
     "row": "33331111",
     "generations": 3,
     "end": "state 3 extinct"
    },
    {
     "row": "31111111",
     "generations": 1,
     "end": "state 3 extinct"
    }
   ]
  }
 }
}

"""
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), reference)
        XCTAssertEqual(Store.loadOdcaFile(file), [pair])
        let loaded = Store.loadSeeds(file)
        XCTAssertEqual(loaded[kills3.id]?[8], [seed("33331111", 3), seed("31111111", 1)])  // longest first
        XCTAssertEqual(loaded[allZero.id]?[8], [seed("01230123", 50, "survived")])
        // odca-select's writer carries the section through untouched.
        Store.saveOdcaFile([pair, pair], to: file)
        XCTAssertEqual(Store.loadSeeds(file), loaded)
        XCTAssertEqual(Store.loadOdcaFile(file)?.count, 2)
        // No seeds: no section, so files without any are written as before.
        Store.saveOdcaFile([pair], seeds: [:], to: file)
        XCTAssertFalse(try String(contentsOf: file, encoding: .utf8).contains("seeds"))
        XCTAssertEqual(Store.loadSeeds(file), [:])
        // Malformed entries are skipped: a row of the wrong width, a bad digit, a width below the minimum, a bad rule.
        try """
        {"pairs": [], "seeds": {"\(kills3.id)": {"8": [{"row": "3111111", "generations": 1, "end": "x"},
         {"row": "3111111a", "generations": 1, "end": "x"}, {"row": "31111111", "generations": 2, "end": "state 3 extinct"}],
         "2": [{"row": "31", "generations": 1, "end": "x"}]}, "nonsense": {"8": []}}}
        """.write(to: file, atomically: true, encoding: .utf8)
        XCTAssertEqual(Store.loadSeeds(file), [kills3.id: [8: [seed("31111111", 2)]]])
    }

    func testClocksReadHoursMinutesSeconds() {  // PT-41, R-E4, R-O16
        XCTAssertEqual(Evolve.hms(0), "00:00:00")
        XCTAssertEqual(Evolve.hms(0.2), "00:00:01")  // rounded up: a second left until it is gone
        XCTAssertEqual(Evolve.hms(59.5), "00:01:00")
        XCTAssertEqual(Evolve.hms(4 * 3600 + 5 * 60 + 6), "04:05:06")
        XCTAssertEqual(Evolve.hms(-3), "00:00:00")
        var parts = DateComponents()
        parts.year = 2026; parts.month = 9; parts.day = 9; parts.hour = 13; parts.minute = 7; parts.second = 9
        XCTAssertEqual(Evolve.timeOfDay(Calendar.current.date(from: parts)!), "13:07:09")
    }
}

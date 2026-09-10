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
        // Under the all-zero rule every row is all zeros from generation 1: a
        // period-1 cycle, confirmed at generation 2 (R-E2, Brent's).
        XCTAssertEqual(Evolve.lifetime(rule: allZero, row: seed("012301230123", 0).row, cap: 40),
                       seed("012301230123", 2, "repeating (period 1)"))
        XCTAssertEqual(Evolve.lifetime(rule: allZero, row: seed("012301230123", 0).row, cap: 1)?.end, "survived")  // capped first
        var looks = 0
        // A block of 4000 3s in 8000 cells under kills3 loses two a generation
        // and changes every generation: alive and aperiodic past the first look.
        let wide = [UInt8](repeating: 1, count: 2000) + [UInt8](repeating: 3, count: 4000) + [UInt8](repeating: 1, count: 2000)
        let abandoned = Evolve.lifetime(rule: kills3, row: wide, cap: 1_000_000) {
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

    func testTheClockReadsHoursMinutesSeconds() {  // PT-41, R-E4, R-O16
        XCTAssertEqual(Evolve.hms(0), "00:00:00")
        XCTAssertEqual(Evolve.hms(0.2), "00:00:01")  // rounded up: a second left until it is gone
        XCTAssertEqual(Evolve.hms(59.5), "00:01:00")
        XCTAssertEqual(Evolve.hms(4 * 3600 + 5 * 60 + 6), "04:05:06")
        XCTAssertEqual(Evolve.hms(-3), "00:00:00")  // a line printed just past the deadline
    }

    func testParityGivesUpTheTurnOfARuleFarAhead() {  // PT-46, R-E5
        func seeds(_ lengths: [Int]) -> [Seed] { lengths.map { Seed(row: [UInt8](repeating: 0, count: 8), generations: $0, end: "x") } }
        let a = "a", b = "b", c = "c", rules = [a, b, c]
        var all: Seeds = [a: [8: seeds([5000, 4000, 3000])], b: [8: seeds([2000, 1500])], c: [8: seeds([100_000])]]
        // a: shortest 3000 × 0.9 = 2700 outlives b's longest 2000: a gives up its
        // turn, whatever c holds (a survivor, say) — the rule furthest behind decides.
        XCTAssertEqual(Evolve.givesUpTurn(rule: a, width: 8, seeds: all, rules: rules)?.shortest, 3000)
        XCTAssertEqual(Evolve.givesUpTurn(rule: a, width: 8, seeds: all, rules: rules)?.longest, 2000)
        XCTAssertEqual(Evolve.givesUpTurn(rule: c, width: 8, seeds: all, rules: rules)?.longest, 2000)  // c too
        XCTAssertNil(Evolve.givesUpTurn(rule: b, width: 8, seeds: all, rules: rules))  // furthest behind: runs
        all[c] = nil  // c gone (a stray seed of a rule not in the file does not count either)
        XCTAssertNotNil(Evolve.givesUpTurn(rule: a, width: 8, seeds: all, rules: rules))
        XCTAssertNil(Evolve.givesUpTurn(rule: c, width: 8, seeds: all, rules: rules))  // no seeds: runs
        all[a] = [8: seeds([2222, 2221])]  // 2221 × 0.9 = 1998.9 < 2000: not far enough ahead
        XCTAssertNil(Evolve.givesUpTurn(rule: a, width: 8, seeds: all, rules: rules))
        all[a] = [8: seeds([2223])]  // 2000.7 > 2000: gives up, one seed counting as its shortest
        XCTAssertNotNil(Evolve.givesUpTurn(rule: a, width: 8, seeds: all, rules: rules))
        XCTAssertNil(Evolve.givesUpTurn(rule: a, width: 9, seeds: all, rules: rules))  // another width: no seeds there
        XCTAssertNil(Evolve.givesUpTurn(rule: a, width: 8, seeds: [a: [8: seeds([9])]], rules: rules))  // no other rule has seeds
        let stray: Seeds = [a: [8: seeds([100])], "z": [8: seeds([5000])]]  // z is not in the file
        XCTAssertNil(Evolve.givesUpTurn(rule: a, width: 8, seeds: stray, rules: [a, b]))
    }

    func testParityPlanSkipsAtMostTheLimitFurthestAhead() {  // PT-46, R-E5
        func seeds(_ lengths: [Int]) -> [Seed] { lengths.map { Seed(row: [UInt8](repeating: 0, count: 8), generations: $0, end: "x") } }
        let rules = ["a", "b", "c", "d", "e"]
        let all: Seeds = ["a": [8: seeds([5000, 3000])], "b": [8: seeds([400, 300])], "c": [8: seeds([9000, 4000])],
                          "d": [8: seeds([4000, 3000])], "e": [8: seeds([4500, 4000])]]  // b, at 400, is furthest behind
        var plan = Evolve.parityPlan(rules: rules, width: 8, seeds: all, limit: 0)
        XCTAssertEqual(Set(plan.skips.keys), ["a", "c", "d", "e"])  // every rule ahead of b; no limit
        XCTAssertEqual(plan.ahead, 4)
        XCTAssertEqual(plan.skips["a"]?.longest, 400)
        plan = Evolve.parityPlan(rules: rules, width: 8, seeds: all, limit: 2)
        XCTAssertEqual(Set(plan.skips.keys), ["c", "e"])  // the two furthest ahead by shortest lifetime: c (4000), e (4000)...
        XCTAssertEqual(plan.ahead, 4)
        plan = Evolve.parityPlan(rules: rules, width: 8, seeds: all, limit: 3)
        XCTAssertEqual(Set(plan.skips.keys), ["c", "e", "a"])  // then a and d tie at 3000: a first in file order
        plan = Evolve.parityPlan(rules: rules, width: 8, seeds: all, limit: 10)
        XCTAssertEqual(plan.skips.count, 4)  // a limit above the qualifiers changes nothing
        XCTAssertTrue(Evolve.parityPlan(rules: rules, width: 8, seeds: ["b": [8: seeds([400])]], limit: 0).skips.isEmpty)  // one rule with seeds
    }

    func testTenSurvivorsEndTheTurn() {  // PT-41, R-E3
        func seeds(_ ends: [String]) -> [Seed] {
            ends.enumerated().map { Seed(row: [UInt8](repeating: UInt8($0.offset % 4), count: 8) + [UInt8(($0.offset / 4) % 4)], generations: 100, end: $0.element) }
        }
        XCTAssertTrue(Evolve.allSurvived(seeds(Array(repeating: Seed.survived, count: 10))))
        XCTAssertFalse(Evolve.allSurvived(seeds(Array(repeating: Seed.survived, count: 9))))  // not yet ten
        XCTAssertFalse(Evolve.allSurvived(seeds(Array(repeating: Seed.survived, count: 9) + ["state 1 extinct"])))
        XCTAssertFalse(Evolve.allSurvived([]))
    }
}

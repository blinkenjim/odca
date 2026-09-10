import Foundation
import XCTest

@testable import ODCAKit

/// Layer 2 of TESTS.md: property tests PT-1..PT-8, PT-11, PT-12.
final class PropertyTests: XCTestCase {
    func tempStore() throws -> Store {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("odca-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return Store(
            stateDir: dir.appendingPathComponent("state"),
            libraryFile: dir.appendingPathComponent("library.json"),
            candidatePalettesFile: dir.appendingPathComponent("candidates.json"))
    }

    // PT-1: mutation changes exactly one entry to a different valid state.
    func testMutationChangesExactlyOneEntry() {
        var rng = Xoshiro256(seed: 11)
        var rule = Rule.random(using: &rng)
        for _ in 0..<50 {
            let mutant = rule.mutated(using: &rng)
            let diffs = (0..<Rule.tableSize).filter { rule.states[$0] != mutant.states[$0] }
            XCTAssertEqual(diffs.count, 1)
            let i = diffs[0]
            XCTAssertLessThan(mutant.states[i], UInt8(Rule.stateCount))
            XCTAssertNotEqual(mutant.states[i], rule.states[i])
            rule = mutant
        }
    }

    // PT-2: random rules are valid.
    func testRandomRulesValid() {
        var rng = Xoshiro256(seed: 2)
        for _ in 0..<20 {
            let rule = Rule.random(using: &rng)
            XCTAssertEqual(rule.states.count, Rule.tableSize)
            XCTAssertTrue(rule.states.allSatisfy { $0 < UInt8(Rule.stateCount) })
        }
    }

    // PT-3: invalid construction fails cleanly.
    func testInvalidConstructionRejected() {
        var rng = Xoshiro256(seed: 3)
        let rule = Rule.random(using: &rng)
        XCTAssertThrowsError(try Automaton(width: 2, rule: rule, cells: [0, 0]))
        XCTAssertThrowsError(try Automaton(width: 5, rule: rule, cells: [0, 0, 0]))
        XCTAssertThrowsError(try Automaton(width: 5, rule: rule, cells: [4, 0, 0, 0, 0]))
        XCTAssertThrowsError(try Rule(states: [UInt8](repeating: 0, count: 19)))
        XCTAssertThrowsError(try Rule(states: [4] + [UInt8](repeating: 0, count: 19)))
    }

    // PT-4: the all-zero rule screens as cyclic with period 1.
    func testAllZeroRuleCyclic() throws {
        var rng = Xoshiro256(seed: 4)
        let result = Classifier.evaluate(
            try Rule(states: [UInt8](repeating: 0, count: 20)), using: &rng)
        XCTAssertEqual(result.cyclePeriod, 1)
        XCTAssertFalse(result.maybeIV)
    }

    // PT-5: findCandidate always returns a rule, including the fallback.
    func testFindCandidateAlwaysReturns() {
        var rng = Xoshiro256(seed: 5)
        let (rule, tries) = Classifier.findCandidate(using: &rng, maxTries: 1)
        XCTAssertEqual(tries, 1)
        XCTAssertEqual(rule.states.count, Rule.tableSize)
    }

    // PT-6: current-rule round trip; missing/corrupt loads as absent.
    func testRuleStoreRoundTrip() throws {
        let store = try tempStore()
        XCTAssertNil(store.loadRule())
        var rng = Xoshiro256(seed: 6)
        let rule = Rule.random(using: &rng)
        store.saveRule(rule)
        XCTAssertEqual(store.loadRule(), rule)
        try "not a rule\n".write(
            to: store.stateDir.appendingPathComponent("rule"),
            atomically: true, encoding: .utf8)
        XCTAssertNil(store.loadRule())
    }

    // PT-7: candidate stash round trip in order; invalid lines skipped.
    func testCandidatesRoundTrip() throws {
        let store = try tempStore()
        XCTAssertEqual(store.loadCandidates(), [])
        var rng = Xoshiro256(seed: 7)
        let rules = (0..<5).map { _ in Rule.random(using: &rng) }
        store.saveCandidates(rules)
        XCTAssertEqual(store.loadCandidates(), rules)
        try ("garbage\n" + rules[0].id + "\n").write(
            to: store.stateDir.appendingPathComponent("candidates"),
            atomically: true, encoding: .utf8)
        XCTAssertEqual(store.loadCandidates(), [rules[0]])
    }

    // PT-8: odca file — pairs — round trip and tolerant loading.
    func testOdcaFileRoundTripAndTolerance() throws {
        let store = try tempStore()
        let url = store.stateDir.appendingPathComponent("pairs.odca")
        var rng = Xoshiro256(seed: 8)
        let first = Rule.random(using: &rng)
        let second = Rule.random(using: &rng)
        let pairs = [Pair(rule: first.id, colorset: "ODCA default", colors: Store.defaultColorSets[1]!.colors),
                     Pair(rule: second.id, colorset: "Mine", colors: ["#000000", "#111111", "#222222", "#333333"])]
        Store.saveOdcaFile(pairs, to: url)
        XCTAssertEqual(Store.loadOdcaFile(url), pairs)
        try "{\"pairs\": [{\"rule\": \"notarule\", \"colorset\": \"x\", \"colors\": [\"#000000\", \"#000000\", \"#000000\", \"#000000\"]}, {\"rule\": \"\(first.id)\", \"colorset\": \"ok\", \"colors\": [\"#000000\", \"#000000\", \"#000000\", \"#000000\"]}]}"
            .write(to: url, atomically: true, encoding: .utf8)
        XCTAssertEqual(Store.loadOdcaFile(url)!.map(\.rule), [first.id])
        try "{\"entries\": [{\"rule\": \"\(first.id)\", \"colorset\": \"old\", \"colors\": [\"#000000\", \"#000000\", \"#000000\", \"#000000\"]}]}"
            .write(to: url, atomically: true, encoding: .utf8)  // an unknown key holds nothing
        XCTAssertEqual(Store.loadOdcaFile(url), [])
    }

    // PT-11: stop() terminates workers; stopping an unstarted search is safe.
    // PT-12: delivered candidates are valid rules.
    func testSearchFindsCandidatesAndStops() {
        CandidateSearch(workers: 1).stop()  // never started: must not hang

        let search = CandidateSearch(workers: 2)
        search.start()
        var found: [Rule] = []
        let deadline = Date().addingTimeInterval(30)
        while found.isEmpty && Date() < deadline {
            found = search.drain()
            Thread.sleep(forTimeInterval: 0.05)
        }
        search.stop()
        XCTAssertFalse(found.isEmpty, "no candidate found within 30s")
        XCTAssertTrue(found.allSatisfy { $0.states.count == Rule.tableSize })
    }

    // PT-24: color sets file round trip and tolerance (R-P4).
    func testColorSetsRoundTripAndTolerance() throws {
        let store = try tempStore()
        XCTAssertEqual(Set(store.loadColorSets().keys), [1])  // missing file: default only
        let sets = [0: ColorSet(name: "A", colors: ["#010203", "#040506", "#070809", "#0A0B0C"]),
                    1: ColorSet(name: "Mine", colors: ["#000000", "#FFFFFF", "#FF0000", "#0000FF"])]
        store.saveColorSets(sets)
        XCTAssertEqual(store.loadColorSets(), sets)  // file's slot 1 overrides the built-in
        try """
            {"sets": [{"slot": 4, "name": "bad", "colors": ["#12"]},
                      {"slot": 12, "name": "x", "colors": ["#000000", "#000000", "#000000", "#000000"]},
                      {"slot": 7, "name": "ok", "colors": ["#abcdef", "#000000", "#111111", "#222222"]}]}
            """.write(to: store.libraryFile, atomically: true, encoding: .utf8)
        let loaded = store.loadColorSets()
        XCTAssertEqual(Set(loaded.keys), [1, 7])
        XCTAssertEqual(loaded[7]!.colors[0], "#ABCDEF")
        try "not json".write(to: store.libraryFile, atomically: true, encoding: .utf8)
        XCTAssertEqual(Set(store.loadColorSets().keys), [1])
    }

    /// Saving the shipped file back out must be byte-identical (shared file).
    func testColorSetsFileLayoutMatchesReference() throws {
        let reference = Store.repoRoot.appendingPathComponent("library.json")
        let original = try String(contentsOf: reference, encoding: .utf8)
        let store = try tempStore()
        store.saveColorSetFile(Store(libraryFile: reference).loadColorSetFile())
        XCTAssertEqual(try String(contentsOf: store.libraryFile, encoding: .utf8), original)
    }

    // R-P4: pool entries and the dropped list round-trip; saveColorSets keeps them.
    func testColorSetFilePoolAndDropped() throws {
        let store = try tempStore()
        let file = ColorSetFile(sets: [
            ColorSetEntry(slot: 1, name: "One", colors: ["#000000", "#111111", "#222222", "#333333"]),
            ColorSetEntry(slot: nil, name: "Pool A", colors: ["#AAAAAA", "#BBBBBB", "#CCCCCC", "#DDDDDD"]),
        ], dropped: ["Gone"])
        store.saveColorSetFile(file)
        XCTAssertEqual(store.loadColorSetFile(), file)
        XCTAssertEqual(Set(store.loadColorSets().keys), [1])
        store.saveColorSets([1: ColorSet(name: "One", colors: ["#333333", "#222222", "#111111", "#000000"]),
                             2: ColorSet(name: "Two", colors: ["#010101", "#010101", "#010101", "#010101"])])
        let after = store.loadColorSetFile()
        XCTAssertEqual(after.sets.map(\.name), ["One", "Two", "Pool A"])
        XCTAssertEqual(after.sets[0].colors[0], "#333333")
        XCTAssertNil(after.sets[2].slot)
        XCTAssertEqual(after.dropped, ["Gone"])
        let text = try String(contentsOf: store.libraryFile, encoding: .utf8)
        XCTAssertTrue(text.hasSuffix(" \"dropped\": [\n  \"Gone\"\n ]\n}\n"))
        // A JSON null slot reads as pool-only.
        try "{\"sets\": [{\"slot\": null, \"name\": \"N\", \"colors\": [\"#000000\", \"#000000\", \"#000000\", \"#000000\"]}]}"
            .write(to: store.libraryFile, atomically: true, encoding: .utf8)
        XCTAssertNil(store.loadColorSetFile().sets.first!.slot)
    }

    func testCandidatePalettesLoad() throws {
        let store = try tempStore()
        XCTAssertEqual(store.loadCandidatePalettes(), [])
        try "{\"palettes\": [{\"index\": 0, \"name\": \"A\", \"colors\": [\"#0a0a0a\", \"#000000\", \"#000000\", \"#000000\"]}, {\"name\": \"bad\", \"colors\": [\"#12\"]}]}"
            .write(to: store.candidatePalettesFile, atomically: true, encoding: .utf8)
        XCTAssertEqual(store.loadCandidatePalettes(), [ColorSetEntry(slot: nil, name: "A", colors: ["#0A0A0A", "#000000", "#000000", "#000000"])])
    }

    // R-P3, PT-29: odca file round trip, tolerance, and Python-compatible layout.
    func testOdcaFileLayout() throws {
        let store = try tempStore()
        let url = store.stateDir.appendingPathComponent("saver.odca")
        XCTAssertNil(Store.loadOdcaFile(url))  // missing
        let pairs = [Pair(rule: String(repeating: "0123", count: 5), colorset: "A", colors: ["#000000", "#111111", "#222222", "#333333"]),
                     Pair(rule: String(repeating: "3", count: 20), colorset: "B \"quoted\"", colors: ["#AAAAAA", "#BBBBBB", "#CCCCCC", "#DDDDDD"])]
        Store.saveOdcaFile(pairs, to: url)
        XCTAssertEqual(Store.loadOdcaFile(url), pairs)
        let named = [Pair(name: "pair-0007", rule: pairs[0].rule, colorset: pairs[0].colorset, colors: pairs[0].colors), pairs[1]]
        Store.saveOdcaFile(named, to: url)  // a name is kept, and written first
        XCTAssertEqual(Store.loadOdcaFile(url), named)
        XCTAssertTrue(try String(contentsOf: url, encoding: .utf8).hasPrefix("{\n \"pairs\": [\n  {\n   \"name\": \"pair-0007\",\n   \"rule\": \""))
        try String(contentsOf: url, encoding: .utf8).replacingOccurrences(of: "\"pairs\"", with: "\"looks\"")
            .write(to: url, atomically: true, encoding: .utf8)  // the 3.0.0 key is still read
        XCTAssertEqual(Store.loadOdcaFile(url), named)
        XCTAssertEqual(Store.nextPairName([]), "pair-0000")
        XCTAssertEqual(Store.nextPairName([Pair(name: "pair-0000", rule: "", colorset: "", colors: []),
                                           Pair(name: "pair-0002", rule: "", colorset: "", colors: []),
                                           Pair(rule: "", colorset: "", colors: [])]), "pair-0003")
        XCTAssertEqual(Store.nextPairName([Pair(name: "pair-9999", rule: "", colorset: "", colors: [])]), "pair-10000")
        XCTAssertEqual(Store.nextPairName([Pair(name: "sunset", rule: "", colorset: "", colors: [])]), "pair-0000")
        Store.saveOdcaFile(pairs, to: url)
        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(text.hasPrefix("{\n \"pairs\": [\n  {\n   \"rule\": \"01230123012301230123\",\n   \"colorset\": \"A\",\n   \"colors\": [\n    \"#000000\","))
        Store.saveOdcaFile([], to: url)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "{\n \"pairs\": []\n}\n")
        try "{\"pairs\": [{\"rule\": \"bad\", \"colorset\": \"x\", \"colors\": [\"#000000\", \"#000000\", \"#000000\", \"#000000\"]}, {\"rule\": \"00000000000000000000\", \"colorset\": \"ok\", \"colors\": [\"#0a0a0a\", \"#000000\", \"#000000\", \"#000000\"]}]}"
            .write(to: url, atomically: true, encoding: .utf8)
        XCTAssertEqual(Store.loadOdcaFile(url)!.map(\.colorset), ["ok"])
        XCTAssertEqual(Store.loadOdcaFile(url)!.first!.colors[0], "#0A0A0A")
        try "not json".write(to: url, atomically: true, encoding: .utf8)
        XCTAssertEqual(Store.loadOdcaFile(url), [])
    }

    /// The shipped odca file (written by Python's json.dumps) round-trips byte-identically.
    func testOdcaFileLayoutMatchesReference() throws {
        let reference = Store.repoRoot.appendingPathComponent("interesting.odca")
        let original = try String(contentsOf: reference, encoding: .utf8)
        let store = try tempStore()
        let url = store.stateDir.appendingPathComponent("copy.odca")
        Store.saveOdcaFile(Store.loadOdcaFile(reference)!, to: url)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), original)
    }

    func testFitToWidthKeepsTheAspect() {  // PT-44, R-X8
        var fit = Geometry.fitToWidth(width: 1920, height: 1080, cols: 600, cell: 2)
        XCTAssertEqual(fit.factor, 1.6, accuracy: 1e-12)
        XCTAssertEqual(fit.rows, 337)  // 1080 / 3.2
        XCTAssertFalse(Geometry.isWhole(fit.factor))
        fit = Geometry.fitToWidth(width: 1200, height: 800, cols: 600, cell: 2)
        XCTAssertEqual(fit.factor, 1)
        XCTAssertEqual(fit.rows, 400)
        XCTAssertTrue(Geometry.isWhole(fit.factor))
        fit = Geometry.fitToWidth(width: 600, height: 50, cols: 600, cell: 2)  // scaled down, one row at least
        XCTAssertEqual(fit.factor, 0.5)
        XCTAssertEqual(fit.rows, 50)
        XCTAssertEqual(Geometry.fitToWidth(width: 600, height: 0, cols: 600, cell: 2).rows, 1)
    }
}

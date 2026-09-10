import Foundation

/// odca-evolve (REQTS section 4e): the search for a rule's longest-lived
/// seeds at one width. A seed's lifetime is the number of generations
/// before the first one that is boring by extinction (R-A1's first clause,
/// the same test that makes odca re-seed) or that confirms a cycle
/// (Brent's, as the player runs it), or the cap.
public enum Evolve {
    public static let keep = 10  // the seeds kept per rule and width (R-E3)
    public static let defaultCap = 100_000  // generations a row may live before it counts as surviving (R-E2)
    public static let rateWindow = 10  // seconds the countdown's rows-per-second looks back over (R-E4)
    public static let parityMargin = 0.9  // --parity: a rule gives up its turn when its shortest × this outlives the rest (R-E5)

    /// `--parity` (R-E5): whether `rule` gives up its turn at `width` — its
    /// shortest recorded lifetime times the margin outlives the longest
    /// lifetime of some other rule among `rules` at that width, that is,
    /// of the other rule furthest behind. Returns the two lifetimes for
    /// the message, or nil when the rule runs: it has no seeds, no other
    /// rule has any, or no other rule is that far behind it.
    public static func givesUpTurn(rule: String, width: Int, seeds: Seeds, rules: [String]) -> (shortest: Int, longest: Int)? {
        guard let shortest = seeds[rule]?[width]?.map(\.generations).min() else { return nil }
        let others = rules.filter { $0 != rule }.compactMap { seeds[$0]?[width]?.map(\.generations).max() }
        guard let behind = others.min(), Double(shortest) * parityMargin > Double(behind) else { return nil }
        return (shortest, behind)
    }

    /// The plan for one round trip under `--parity` (R-E5), made up front on
    /// the seeds as they stand: the rules that give up their turn, with the
    /// lifetimes for their lines, and how many qualified. With `limit` above
    /// zero only that many are skipped, those furthest ahead by their
    /// shortest lifetime, ties in file order.
    public static func parityPlan(rules: [String], width: Int, seeds: Seeds, limit: Int)
        -> (skips: [String: (shortest: Int, longest: Int)], ahead: Int) {
        let ahead = rules.compactMap { id in givesUpTurn(rule: id, width: width, seeds: seeds, rules: rules).map { (id, $0) } }
        var chosen = ahead
        if limit > 0 && ahead.count > limit {
            let order = Dictionary(uniqueKeysWithValues: rules.enumerated().map { ($1, $0) })
            chosen = Array(ahead.sorted { ($0.1.shortest, order[$1.0]!) > ($1.1.shortest, order[$0.0]!) }.prefix(limit))
        }
        return (Dictionary(uniqueKeysWithValues: chosen), ahead.count)
    }

    /// A span of seconds as `hh:mm:ss`, rounded up to the second: the
    /// countdown, and the time left that opens every status line (R-E4, R-O16).
    public static func hms(_ seconds: Double) -> String {
        let whole = max(0, Int(seconds.rounded(.up)))
        return String(format: "%02d:%02d:%02d", whole / 3600, whole / 60 % 60, whole % 60)
    }
    static let stopCheckEvery = 1024  // generations between looks at the stop flag

    /// Evolve `row` under `rule` in wrap mode until extinction, a confirmed
    /// cycle, or the cap (R-E2). nil when `shouldStop` said to abandon the row.
    public static func lifetime(rule: Rule, row: [UInt8], cap: Int,
                                shouldStop: () -> Bool = { false }) -> Seed? {
        guard var automaton = try? Automaton(width: row.count, rule: rule, cells: row) else { return nil }
        // Brent's cycle detection, as Session.observe runs it from a fresh
        // seed: one saved row, refreshed at powers of two; a recurrence
        // proves the future periodic, the steps since the snapshot the period.
        var snapshot: [UInt8]?
        var power = 1, steps = 0
        while automaton.generation < cap {
            let next = automaton.step()
            if let end = Session.extinction(in: next, rule: rule) {
                return Seed(row: row, generations: automaton.generation, end: end)
            }
            if let saved = snapshot {
                steps += 1
                if next == saved {
                    return Seed(row: row, generations: automaton.generation, end: "repeating (period \(steps))")
                }
                if steps == power {
                    snapshot = next
                    power *= 2
                    steps = 0
                }
            } else {
                snapshot = next
            }
            if automaton.generation % stopCheckEvery == 0 && shouldStop() { return nil }
        }
        return Seed(row: row, generations: cap, end: Seed.survived)
    }

    /// The ten to keep out of any number (R-E3): longest first, ties by
    /// row text, identical rows counted once.
    public static func merge(_ lists: [Seed]...) -> [Seed] {
        var seen = Set<[UInt8]>()
        return lists.joined()
            .filter { seen.insert($0.row).inserted }
            .sorted { ($0.generations, $1.rowText) > ($1.generations, $0.rowText) }
            .prefix(keep).map { $0 }
    }

    /// Seeds by rule and width, merged list by list.
    public static func merge(_ a: Seeds, _ b: Seeds) -> Seeds {
        var out = a
        for (id, byWidth) in b {
            for (width, list) in byWidth {
                out[id, default: [:]][width] = merge(out[id]?[width] ?? [], list)
            }
        }
        return out
    }

    /// Where `seed` would join `kept` (longest first), 0-based, or nil: it
    /// joins when fewer than ten are kept or it outlived the shortest, and
    /// never when its row is already there (R-E3).
    public static func rank(of seed: Seed, among kept: [Seed]) -> Int? {
        if kept.contains(where: { $0.row == seed.row }) { return nil }
        let index = kept.firstIndex { $0.generations < seed.generations } ?? kept.count
        return index < keep ? index : nil
    }
}

/// One rule's search (R-E2, R-E3): workers on every processor draw random
/// rows and measure their lifetimes until the deadline; the coordinator
/// keeps the ten longest and reports each row that joins them.
public final class SeedSearch: @unchecked Sendable {
    public let rule: Rule
    public let cells: Int
    public let cap: Int
    public let workers: Int
    /// Called, serialized, with each seed that joins the ten and its 1-based rank at the time.
    public var onKept: ((Seed, Int) -> Void)?
    private let lock = NSLock()
    private var stopRequested = false
    private var keptRows: [Seed]
    private var triedCount = 0

    public init(rule: Rule, cells: Int, cap: Int = Evolve.defaultCap, workers: Int? = nil, kept: [Seed] = []) {
        self.rule = rule
        self.cells = cells
        self.cap = cap
        self.workers = workers ?? max(1, ProcessInfo.processInfo.activeProcessorCount)
        self.keptRows = Evolve.merge(kept)
    }

    /// The ten so far, longest first.
    public var kept: [Seed] {
        lock.lock()
        defer { lock.unlock() }
        return keptRows
    }

    /// Rows whose lifetimes were measured (abandoned rows are not counted).
    public var tried: Int {
        lock.lock()
        defer { lock.unlock() }
        return triedCount
    }

    public var stopped: Bool {
        lock.lock()
        defer { lock.unlock() }
        return stopRequested
    }

    /// End the search early (Ctrl-C, R-E4); `run` then returns as soon as the
    /// workers notice, within a thousand generations each.
    public func stop() {
        lock.lock()
        stopRequested = true
        lock.unlock()
    }

    private func offer(_ seed: Seed) {
        lock.lock()
        defer { lock.unlock() }
        triedCount += 1
        guard let index = Evolve.rank(of: seed, among: keptRows) else { return }
        keptRows.insert(seed, at: index)
        if keptRows.count > Evolve.keep { keptRows.removeLast() }
        onKept?(seed, index + 1)
    }

    /// Search until `deadline` or `stop()`, calling `tick` about once a
    /// second with the time left; returns the ten, longest first.
    @discardableResult
    public func run(until deadline: Date, tick: ((TimeInterval) -> Void)? = nil) -> [Seed] {
        let group = DispatchGroup()
        for _ in 0..<workers {
            DispatchQueue.global(qos: .userInitiated).async(group: group) { [self] in
                var rng = Xoshiro256()  // per-worker OS-entropy seed; streams differ
                while !stopped && Date() < deadline {
                    let row = Automaton.randomCells(width: cells, using: &rng)
                    guard let seed = Evolve.lifetime(rule: rule, row: row, cap: cap,
                                                     shouldStop: { self.stopped || Date() >= deadline })
                    else { break }  // R-E2: a row unfinished at the end is discarded
                    offer(seed)
                }
            }
        }
        while !stopped {
            let remaining = deadline.timeIntervalSinceNow
            if remaining <= 0 { break }
            tick?(remaining)
            Thread.sleep(forTimeInterval: min(1, remaining))
        }
        stop()
        group.wait()
        return kept
    }
}

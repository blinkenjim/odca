import Foundation

/// odca-evolve (REQTS section 4e): the search for a rule's longest-lived
/// seeds at one width. A seed's lifetime is the number of generations
/// before the first one that is boring by extinction (R-A1's first clause,
/// the same test that makes odca re-seed) or that confirms a cycle
/// (Brent's, as the player runs it), or the cap.
public enum Evolve {
    public static let keep = 10  // the seeds kept per rule and width (R-E3)
    public static let defaultCap = 1_000_000  // generations a row may live before it counts as surviving (R-E2)
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

    /// R-E3: ten survivors of the cap leave the search nothing to improve:
    /// the turn ends early.
    public static func allSurvived(_ kept: [Seed]) -> Bool {
        kept.count == keep && kept.allSatisfy { $0.end == Seed.survived }
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

/// R-E2's stagnation clause: the minority population of the last
/// `Session.stagnationWindow` generations, answering R-A1's question — is
/// `(max - min) / mean` under the swing? — in constant time per generation.
///
/// The player rescans its whole window on every row, which costs nothing at
/// display rates; a search measuring millions of generations cannot. So the
/// sum is carried, and the extremes are kept in two deques of slot numbers,
/// oldest at the front and values monotonic behind it. A slot leaves the
/// front when it falls out of the window and the back when the arriving
/// value beats it, which it never comes back from, so each slot is pushed
/// and popped once and the front is always the window's extreme.
struct StagnationWindow {
    private let width: Int
    private var values: [Int]
    private var least: [Int], greatest: [Int]  // slot numbers, monotonic
    private var leastFront = 0, leastBack = 0
    private var greatestFront = 0, greatestBack = 0
    private var arrived = 0, sum = 0

    init(width: Int) {
        self.width = width
        values = [Int](repeating: 0, count: width)
        least = values
        greatest = values
    }

    /// Admits one generation's minority population and says whether the
    /// window is now both full and steady.
    mutating func admit(_ population: Int) -> Bool {
        // Once full, the slot about to be written is the oldest, so this is
        // where it leaves the sum and, if it is one, an extreme.
        let slot = arrived % width
        if arrived >= width {
            sum -= values[slot]
            if least[leastFront % width] == slot { leastFront += 1 }
            if greatest[greatestFront % width] == slot { greatestFront += 1 }
        }
        values[slot] = population
        sum += population
        while leastBack > leastFront, values[least[(leastBack - 1) % width]] >= population {
            leastBack -= 1
        }
        least[leastBack % width] = slot
        leastBack += 1
        while greatestBack > greatestFront, values[greatest[(greatestBack - 1) % width]] <= population {
            greatestBack -= 1
        }
        greatest[greatestBack % width] = slot
        greatestBack += 1
        arrived += 1

        guard arrived >= width else { return false }
        let mean = Double(sum) / Double(width)
        let spread = values[greatest[greatestFront % width]] - values[least[leastFront % width]]
        return mean > 0 && Double(spread) / mean < Session.stagnationSwing
    }
}


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
        // R-E2: the stagnation clause of R-A1, run on the same populations
        // the player watches, so a seed's lifetime ends where the player
        // would re-seed rather than running on to the cap unwatchable.
        var steady = StagnationWindow(width: Session.stagnationWindow)
        // R-A1: the extinction clause reads how long each state has been a
        // minority, so the run carries that history rather than the row.
        var clock = Session.MinorityClock()
        while automaton.generation < cap {
            let next = automaton.step()
            let (end, minorityPopulation) = Session.census(of: next, rule: rule, clock: &clock)
            if let end = end {
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
            // Last of the three: an extinction or a confirmed cycle says
            // outright what the row has become, where stagnation only says
            // it has stopped going anywhere.
            if steady.admit(minorityPopulation) {
                return Seed(row: row, generations: automaton.generation, end: "stagnant")
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
    /// Called as a seed joins the ten: the seed, its 1-based rank, and the
    /// ten as they now stand. The list is handed over rather than read back
    /// from `kept`, for two reasons: this runs with the lock held and `kept`
    /// takes that same lock, which is not recursive, so reading it here would
    /// deadlock; and a snapshot is what the caller wants anyway, matching the
    /// moment of the keep rather than whatever another worker did since.
    public var onKept: ((Seed, Int, [Seed]) -> Void)?
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
        onKept?(seed, index + 1, keptRows)
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

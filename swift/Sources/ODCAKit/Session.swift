import Foundation

/// The toolkit-free orchestration layer: everything the interactive
/// program does except rendering pixels and reading raw key events.
/// The UI layer translates toolkit key events into `Session.Key`, calls
/// `tick(_:)` at its refresh rate, and draws `history` with the palette
/// for `colorSet`. See REQTS sections R-U, R-K, R-B, R-O.
public final class Session {
    public static let definedColorSets = 3  // slots 0-2; 3-9 reserved (R-U4)
    public static let defaultColorSet = 2
    public static let initialDelay = 1.0 / 60.0  // R-U5
    public static let minDelay = 1.0 / 16384.0  // R-K8
    public static let maxDelay = 8.0
    public static let maxCandidates = 64  // R-S3
    public static let stepCap = 2000  // per-tick catch-up cap (R-U5)

    public enum Key: Equatable {
        case q, r, m, u, s, i, n, p
        case plus, minus, space, ret
        case digit(Int)
    }

    public let cols: Int
    public let rows: Int
    public private(set) var automaton: Automaton
    /// The most recent generations, oldest first, at most `rows` entries.
    public private(set) var history: [[UInt8]] = []
    public private(set) var delay = Session.initialDelay
    public private(set) var paused = false
    public private(set) var colorSet = Session.defaultColorSet
    public private(set) var undoStack: [Rule] = []
    public private(set) var interestingIndex: Int?
    public private(set) var unsavedRule: Rule?
    public private(set) var candidates: [Rule]

    let store: Store
    let search: CandidateSearch
    var rng: Xoshiro256
    private var accumulated = 0.0

    public init(
        cols: Int, rows: Int, store: Store = Store(),
        search: CandidateSearch = CandidateSearch(), rng: Xoshiro256 = Xoshiro256()
    ) {
        self.cols = cols
        self.rows = rows
        self.store = store
        self.search = search
        var rng = rng

        // Startup per R-U1: previous rule (random fallback), random cells.
        let rule = store.loadRule() ?? Rule.random(using: &rng)
        automaton = try! Automaton(
            width: cols, rule: rule,
            cells: Automaton.randomCells(width: cols, using: &rng))
        store.saveRule(rule)

        // Cycle position per R-U1 step 6 / R-B3.
        let saved = store.loadInteresting()
        if let index = saved.firstIndex(of: rule) {
            interestingIndex = index
            unsavedRule = nil
        } else {
            interestingIndex = nil
            unsavedRule = rule
        }

        candidates = store.loadCandidates()
        self.rng = rng
        pushRow(automaton.cells)
        print("rule \(rule.id)")
    }

    public var ruleID: String { automaton.rule.id }

    public func startSearch() { search.start() }
    public func stopSearch() { search.stop() }

    private func pushRow(_ row: [UInt8]) {
        history.append(row)
        if history.count > rows { history.removeFirst() }
    }

    /// Advance by elapsed wall-clock time (R-U5); call at ~60 Hz.
    public func tick(_ dt: Double) {
        drainSearch()
        accumulated += dt
        if paused {
            accumulated = 0  // no catch-up burst on resume (R-K10)
            return
        }
        let steps = Int(accumulated / delay)
        accumulated -= Double(steps) * delay
        for _ in 0..<min(steps, Session.stepCap) {
            pushRow(automaton.step())
        }
    }

    private func drainSearch() {
        guard candidates.count < Session.maxCandidates else { return }
        let found = search.drain()
        if !found.isEmpty {
            candidates.append(contentsOf: found)
            if candidates.count > Session.maxCandidates {
                candidates.removeLast(candidates.count - Session.maxCandidates)
            }
            store.saveCandidates(candidates)
        }
    }

    private func setRule(_ rule: Rule) {
        automaton.rule = rule
        store.saveRule(rule)
        print("rule \(rule.id)")  // R-O1
    }

    private func setUnsavedRule(_ rule: Rule) {
        unsavedRule = rule
        interestingIndex = nil
        setRule(rule)
    }

    private func newRule() {  // R-K2
        undoStack.append(automaton.rule)
        drainSearch()
        let rule: Rule
        if !candidates.isEmpty {
            rule = candidates.removeFirst()
            store.saveCandidates(candidates)
        } else {
            let (found, tries) = Classifier.findCandidate(using: &rng)
            if tries > 1 {
                print("discarded \(tries - 1) rule\(tries > 2 ? "s" : "")")  // R-O2
            }
            rule = found
        }
        setUnsavedRule(rule)
    }

    private func mutateRule() {  // R-K3
        undoStack.append(automaton.rule)
        setUnsavedRule(automaton.rule.mutated(using: &rng))
    }

    private func undo() {  // R-K4
        if let rule = undoStack.popLast() {
            setRule(rule)
        }
    }

    private func saveInteresting() {  // R-K5
        store.appendInteresting(automaton.rule)
        print("saved rule \(automaton.rule.id)")  // R-O3
    }

    private func initCells() {  // R-K6
        automaton.resetRandom(using: &rng)
        pushRow(automaton.cells)
    }

    private func selectInteresting(step: Int) {  // R-B2, R-B3
        let rules = store.loadInteresting()
        guard !rules.isEmpty else {
            print("no saved interesting rules")  // R-O5
            return
        }
        let n = rules.count
        let total = unsavedRule != nil ? n + 1 : n
        let at = interestingIndex ?? n
        let to = ((at + step) % total + total) % total
        undoStack.append(automaton.rule)
        if to == n {  // only reachable when the unsaved slot is occupied
            interestingIndex = nil
            print("unsaved rule")  // R-O4
            setRule(unsavedRule!)
        } else {
            interestingIndex = to
            print("interesting \(to + 1)/\(n)")  // R-O4
            setRule(rules[to])
        }
    }

    /// Returns false when the program should quit.
    public func handleKey(_ key: Key) -> Bool {
        if key == .q { return false }
        if paused {  // R-K10: only space, Return, q are live
            switch key {
            case .space:
                paused = false
            case .ret:  // R-K11: single step, stay paused
                pushRow(automaton.step())
            default:
                break
            }
            return true
        }
        switch key {
        case .space:
            paused = true
        case .r:
            newRule()
        case .m:
            mutateRule()
        case .u:
            undo()
        case .s:
            saveInteresting()
        case .i:
            initCells()
        case .n:
            selectInteresting(step: 1)
        case .p:
            selectInteresting(step: -1)
        case .plus:
            delay = max(delay / 2, Session.minDelay)
        case .minus:
            delay = min(delay * 2, Session.maxDelay)
        case .digit(let d):
            if d >= 0 && d < Session.definedColorSets { colorSet = d }
        case .q, .ret:
            break
        }
        return true
    }
}

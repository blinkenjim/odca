import Foundation

/// An RGB color, states' display colors after arrangement (R-U4).
public struct RGB: Equatable {
    public let r: UInt8
    public let g: UInt8
    public let b: UInt8

    public init(r: UInt8, g: UInt8, b: UInt8) {
        self.r = r
        self.g = g
        self.b = b
    }

    /// Parse "#RRGGBB" (validated on load, so a bad string yields black).
    public init(hex: String) {
        let s = Array(hex.dropFirst())
        func byte(_ i: Int) -> UInt8 { UInt8(String(s[i..<i + 2]), radix: 16) ?? 0 }
        self.init(r: byte(0), g: byte(2), b: byte(4))
    }
}

/// The toolkit-free orchestration layer: everything the interactive
/// program does except rendering pixels and reading raw key events.
/// The UI layer translates toolkit key events into `Session.Key`, calls
/// `tick(_:)` at its refresh rate, and draws `history` with `palette`.
/// See REQTS sections R-U, R-K, R-B, R-A, R-P, R-O.
public final class Session {
    public static let defaultColorSet = 1  // slot active at startup (R-U4)
    public static let initialDelay = 1.0 / 60.0  // R-U5
    public static let minDelay = 1.0 / 16384.0  // R-K8
    public static let maxDelay = 8.0
    public static let maxCandidates = 64  // R-S3
    public static let stepCap = 2000  // per-tick catch-up cap (R-U5)
    public static let smoothScrollDelay = 2 * Session.initialDelay  // slower: continuous scrolling (R-U3)
    public static let screenSpeedup = 8.0  // paused 's' zips at delay / 8 (R-K13)
    public static let repeatScreens = 10  // repetition window in screens (R-A1)
    public static let minorityFraction = 0.10  // a producible state below this share is a minority (R-A1)
    public static let stagnationScreens = 4  // minority population steady this long -> stagnant (R-A1)
    public static let stagnationSwing = 0.25  // (max - min) / mean below this counts as steady
    public static let playTimeout = 120.0  // screensaver: a pair's screen time before it may advance (R-X3)
    public static let playGrace = 60.0  // screensaver: no transition within this long of an initialization (R-X3)
    public static let historyDepth = 2048  // rows remembered beyond the screen (R-U8)
    public static let minCols = 3  // R-M2

    /// Digit keys in review order (R-V): the first ten kept sets own these.
    public static let keyOrder = [1, 2, 3, 4, 5, 6, 7, 8, 9, 0]

    /// The 24 assignments of four colors to four states, lexicographic,
    /// identity first (R-K15).
    public static let arrangements: [[Int]] = permutations([0, 1, 2, 3])

    private static func permutations(_ items: [Int]) -> [[Int]] {
        if items.count <= 1 { return [items] }
        var out: [[Int]] = []
        for (i, x) in items.enumerated() {
            var rest = items
            rest.remove(at: i)
            for p in permutations(rest) { out.append([x] + p) }
        }
        return out
    }

    public enum Key: Equatable {
        case q, r, m, u, s, i, n, p, a
        case c, C, S  // arrange colors forward / backward, save color set
        case N, P, X  // review modes: next, previous, drop (R-V, R-W)
        case poolPrev, poolNext  // '[' / ']': step through the color set pool (R-W3)
        case plus, minus, space, ret
        case digit(Int)
    }

    public private(set) var cols: Int
    public private(set) var rows: Int
    public private(set) var automaton: Automaton
    /// Remembered generations, oldest first, up to `historyDepth` (never
    /// fewer than `rows + 1`). The display shows the last `rows + 1`: one
    /// more than the window, so continuous scrolling has a row to slide in;
    /// a taller window uncovers older rows (R-U8).
    public private(set) var history: [[UInt8]] = []
    /// Palette bank (0 or 1) each history row was painted from (R-X5).
    public private(set) var rowBanks: [UInt8] = []
    private var bank = 0
    private var banks: [[RGB]] = [[], []]  // two banks of four colors
    public private(set) var delay = Session.initialDelay
    public private(set) var paused = false
    public private(set) var screenRemaining = 0  // generations still to zip (R-K13)
    public private(set) var screenCounter: Int?  // screenfuls since last resume (R-K14)
    public private(set) var autoInit = true  // R-K12: on at startup, not persisted
    public private(set) var cyclePeriod: Int?  // exact period once Brent's finds a cycle
    public private(set) var colorSets: [Int: ColorSet]
    public private(set) var colorSet = Session.defaultColorSet
    // Color set review mode (R-V): kept sets in review order, position, drops.
    public let reviewMode: Bool
    public private(set) var reviewEntries: [ColorSetEntry] = []
    public private(set) var reviewIndex = 0
    public private(set) var droppedNames: [String] = []
    private var reviewArrangement: [String: Int] = [:]
    // Screensaver review mode (R-W): the file, its pairs, and the active set.
    public let screensaverFile: URL?
    public let groupByRule: Bool  // consistency check: view grouped by rule (R-W7)
    public private(set) var pairs: [ScreensaverPair] = []  // always in file order
    public private(set) var pairIndex: Int?  // file index of the pair under review
    public private(set) var viewOrder: [Int] = []  // file indices in presentation order
    public private(set) var viewPosition: Int?  // position of pairIndex within viewOrder
    // Screensaver mode (R-X): play the pairs of a file in order.
    public let playFile: URL?
    public private(set) var playElapsed = 0.0  // unpaused seconds on the current pair
    public private(set) var sinceInit = 0.0  // unpaused seconds since the last (re)initialization
    public private(set) var activeSet: ColorSetEntry?  // the set in use (any pool member)
    private var activeArrangement = 0
    private var pool: [ColorSetEntry] = []  // whole pool in review order for [ / ]
    public private(set) var undoStack: [Rule] = []
    public private(set) var interestingIndex: Int?
    public private(set) var unsavedRule: Rule?
    public private(set) var candidates: [Rule]
    /// Terminal output sink (R-O); the UI leaves it as print, tests capture it.
    public var output: (String) -> Void = { print($0) }

    let store: Store
    let search: CandidateSearch
    var rng: Xoshiro256
    private var accumulated = 0.0
    private var zipAccumulated = 0.0
    private var counted = 0  // generations since the screen counter started
    private var arrangement: [Int: Int] = [:]  // slot -> index into arrangements

    // Auto-init state (R-A); internal so tests can observe it.
    var boringStreak = 0
    var boringReason: String?
    private var recentRows: [[UInt8]] = []
    private var recentCounts: [[UInt8]: Int] = [:]
    private var minorityCounts: [Int] = []
    private var brentSnapshot: [UInt8]?
    private var brentPower = 1
    private var brentSteps = 0

    public init(
        cols: Int, rows: Int, store: Store = Store(),
        search: CandidateSearch = CandidateSearch(), rng: Xoshiro256 = Xoshiro256(),
        reviewMode: Bool = false, screensaverFile: URL? = nil, groupByRule: Bool = false,
        playFile: URL? = nil, output: @escaping (String) -> Void = { print($0) }
    ) {
        self.cols = cols
        self.rows = rows
        self.store = store
        self.search = search
        // Mode precedence: screensaver play, then screensaver review, then color set review.
        self.playFile = playFile
        let screensaverFile = playFile == nil ? screensaverFile : nil
        self.reviewMode = reviewMode && screensaverFile == nil && playFile == nil
        self.screensaverFile = screensaverFile
        self.groupByRule = groupByRule && screensaverFile != nil
        self.output = output
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
        colorSets = store.loadColorSets()  // R-P4
        self.rng = rng
        pushRow(automaton.cells)
        output("rule \(rule.id)")
        if reviewMode { loadReview() }
        if let url = screensaverFile { loadScreensaver(url) }
        if let url = playFile { loadPlay(url) }
    }

    public var screensaverMode: Bool { screensaverFile != nil }
    public var playMode: Bool { playFile != nil }
    /// Modes whose palette is the active set (any pool member) rather than a digit slot.
    private var activeSetMode: Bool { screensaverMode || playMode }

    public var ruleID: String { automaton.rule.id }

    public func startSearch() { search.start() }
    public func stopSearch() { search.stop() }

    private func pushRow(_ row: [UInt8]) {
        if playMode {
            // R-X5: a new color set takes the idle bank; rows already on
            // screen keep theirs until they scroll off.
            let current = palette
            if banks[bank].isEmpty {
                banks = [current, current]
            } else if current != banks[bank] {
                bank ^= 1
                banks[bank] = current
            }
        }
        history.append(row)
        rowBanks.append(UInt8(bank))
        trimHistory()
    }

    private func trimHistory() {
        let keep = max(Session.historyDepth, rows + 1)
        if history.count > keep {
            history.removeFirst(history.count - keep)
            rowBanks.removeFirst(rowBanks.count - keep)
        }
    }

    /// Index of the first history row the display shows (R-U3, R-U8).
    public var visibleStart: Int { max(0, history.count - (rows + 1)) }

    /// Change the geometry (R-U8): the state vector keeps its center — cropped
    /// from both edges when narrower, padded at both edges when wider, the
    /// new cells seeded at random (older rows padded with state 0) — and the
    /// boring detectors start afresh. Returns whether anything changed.
    @discardableResult
    public func resize(cols newCols: Int, rows newRows: Int) -> Bool {
        let newCols = max(Session.minCols, newCols)
        let newRows = max(1, newRows)
        guard newCols != cols || newRows != rows else { return false }
        if newCols != cols {
            func fit(_ row: [UInt8], padding: (Int) -> [UInt8]) -> [UInt8] {
                if newCols < row.count {
                    let left = (row.count - newCols) / 2
                    return Array(row[left..<(left + newCols)])
                }
                let add = newCols - row.count
                return padding(add / 2) + row + padding(add - add / 2)
            }
            history = history.map { fit($0) { [UInt8](repeating: 0, count: $0) } }
            var rng = self.rng
            let cells = fit(automaton.cells) { Automaton.randomCells(width: $0, using: &rng) }
            self.rng = rng
            automaton = try! Automaton(width: newCols, rule: automaton.rule, cells: cells)
            if !history.isEmpty { history[history.count - 1] = cells }
        }
        cols = newCols
        rows = newRows
        trimHistory()
        resetBoredom()
        output("resized \(cols)x\(rows)")  // R-O14
        return true
    }

    /// The eight-entry display palette: two banks of four (R-X5). Outside
    /// screensaver mode both banks are the active set, so the whole screen
    /// recolors at once.
    public var palette8: [RGB] {
        if playMode && !banks[0].isEmpty { return banks[0] + banks[1] }
        let p = palette
        return p + p
    }

    /// Display color of a history cell: its state through its row's bank.
    public func color(row: Int, col: Int) -> RGB {
        palette8[Int(rowBanks[row]) * 4 + Int(history[row][col])]
    }

    /// How far the display is scrolled into the top history row, in cells
    /// (R-U3): 0 while the buffer is filling; 1 (newest row fully shown) when
    /// paused or at fast speeds; else the elapsed fraction of the current
    /// delay, so the picture slides up one cell per delay.
    public var scrollOffset: Double {
        if history.count <= rows { return 0 }
        if paused || delay <= Session.smoothScrollDelay { return 1 }
        return min(accumulated / delay, 1)
    }

    // MARK: - Colors (R-U4, R-K15, R-K16)

    private func arrangedColors(_ slot: Int) -> [String] {
        let base = colorSets[slot]!.colors
        return Session.arrangements[arrangement[slot] ?? 0].map { base[$0] }
    }

    /// The set under review, or nil when the review pool is empty.
    private var reviewEntry: ColorSetEntry? {
        reviewEntries.isEmpty ? nil : reviewEntries[reviewIndex]
    }

    private func arrangedReviewColors() -> [String] {
        guard let e = reviewEntry else { return Store.defaultColorSets[1]!.colors }
        return Session.arrangements[reviewArrangement[e.name] ?? 0].map { e.colors[$0] }
    }

    private func arrangedActiveColors() -> [String] {
        let base = activeSet?.colors ?? colorSets[colorSet]!.colors
        return Session.arrangements[activeArrangement].map { base[$0] }
    }

    /// The active color set as four RGB colors, states 0-3, after arrangement.
    public var palette: [RGB] {
        let colors = reviewMode ? arrangedReviewColors()
            : activeSetMode ? arrangedActiveColors() : arrangedColors(colorSet)
        return colors.map { RGB(hex: $0) }
    }

    private func cycleColors(_ step: Int) {
        let n = Session.arrangements.count
        if activeSetMode {
            activeArrangement = ((activeArrangement + step) % n + n) % n
            let name = activeSet?.name ?? colorSets[colorSet]!.name
            output("color set \(name) arrangement \(activeArrangement + 1)/\(n)")  // R-O9
            return
        }
        if reviewMode {
            guard let e = reviewEntry else { return }
            let index = (((reviewArrangement[e.name] ?? 0) + step) % n + n) % n
            reviewArrangement[e.name] = index
            output("color set \(e.name) arrangement \(index + 1)/\(n)")  // R-O9
            return
        }
        let index = (((arrangement[colorSet] ?? 0) + step) % n + n) % n
        arrangement[colorSet] = index
        output("color set \(colorSet) arrangement \(index + 1)/\(n)")  // R-O9
    }

    // MARK: - Color set review (R-V)

    private static func keyRank(_ slot: Int) -> Int { keyOrder.firstIndex(of: slot) ?? 10 }

    /// Build the review order: digit-bound sets in key order (1-9, 0), then
    /// the pool, then every candidate palette not already present or dropped.
    private func loadReview() {  // R-V2
        let file = store.loadColorSetFile()
        var slotted = file.sets.filter { $0.slot != nil }
        if !slotted.contains(where: { $0.slot == 1 }) {
            let d = Store.defaultColorSets[1]!
            slotted.append(ColorSetEntry(slot: 1, name: d.name, colors: d.colors))
        }
        slotted.sort { Session.keyRank($0.slot!) < Session.keyRank($1.slot!) }
        var entries = slotted + file.sets.filter { $0.slot == nil }
        droppedNames = file.dropped
        var names = Set(entries.map(\.name))
        let dropped = Set(file.dropped)
        for p in store.loadCandidatePalettes() where !names.contains(p.name) && !dropped.contains(p.name) {
            entries.append(p)
            names.insert(p.name)
        }
        reviewEntries = entries
        reviewIndex = 0
        announceReview()
    }

    private func announceReview() {  // R-O11
        guard let e = reviewEntry else {
            output("review empty")
            return
        }
        output("review \(reviewIndex + 1)/\(reviewEntries.count) \(e.name)")
    }

    private func reviewStep(_ step: Int) {  // R-V3
        guard !reviewEntries.isEmpty else { return }
        var index = reviewIndex + step
        if index >= reviewEntries.count {
            index = 0
            output("review wrapped")
        } else if index < 0 {
            index = reviewEntries.count - 1
            output("review wrapped")
        }
        reviewIndex = index
        announceReview()
        for _ in 0..<rows { advance() }  // R-V7: fill the screen under the new set
    }

    private func dropReview() {  // R-V4
        guard let e = reviewEntry else { return }
        reviewEntries.remove(at: reviewIndex)
        droppedNames.append(e.name)
        reviewArrangement[e.name] = nil
        output("dropped \(e.name)")
        if reviewIndex >= reviewEntries.count && !reviewEntries.isEmpty {
            reviewIndex = 0
            output("review wrapped")
        }
        announceReview()
        saveReview()  // R-V5: every drop is saved at once
        if !reviewEntries.isEmpty { for _ in 0..<rows { advance() } }  // R-V7
    }

    /// Write the kept sets: the first ten in review order own the digit
    /// keys (1-9, 0), the rest are pool-only, dropped names recorded.
    /// Arrangements made during review are preview only (R-V6).
    private func saveReview() {  // R-V5
        var kept: [ColorSetEntry] = []
        for (i, e) in reviewEntries.enumerated() {
            var entry = e
            entry.slot = i < Session.keyOrder.count ? Session.keyOrder[i] : nil
            kept.append(entry)
        }
        reviewEntries = kept
        let ordered = kept.filter { $0.slot != nil }.sorted { $0.slot! < $1.slot! }
            + kept.filter { $0.slot == nil }
        store.saveColorSetFile(ColorSetFile(sets: ordered, dropped: droppedNames))
        colorSets = store.loadColorSets()
        output("saved \(kept.count) color sets, \(droppedNames.count) dropped")  // R-O11
    }

    // MARK: - Screensaver review (R-W)

    /// The whole pool in review order: digit-bound sets by key, then the rest.
    private func poolOrder() -> [ColorSetEntry] {
        let file = store.loadColorSetFile()
        var slotted = file.sets.filter { $0.slot != nil }
        if !slotted.contains(where: { $0.slot == 1 }) {
            let d = Store.defaultColorSets[1]!
            slotted.append(ColorSetEntry(slot: 1, name: d.name, colors: d.colors))
        }
        slotted.sort { Session.keyRank($0.slot!) < Session.keyRank($1.slot!) }
        return slotted + file.sets.filter { $0.slot == nil }
    }

    private func loadScreensaver(_ url: URL) {  // R-W1, R-W2
        pool = poolOrder()
        let d = colorSets[colorSet]!
        activeSet = ColorSetEntry(slot: colorSet, name: d.name, colors: d.colors)
        if let loaded = Store.loadScreensaver(url) {
            pairs = loaded
        } else {
            pairs = []
            Store.saveScreensaver(pairs, to: url)  // a new, empty file
        }
        rebuildViewOrder()
        output("screensaver \(url.lastPathComponent): \(pairs.count) pairs")
        if !pairs.isEmpty { activate(viewPosition: 0) }
    }

    /// Presentation order (R-W7): file order, or — in a consistency check —
    /// pairs grouped by rule, groups in order of each rule's first appearance.
    private func rebuildViewOrder() {
        if groupByRule {
            var groups: [String: [Int]] = [:]
            var ruleOrder: [String] = []
            for (i, p) in pairs.enumerated() {
                if groups[p.rule] == nil { ruleOrder.append(p.rule) }
                groups[p.rule, default: []].append(i)
            }
            viewOrder = ruleOrder.flatMap { groups[$0]! }
        } else {
            viewOrder = Array(pairs.indices)
        }
        viewPosition = pairIndex.flatMap { viewOrder.firstIndex(of: $0) }
    }

    /// 1-based group number of a file index among the rule groups, and the count.
    private func ruleGroup(of index: Int) -> (Int, Int) {
        var seen: [String] = []
        for p in pairs where !seen.contains(p.rule) { seen.append(p.rule) }
        return ((seen.firstIndex(of: pairs[index].rule) ?? 0) + 1, seen.count)
    }

    private func currentPair() -> ScreensaverPair {
        let name = activeSet?.name ?? colorSets[colorSet]!.name
        return ScreensaverPair(rule: automaton.rule.id, colorset: name, colors: arrangedActiveColors())
    }

    private func activate(viewPosition position: Int) {  // R-W2
        let index = viewOrder[position]
        if groupByRule, pairIndex.map({ pairs[$0].rule }) != pairs[index].rule {
            let (g, total) = ruleGroup(of: index)
            output("--- rule group \(g)/\(total) ---")  // R-O12
        }
        viewPosition = position
        let pair = pairs[index]
        pairIndex = index
        if let rule = try? Rule(id: pair.rule), rule != automaton.rule {
            undoStack.append(automaton.rule)
            setRule(rule)
        }
        activeSet = ColorSetEntry(slot: nil, name: pair.colorset, colors: pair.colors)
        activeArrangement = 0  // stored colors are already arranged
        output("screensaver \(position + 1)/\(pairs.count) \(pair.colorset)")  // R-O12
        // R-W8: fill the screen with the pair's own output at once, so every
        // navigation looks the same whether or not the rule changed.
        for _ in 0..<rows { advance() }
    }

    private func screensaverStep(_ step: Int) {  // R-W2: no wrap
        guard !pairs.isEmpty else { return }
        let next = (viewPosition ?? -1) + step
        guard (0..<viewOrder.count).contains(next) else {
            output("screensaver end")
            return
        }
        activate(viewPosition: next)
    }

    private func saveScreensaver() {
        guard let url = screensaverFile else { return }
        Store.saveScreensaver(pairs, to: url)
        output("saved \(pairs.count) pair\(pairs.count == 1 ? "" : "s") to \(url.lastPathComponent)")  // R-O12
    }

    private func savePair() {  // R-W4: 's' overwrites the pair under review
        guard let i = pairIndex else {
            output("no pair under review")
            return
        }
        pairs[i] = currentPair()  // in place: the file position is unchanged
        rebuildViewOrder()  // a changed rule may move it between groups
        saveScreensaver()
        output("saved pair \((viewPosition ?? i) + 1)/\(pairs.count)")  // R-O12
    }

    private func appendPair() {  // R-W4: 'S' appends; the review position is unchanged
        pairs.append(currentPair())  // always at the end of the file
        rebuildViewOrder()  // in a consistency check it joins its rule's group in the view
        saveScreensaver()
        output("added pair \(pairs.count)/\(pairs.count)")  // R-O12
    }

    private func deletePair() {  // R-W5
        guard let i = pairIndex, let position = viewPosition else { return }
        pairs.remove(at: i)  // in place: later pairs keep their relative file order
        pairIndex = nil
        rebuildViewOrder()
        saveScreensaver()
        output("deleted pair \(position + 1)/\(pairs.count + 1)")  // R-O12
        if pairs.isEmpty {
            viewPosition = nil
        } else {
            activate(viewPosition: min(position, viewOrder.count - 1))
        }
    }

    private func poolStep(_ step: Int) {  // R-W3: '[' / ']' walk the whole pool
        guard screensaverMode, !pool.isEmpty else { return }
        let current = pool.firstIndex { $0.name == activeSet?.name } ?? -1
        let n = pool.count
        let index = ((current + step) % n + n) % n
        activeSet = ColorSetEntry(slot: pool[index].slot, name: pool[index].name, colors: pool[index].colors)
        activeArrangement = 0
        output("color set \(pool[index].name)")  // R-O12
    }

    // MARK: - Screensaver mode (R-X)

    private func loadPlay(_ url: URL) {  // R-X1
        pairs = Store.loadScreensaver(url) ?? []
        let d = colorSets[colorSet]!
        activeSet = ColorSetEntry(slot: colorSet, name: d.name, colors: d.colors)
        output("screensaver \(url.lastPathComponent): \(pairs.count) pairs")
        if !pairs.isEmpty { playPair(0, reason: nil) }
    }

    /// Activate a pair for play: its rule and colors, then a fresh seed (R-X4).
    private func playPair(_ index: Int, reason: String?) {
        let pair = pairs[index]
        pairIndex = index
        if let rule = try? Rule(id: pair.rule), rule != automaton.rule { setRule(rule) }
        activeSet = ColorSetEntry(slot: nil, name: pair.colorset, colors: pair.colors)
        activeArrangement = 0
        initCells()
        playElapsed = 0  // the pair's screen time starts now
        let why = reason.map { " (\($0))" } ?? ""
        output("screensaver \(index + 1)/\(pairs.count) \(pair.colorset)\(why)")  // R-O13
    }

    private func nextPlayPair(reason: String) {  // R-X2, R-X3: sequential, looping
        playPair(((pairIndex ?? -1) + 1) % pairs.count, reason: reason)
    }

    private func playStep(_ step: Int) {  // R-X6: N/P move through the pairs, wrapping
        guard !pairs.isEmpty else { return }
        let n = pairs.count
        playPair((((pairIndex ?? 0) + step) % n + n) % n, reason: step > 0 ? "next" : "previous")
    }

    /// Call at program exit; in review mode this saves the kept sets (R-V5).
    public func finish() {
        if reviewMode { saveReview() }  // screensaver mode saves as it goes
    }

    private func saveColorSet() {
        colorSets[colorSet]!.colors = arrangedColors(colorSet)
        arrangement[colorSet] = 0
        store.saveColorSets(colorSets)
        output("saved color set \(colorSet) \(colorSets[colorSet]!.name)")  // R-O10
    }

    private func selectColorSet(_ slot: Int) {
        if reviewMode { return }  // R-V1: digit keys are disabled during review
        guard let set = colorSets[slot] else { return }  // R-K9: undefined slot is a no-op
        colorSet = slot
        if activeSetMode {
            activeSet = ColorSetEntry(slot: slot, name: set.name, colors: set.colors)
            activeArrangement = 0
        }
    }

    /// Color keys shared by the paused and running states (R-K10).
    private func handleColorKey(_ key: Key) -> Bool {
        switch key {
        case .c: cycleColors(1)
        case .C: cycleColors(-1)
        case .S:
            if screensaverMode { appendPair() } else if !reviewMode { saveColorSet() }
        case .N:
            if playMode { playStep(1) } else if screensaverMode { screensaverStep(1) } else if reviewMode { reviewStep(1) }
        case .P:
            if playMode { playStep(-1) } else if screensaverMode { screensaverStep(-1) } else if reviewMode { reviewStep(-1) }
        case .X: if screensaverMode { deletePair() } else if reviewMode { dropReview() }
        case .poolPrev: poolStep(-1)
        case .poolNext: poolStep(1)
        case .digit(let d): selectColorSet(d)
        default: return false
        }
        return true
    }

    // MARK: - Evolution and auto-init (R-U5, R-A)

    /// Compute one generation, display it, and apply auto-init (R-A).
    private func advance() {
        let row = automaton.step()
        pushRow(row)
        observe(row)
        if screenCounter != nil {  // R-K14
            counted += 1
            if counted % rows == 0 {
                screenCounter! += 1
                output("screen \(screenCounter!)")  // R-O7
            }
        }
        if autoInit && boringStreak >= rows {
            let reason = boringReason ?? "boring"
            if playMode && !pairs.isEmpty && playElapsed >= Session.playTimeout {
                nextPlayPair(reason: reason)  // R-X3: watchdog expired, a re-init transitions
            } else {
                initCells()
                output("auto-init (\(reason))")  // R-O6
            }
        }
    }

    /// Classify a computed generation as boring or not (R-A1).
    func observe(_ row: [UInt8]) {
        // Brent's cycle detection: one saved row, refreshed at powers of two.
        // The automaton is deterministic, so a recurring row proves the
        // future periodic; steps since the snapshot are exactly the period.
        if cyclePeriod == nil {
            if brentSnapshot == nil {
                brentSnapshot = row
            } else {
                brentSteps += 1
                if row == brentSnapshot! {
                    cyclePeriod = brentSteps
                    output("cycle period \(brentSteps)")  // R-O8
                } else if brentSteps == brentPower {
                    brentSnapshot = row
                    brentPower *= 2
                    brentSteps = 0
                }
            }
        }
        // Window repetition: seen within the last repeatScreens screens.
        let repeating = (recentCounts[row] ?? 0) > 0
        recentRows.append(row)
        recentCounts[row, default: 0] += 1
        if recentRows.count > Session.repeatScreens * rows {
            let old = recentRows.removeFirst()
            if let n = recentCounts[old] {
                if n <= 1 { recentCounts[old] = nil } else { recentCounts[old] = n - 1 }
            }
        }
        // Census: extinction with living-minority patience, and stagnation.
        var census = [Int](repeating: 0, count: Rule.stateCount)
        for c in row { census[Int(c)] += 1 }
        let producible = Set(automaton.rule.states.map { Int($0) }).sorted()
        let extinct = producible.filter { census[$0] == 0 }
        let minority = producible.filter {
            census[$0] > 0 && Double(census[$0]) < Session.minorityFraction * Double(row.count)
        }
        minorityCounts.append(minority.reduce(0) { $0 + census[$1] })
        let window = Session.stagnationScreens * rows
        if minorityCounts.count > window { minorityCounts.removeFirst() }
        var stagnant = false
        if minorityCounts.count == window {
            let lo = minorityCounts.min()!, hi = minorityCounts.max()!
            let mean = Double(minorityCounts.reduce(0, +)) / Double(window)
            stagnant = mean > 0 && Double(hi - lo) / mean < Session.stagnationSwing
        }

        let reason: String?
        if !extinct.isEmpty && minority.isEmpty {
            let names = extinct.map(String.init).joined(separator: ", ")
            reason = "state\(extinct.count > 1 ? "s" : "") \(names) extinct"
        } else if let period = cyclePeriod {
            reason = "repeating (period \(period))"
        } else if repeating {
            reason = "repeating"
        } else if stagnant {
            reason = "stagnant"
        } else {
            reason = nil
        }
        boringStreak = reason == nil ? 0 : boringStreak + 1
        boringReason = reason
    }

    private func resetBoredom() {  // R-A3
        boringStreak = 0
        boringReason = nil
        recentRows.removeAll()
        recentCounts.removeAll()
        minorityCounts.removeAll()
        brentSnapshot = nil
        brentPower = 1
        brentSteps = 0
        cyclePeriod = nil
    }

    /// Advance by elapsed wall-clock time (R-U5); call at ~60 Hz.
    public func tick(_ dt: Double) {
        drainSearch()
        if paused {
            // The main accumulator is frozen while paused (no catch-up burst,
            // R-K10); a queued screenful (R-K13) paces on its own accumulator.
            if screenRemaining > 0 {
                zipAccumulated += dt
                let fast = delay / Session.screenSpeedup
                let steps = min(Int(zipAccumulated / fast), screenRemaining, Session.stepCap)
                zipAccumulated -= Double(steps) * fast
                for _ in 0..<steps { advance() }
                screenRemaining -= steps
            }
            if screenRemaining == 0 { zipAccumulated = 0 }
            return
        }
        accumulated += dt
        // Clocks advance before the generations, so a re-seed made by those
        // generations restarts the grace period from this instant (R-X3).
        sinceInit += dt
        if playMode { playElapsed += dt }
        let steps = Int(accumulated / delay)
        accumulated -= Double(steps) * delay
        for _ in 0..<min(steps, Session.stepCap) { advance() }
        if playMode && !pairs.isEmpty  // R-X3: watchdog expired and the grace period observed
            && playElapsed >= Session.playTimeout && sinceInit >= Session.playGrace {
            nextPlayPair(reason: "timeout")
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

    // MARK: - Rules (R-K2..R-K6, R-B)

    private func setRule(_ rule: Rule) {
        automaton.rule = rule
        resetBoredom()
        store.saveRule(rule)
        output("rule \(rule.id)")  // R-O1
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
                output("discarded \(tries - 1) rule\(tries > 2 ? "s" : "")")  // R-O2
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
        if let rule = undoStack.popLast() { setRule(rule) }
    }

    private func saveInteresting() {  // R-K5
        store.appendInteresting(automaton.rule)
        output("saved rule \(automaton.rule.id)")  // R-O3
    }

    private func initCells() {  // R-K6
        automaton.resetRandom(using: &rng)
        pushRow(automaton.cells)
        resetBoredom()
        sinceInit = 0  // R-X3: any initialization restarts the grace period
    }

    private func selectInteresting(step: Int) {  // R-B2, R-B3
        let rules = store.loadInteresting()
        guard !rules.isEmpty else {
            output("no saved interesting rules")  // R-O5
            return
        }
        let n = rules.count
        let total = unsavedRule != nil ? n + 1 : n
        let at = interestingIndex ?? n
        let to = ((at + step) % total + total) % total
        undoStack.append(automaton.rule)
        if to == n {  // only reachable when the unsaved slot is occupied
            interestingIndex = nil
            output("unsaved rule")  // R-O4
            setRule(unsavedRule!)
        } else {
            interestingIndex = to
            output("interesting \(to + 1)/\(n)")  // R-O4
            setRule(rules[to])
        }
    }

    // MARK: - Keys (R-K)

    /// Returns false when the program should quit.
    public func handleKey(_ key: Key) -> Bool {
        if key == .q { return false }
        if paused {  // R-K10: space, Return, s, and the color keys are live
            switch key {
            case .space:
                paused = false
                screenRemaining = 0
                screenCounter = 0  // R-K14: resume (re)starts the screen counter
                counted = 0
                // Resume seamlessly: the paused view shows the newest row fully
                // (offset 1); start at the next generation so the first tick
                // computes it and the picture does not jump.
                accumulated = delay
            case .ret:
                advance()  // R-K11: single step, stay paused
            case .s:
                screenRemaining += rows  // R-K13: queue a screenful
            default:
                _ = handleColorKey(key)
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
            if screensaverMode { savePair() } else { saveInteresting() }  // R-W4
        case .i:
            initCells()
        case .n:
            selectInteresting(step: 1)
        case .p:
            selectInteresting(step: -1)
        case .a:  // R-K12
            autoInit.toggle()
            output("auto-init \(autoInit ? "on" : "off")")  // R-O6
        case .c, .C, .S, .N, .P, .X, .poolPrev, .poolNext, .digit:
            _ = handleColorKey(key)
        case .plus:
            delay = max(delay / 2, Session.minDelay)
        case .minus:
            delay = min(delay * 2, Session.maxDelay)
        case .q, .ret:
            break
        }
        return true
    }
}

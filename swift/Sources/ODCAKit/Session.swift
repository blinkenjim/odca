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

/// The toolkit-free orchestration layer: everything the two programs do
/// except rendering pixels and reading raw key events. The UI layer
/// translates toolkit key events into `Session.Key`, calls `tick(_:)` at
/// its refresh rate, and draws `history` through `paletteTable` and `rowPalettes`
/// (inverted while `inverted`). Programs: odca-select (`selectFile`, section
/// 4c), odca (`show`, section 4d); color set review (`reviewMode`,
/// section 4b) is on hold and bound by no program.
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
    public static let playTimeout = 120.0  // odca: a pair's screen time before it may advance (R-X3)
    public static let playGrace = 60.0  // odca: no transition within this long of an initialization (R-X3)
    public static let shuffleTries = 100  // `shuffle`: draws tried for an order without repeats (R-X7)
    public static let flashSeconds = 0.25  // the screen inverts this long as a mode cue (R-U10)
    public static let historyDepth = 2048  // rows remembered beyond the screen (R-U8)
    public static let paletteLimit = 64  // odca: prune the per-row palette table past this (R-X5)
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
        case U  // undo every change since the cycle position last moved (R-K19)
        case c, C, S  // arrange colors forward / backward; S appends a pair (R-W4)
        case N, P, X  // odca: next / previous pair; odca-select: X deletes; review: next / previous / drop
        case R  // odca-select: toggle the n/p order, file order or grouped by rule (R-W7)
        case poolPrev, poolNext  // '[' / ']': step through the color set pool (R-K17)
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
    /// Index into `paletteTable` of the palette each history row was painted with (R-X5).
    public private(set) var rowPalettes: [UInt16] = []
    /// odca (R-X5): the color sets rows were painted with; other modes use one entry, index 0.
    private var palettes: [[RGB]] = []
    private var paletteIndex = 0
    /// R-U5: the starting delay, 1/60 s at the default cell size and halved
    /// per halving of the cell, so the picture moves at the same speed in
    /// points; the continuous-scrolling threshold is twice it (R-U3).
    public let initialDelay: Double
    /// odca's clocks (R-X2, R-X3): whole seconds from --watchdog / --grace, or the defaults.
    public let playTimeout: Double
    public let playGrace: Double
    public var smoothScrollDelay: Double { 2 * initialDelay }
    public private(set) var delay: Double
    public private(set) var paused = false
    public private(set) var screenRemaining = 0  // generations still to zip (R-K13)
    public private(set) var screenCounter: Int?  // screenfuls since last resume (R-K14)
    public private(set) var autoInit = true  // R-K12: on at startup, not persisted
    public private(set) var cyclePeriod: Int?  // exact period once Brent's finds a cycle
    private var boringByExtinction = false  // the boring reason is an extinction (R-A1 first clause)
    public private(set) var flashRemaining = 0.0  // seconds of screen inversion left (R-U10)
    public private(set) var colorSets: [Int: ColorSet]
    public private(set) var colorSet = Session.defaultColorSet
    // Color set review mode (R-V): kept sets in review order, position, drops.
    public let reviewMode: Bool
    public private(set) var reviewEntries: [ColorSetEntry] = []
    public private(set) var reviewIndex = 0
    public private(set) var droppedNames: [String] = []
    private var reviewArrangement: [String: Int] = [:]
    // The pair cycle (R-B): the file's pairs in view order plus the unsaved slot.
    public let selectFile: URL?  // odca-select (R-W)
    /// odca-select --longest (R-W9): only the pairs whose rule has seeds are
    /// presented; X deletes the rule's seeds instead of the pair.
    public let selectLongest: Bool
    public private(set) var selectSeeds: Seeds = [:]  // the file's seeds under --longest
    public private(set) var pairs: [Pair] = []  // always in file order
    public private(set) var pairIndex: Int?  // file index of the pair under review / playing
    public private(set) var viewOrder: [Int] = []  // file indices in n/p order
    public private(set) var viewPosition: Int?  // position of pairIndex within viewOrder
    public private(set) var grouped = false  // R: n/p order grouped by rule (R-W7)
    public private(set) var unsavedRule: Rule?
    public private(set) var unsavedSet: ColorSetEntry?  // the set shown with the unsaved rule (R-B3)
    // odca (R-X): play a show, one segment per command-line file (Show.load),
    // the files in turn or in a fresh shuffled order per pass, each file's
    // pairs in file order or (R-X7: the script said `shuffle`) shuffled.
    public let show: [Segment]?
    public let shuffle: Bool
    /// `--longest` (R-X8): the show is the recorded seeds of the pairs at the
    /// screen width, those that did not survive the cap; each plays to its
    /// extinction; the width is fixed; the rule keys are inert.
    public let longest: Bool
    /// The pairs of the current pass, in order; `seed` is the rank of the
    /// seed played under `--longest`, nil otherwise.
    public private(set) var playOrder: [(segment: Int, index: Int, seed: Int?)] = []
    public private(set) var playPosition: Int?
    public private(set) var playSegment: Int?  // the segment (command-line file) of the pair playing
    public private(set) var playElapsed = 0.0  // unpaused seconds on the current pair
    public private(set) var sinceInit = 0.0  // unpaused seconds since the last (re)initialization
    public private(set) var activeSet: ColorSetEntry?  // the set in use (any pool member)
    /// Arrangement index of the active set, remembered per set name (R-K15).
    private var activeArrangement: Int {
        get { arrangementByName[activeName] ?? 0 }
        set { arrangementByName[activeName] = newValue }
    }
    private var activeName: String { activeSet?.name ?? colorSets[colorSet]!.name }
    private var pool: [ColorSetEntry] = []  // whole pool in review order for [ / ]
    public private(set) var undoStack: [Rule] = []
    private var undoMark = 0  // stack depth when the cycle position last moved; U unwinds to it (R-K19)
    public private(set) var candidates: [Rule]
    /// Terminal output sink (R-O); the UI leaves it as print, tests capture it.
    public var output: (String) -> Void = { print($0) }

    let store: Store
    let search: CandidateSearch
    var rng: Xoshiro256
    private var accumulated = 0.0
    private var zipAccumulated = 0.0
    private var counted = 0  // generations since the screen counter started
    private var arrangementByName: [String: Int] = [:]  // set name -> index into arrangements

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
        reviewMode: Bool = false, selectFile: URL? = nil, selectLongest: Bool = false,
        show: [Segment]? = nil, shuffle: Bool = false, longest: Bool = false,
        initialDelay: Double = Session.initialDelay,
        playTimeout: Double = Session.playTimeout, playGrace: Double = Session.playGrace,
        output: @escaping (String) -> Void = { print($0) }
    ) {
        self.cols = cols
        self.rows = rows
        self.playTimeout = playTimeout
        self.playGrace = playGrace
        self.initialDelay = initialDelay
        self.delay = initialDelay
        self.store = store
        self.search = search
        // Program precedence: odca (play), then odca-select, then color set review.
        self.show = show
        self.shuffle = shuffle && show != nil
        self.longest = longest && show != nil
        let selectFile = show == nil ? selectFile : nil
        self.reviewMode = reviewMode && selectFile == nil && show == nil
        self.selectFile = selectFile
        self.selectLongest = selectLongest && selectFile != nil
        self.output = output
        var rng = rng

        // Startup per R-U1: previous rule (random fallback), random cells.
        let rule = store.loadRule() ?? Rule.random(using: &rng)
        automaton = try! Automaton(
            width: cols, rule: rule,
            cells: Automaton.randomCells(width: cols, using: &rng))
        store.saveRule(rule)
        unsavedRule = rule  // the startup rule fills the unsaved slot (R-B3) unless a file opens on pair 1

        candidates = store.loadCandidates()
        colorSets = store.loadColorSets()  // R-P4
        self.rng = rng
        // Every mode but color set review draws through the active set, which
        // may be any pool member (R-K17); it starts as the default slot.
        pool = poolOrder()
        let d = colorSets[colorSet]!
        activeSet = ColorSetEntry(slot: colorSet, name: d.name, colors: d.colors)
        unsavedSet = activeSet
        pushRow(automaton.cells)
        output("rule \(rule.id)")
        if reviewMode { loadReview() }
        if let url = selectFile { loadSelect(url) }
        if show != nil { loadPlay() }
    }

    public var selectMode: Bool { selectFile != nil }
    public var playMode: Bool { show != nil }
    /// The display shows inverted colors while a flash runs (R-U10).
    public var inverted: Bool { flashRemaining > 0 }

    public var ruleID: String { automaton.rule.id }

    /// The window title (R-U6).
    public var title: String { "ODCA — rule \(ruleID)" }

    /// The generation counter under `--longest` (R-O17): `<n>/<m>`, this
    /// generation over the seed's recorded lifetime; nil in any other show.
    /// The UI shows it on the terminal five times a second.
    public var counter: String? {
        guard longest, let position = playPosition, let rank = playOrder[position].seed else { return nil }
        let seed = playableSeeds(playOrder[position].segment, playOrder[position].index)[rank]
        return "\(automaton.generation)/\(seed.generations)"
    }

    public func startSearch() { search.start() }
    public func stopSearch() { search.stop() }

    private func pushRow(_ row: [UInt8]) {
        if playMode {
            // R-X5: a row keeps the colors it was painted with. A changed
            // active set becomes a new table entry for the rows from now on.
            let current = palette
            if palettes.isEmpty {
                palettes = [current]
            } else if current != palettes[paletteIndex] {
                if let shared = palettes.firstIndex(of: current) {  // a set seen before: share its entry
                    paletteIndex = shared
                } else {
                    if palettes.count >= Session.paletteLimit { prunePalettes() }
                    palettes.append(current)
                    paletteIndex = palettes.count - 1
                }
            }
        }
        history.append(row)
        rowPalettes.append(UInt16(paletteIndex))
        trimHistory()
    }

    /// Drop table entries no remembered row uses any more, renumbering the rest.
    private func prunePalettes() {
        let keep = Set(rowPalettes.map { Int($0) }).union([paletteIndex]).sorted()
        var remap = [Int: Int]()
        for (new, old) in keep.enumerated() { remap[old] = new }
        rowPalettes = rowPalettes.map { UInt16(remap[Int($0)]!) }
        palettes = keep.map { palettes[$0] }
        paletteIndex = remap[paletteIndex]!
    }

    private func trimHistory() {
        let keep = max(Session.historyDepth, rows + 1)
        if history.count > keep {
            history.removeFirst(history.count - keep)
            rowPalettes.removeFirst(rowPalettes.count - keep)
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
        let newCols = longest ? cols : max(Session.minCols, newCols)  // R-X8: the width is the seeds'

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

    /// RGB for every (palette, state) as one array, entry palette * 4 + state
    /// (R-X5). Outside odca there is one palette, the active set, so the
    /// whole screen recolors at once.
    public var paletteTable: [RGB] {
        if playMode && !palettes.isEmpty { return palettes.flatMap { $0 } }
        return palette
    }

    /// Display color of a history cell: its state through its row's palette.
    public func color(row: Int, col: Int) -> RGB {
        paletteTable[Int(rowPalettes[row]) * 4 + Int(history[row][col])]
    }

    /// How far the display is scrolled into the top history row, in cells
    /// (R-U3): 0 while the buffer is filling; 1 (newest row fully shown) when
    /// paused or at fast speeds; else the elapsed fraction of the current
    /// delay, so the picture slides up one cell per delay.
    public var scrollOffset: Double {
        if history.count <= rows { return 0 }
        if paused || delay <= smoothScrollDelay { return 1 }
        return min(accumulated / delay, 1)
    }

    // MARK: - Colors (R-U4, R-K15, R-K16)

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
        (reviewMode ? arrangedReviewColors() : arrangedActiveColors()).map { RGB(hex: $0) }
    }

    private func cycleColors(_ step: Int) {
        let n = Session.arrangements.count
        if reviewMode {
            guard let e = reviewEntry else { return }
            let index = (((reviewArrangement[e.name] ?? 0) + step) % n + n) % n
            reviewArrangement[e.name] = index
            output("color set \(e.name) arrangement \(index + 1)/\(n)")  // R-O9
            return
        }
        activeArrangement = ((activeArrangement + step) % n + n) % n
        output("color set \(activeName) arrangement \(activeArrangement + 1)/\(n)")  // R-O9
    }

    /// R-U10: invert the screen briefly as a cue.
    private func flash() { flashRemaining = Session.flashSeconds }

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
        fillScreen()  // R-V7
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
        if !reviewEntries.isEmpty { fillScreen() }  // R-V7
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

    // MARK: - The pool (R-K17)

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

    private func poolStep(_ step: Int) {  // R-K17: '[' / ']' walk the whole pool, wrapping
        guard !pool.isEmpty else { return }
        let current = pool.firstIndex { $0.name == activeSet?.name } ?? -1
        let n = pool.count
        let index = ((current + step) % n + n) % n
        let e = pool[index]
        activeSet = ColorSetEntry(slot: e.slot, name: e.name, colors: e.colors)
        if let slot = e.slot { colorSet = slot }
        output("color set \(e.name)")  // R-O15
    }

    /// Compute a screenful at once so a review step shows only the new state (R-V7).
    private func fillScreen() { for _ in 0..<rows { advance() } }

    // MARK: - The pair cycle (R-B, R-W)

    /// n/p order (R-W7): file order, or pairs grouped by rule, groups in
    /// order of each rule's first appearance.
    /// R-W9: under odca-select --longest only pairs whose rule has seeds are presented.
    private func shown(_ index: Int) -> Bool {
        !selectLongest || !(selectSeeds[pairs[index].rule] ?? [:]).isEmpty
    }

    private func rebuildViewOrder() {
        let shown = pairs.indices.filter(shown)
        if grouped {
            var groups: [String: [Int]] = [:]
            var ruleOrder: [String] = []
            for i in shown {
                let p = pairs[i]
                if groups[p.rule] == nil { ruleOrder.append(p.rule) }
                groups[p.rule, default: []].append(i)
            }
            viewOrder = ruleOrder.flatMap { groups[$0]! }
        } else {
            viewOrder = shown
        }
        viewPosition = pairIndex.flatMap { viewOrder.firstIndex(of: $0) }
    }

    /// 1-based group number of a file index among the rule groups shown, and the count.
    private func ruleGroup(of index: Int) -> (Int, Int) {
        var seen: [String] = []
        for i in viewOrder where !seen.contains(pairs[i].rule) { seen.append(pairs[i].rule) }
        return ((seen.firstIndex(of: pairs[index].rule) ?? 0) + 1, seen.count)
    }

    private func currentPair() -> Pair {
        Pair(name: Store.nextPairName(pairs), rule: automaton.rule.id, colorset: activeName,
             colors: arrangedActiveColors())
    }

    /// `<name> <colorset>` for the R-O4 / R-O13 lines; a nameless pair shows its set only.
    private func label(_ pair: Pair) -> String {
        pair.name.map { "\($0) \(pair.colorset)" } ?? pair.colorset
    }

    /// Show a pair's or the unsaved slot's colors: they become the active set (R-B2).
    private func showColors(name: String, colors: [String]) {
        activeSet = ColorSetEntry(slot: nil, name: name, colors: colors)
        activeArrangement = 0  // stored colors are already arranged
    }

    private func activatePair(viewPosition position: Int, pushUndo: Bool = true) {  // R-B2, R-W8
        let index = viewOrder[position]
        let pair = pairs[index]
        if grouped, pairIndex.map({ pairs[$0].rule }) != pair.rule {
            let (g, total) = ruleGroup(of: index)
            output("--- rule group \(g)/\(total) ---")  // R-O12
        }
        viewPosition = position
        pairIndex = index
        if let rule = try? Rule(id: pair.rule), rule != automaton.rule {
            if pushUndo { undoStack.append(automaton.rule) }
            setRule(rule)
        }
        showColors(name: pair.colorset, colors: pair.colors)
        undoMark = undoStack.count
        output("pair \(position + 1)/\(viewOrder.count) \(label(pair))")  // R-O4
        initCells()  // R-W8: the pair grows in from a fresh field below the old rows
    }

    /// n/p: cycle through the pairs in view order plus the unsaved slot, if
    /// occupied (R-B2, R-B3). Only odca-select has a file of pairs.
    private func selectPair(step: Int) {
        let n = viewOrder.count
        let total = unsavedRule != nil ? n + 1 : n
        guard n > 0 else {
            output("no pairs")  // R-O5
            return
        }
        let at = pairIndex == nil ? n : viewPosition!
        let to = ((at + step) % total + total) % total
        undoStack.append(automaton.rule)
        if to == n {  // only reachable when the unsaved slot is occupied
            pairIndex = nil
            viewPosition = nil
            output("unsaved rule")  // R-O4
            setRule(unsavedRule!)
            if let set = unsavedSet { showColors(name: set.name, colors: set.colors) }
            initCells()  // R-W8: every n/p step scrolls the selection in from a fresh field
        } else {
            activatePair(viewPosition: to, pushUndo: false)
        }
    }

    // MARK: - odca-select (R-W)

    private func loadSelect(_ url: URL) {  // R-W1
        pairs = Store.loadOdcaFile(url) ?? []  // a missing file is created by the first save or at exit
        for i in pairs.indices where pairs[i].name == nil {  // R-P3: every pair gets a name
            pairs[i].name = Store.nextPairName(pairs)  // the file is written at exit at the latest
        }
        if selectLongest { selectSeeds = Store.loadSeeds(url) }
        rebuildViewOrder()
        if selectLongest {  // R-W9, R-O12
            output("odca \(url.lastPathComponent): \(pairs.count) pairs, \(viewOrder.count) with seeds")
        } else {
            output("odca \(url.lastPathComponent): \(pairs.count) pairs")  // R-O12
        }
        if !viewOrder.isEmpty {
            // Open on pair 1; the unsaved slot stays empty until r or m fires.
            unsavedRule = nil
            unsavedSet = nil
            activatePair(viewPosition: 0, pushUndo: false)
        }
    }

    private func saveLooks() {
        guard let url = selectFile else { return }
        // R-W9: under --longest the seeds are written back as held here (X
        // removes a rule's); otherwise the file's own are carried through.
        if selectLongest { Store.saveOdcaFile(pairs, seeds: selectSeeds, to: url) } else { Store.saveOdcaFile(pairs, to: url) }
        output("saved \(pairs.count) pair\(pairs.count == 1 ? "" : "s") to \(url.lastPathComponent)")  // R-O12
    }

    private func savePair() {  // R-W4: 's' rewrites the pair under review's colors in place, or appends
        guard let i = pairIndex else {
            appendPair()
            return
        }
        if automaton.rule.id != pairs[i].rule {
            // R-K3: a mutated pair is a new pair; a kept rule is never overwritten.
            // The position moves onto the new pair, so further edits refine it —
            // except under --longest (R-W9), where the new pair, having no
            // seeds, cannot be shown: the position stays.
            appendPair()
            if !selectLongest {
                pairIndex = pairs.count - 1
                rebuildViewOrder()
                undoMark = undoStack.count  // an arrival (R-K19)
            }
            return
        }
        pairs[i] = Pair(name: pairs[i].name, rule: pairs[i].rule, colorset: activeName,
                        colors: arrangedActiveColors())  // the name and the rule stay
        saveLooks()
        output("saved pair \((viewPosition ?? i) + 1)/\(viewOrder.count)")  // R-O12
    }

    private func appendPair() {  // R-W4: 'S' appends a copy of the screen; the position is unchanged
        pairs.append(currentPair())  // always at the end of the file
        rebuildViewOrder()  // in the grouped order it joins its rule's group
        saveLooks()
        output("added pair \(pairs.count)/\(pairs.count)")  // R-O12
    }

    private func deletePair() {  // R-W5; under --longest R-W9: the rule's seeds go, the pair stays
        guard let i = pairIndex, let position = viewPosition else { return }
        let shownCount = viewOrder.count
        if selectLongest {
            let pair = pairs[i]
            selectSeeds[pair.rule] = nil
            output("deleted seeds of pair \(position + 1)/\(shownCount) \(label(pair))")  // R-O12
        } else {
            pairs.remove(at: i)  // in place: later pairs keep their relative file order
        }
        pairIndex = nil
        rebuildViewOrder()
        saveLooks()
        if !selectLongest { output("deleted pair \(position + 1)/\(shownCount)") }  // R-O12
        if viewOrder.isEmpty {
            // Nothing left to review: the rule on screen becomes the unsaved rule.
            viewPosition = nil
            unsavedRule = automaton.rule
            unsavedSet = activeSet
        } else {
            activatePair(viewPosition: min(position, viewOrder.count - 1))
        }
    }

    private func toggleGrouped() {  // R-W7: 'R'
        grouped.toggle()
        rebuildViewOrder()
        output("pair order \(grouped ? "grouped by rule" : "file order")")  // R-O12
        flash()  // R-U10
    }

    // MARK: - odca (R-X)

    private func loadPlay() {  // R-X1
        for (seg, segment) in show!.enumerated() {  // R-O13
            if longest {  // R-X8: what the file brings to the show at this width
                let count = segment.pairs.indices.reduce(0) { $0 + playableSeeds(seg, $1).count }
                output("odca \(segment.file): \(segment.pairs.count) pairs, \(count) seeds at \(cols) cells")
            } else {
                let how = segment.shuffle ? ", shuffled" : ""  // R-X7: the script said `shuffle`
                output("odca \(segment.file): \(segment.pairs.count) pairs\(how)")
            }
        }
        pairs = []
        newPass()
        if !playOrder.isEmpty { playPair(at: 0, reason: nil) }
    }

    /// R-X8: the seeds a pair plays under `--longest` — its rule's at the
    /// screen width, longest first, without those that survived the cap.
    private func playableSeeds(_ segment: Int, _ index: Int) -> [Seed] {
        (show![segment].seeds[show![segment].pairs[index].rule]?[cols] ?? []).filter { $0.end != Seed.survived }
    }

    /// The `--longest` pass (R-X8): every pair's longest playable seed, then
    /// every pair's second, and so on, pairs in file order and files in
    /// command-line order; or, with `--shuffle`, a fresh permutation of all
    /// of them under the constraints of `shuffle` (R-X7), the seam included.
    private func longestPass() -> [(segment: Int, index: Int, seed: Int?)] {
        let show = self.show!
        let counts = show.indices.map { seg in show[seg].pairs.indices.map { playableSeeds(seg, $0).count } }
        var pass: [(segment: Int, index: Int, seed: Int?)] = []
        for rank in 0..<(counts.flatMap { $0 }.max() ?? 0) {
            for seg in show.indices {
                for index in show[seg].pairs.indices where counts[seg][index] > rank {
                    pass.append((segment: seg, index: index, seed: rank))
                }
            }
        }
        if shuffle && pass.count > 1 {
            let previous = playSegment.map { (segment: $0, index: pairIndex!) }
            for _ in 0..<Session.shuffleTries {
                pass.shuffle(using: &rng)
                if noRepeats(pass.map { (segment: $0.segment, index: $0.index) }, after: previous) { break }
            }
        }
        return pass
    }

    /// The files in command-line order, or a fresh shuffle of them per pass
    /// (R-X1): never the same file twice running, the seam from the file
    /// just played included (unless it is the only one with pairs). Within
    /// a file, its pairs in file order, or (R-X7: `shuffle`) a fresh
    /// permutation in which no rule and no color set follows itself; the
    /// seam is the pair before it in the pass, whatever file that came
    /// from, or the pair still on screen for the pass's first file. A file
    /// that allows no such order plays the last draw as it is.
    private func newPass() {
        if longest {
            playOrder = longestPass()
            playPosition = 0
            return
        }
        let show = self.show!
        var order = Array(show.indices)
        if shuffle && show.count > 1 {
            let playable = order.filter { !show[$0].pairs.isEmpty }
            repeat {
                order.shuffle(using: &rng)
            } while playable.count >= 2 && order.first { !show[$0].pairs.isEmpty } == playSegment
        }
        var previous = playSegment.map { (segment: $0, index: pairIndex!) }
        var pass: [(segment: Int, index: Int, seed: Int?)] = []
        for seg in order {
            var indices = Array(show[seg].pairs.indices)
            if show[seg].shuffle && indices.count > 1 {
                for _ in 0..<Session.shuffleTries {
                    indices.shuffle(using: &rng)
                    if noRepeats(indices.map { (segment: seg, index: $0) }, after: previous) { break }
                }
            }
            pass += indices.map { (segment: seg, index: $0, seed: nil) }
            previous = pass.last.map { (segment: $0.segment, index: $0.index) }
        }
        playOrder = pass
        playPosition = 0
    }

    private func noRepeats(_ items: [(segment: Int, index: Int)], after previous: (segment: Int, index: Int)?) -> Bool {
        let chain = (previous.map { [$0] } ?? []) + items
        return zip(chain, chain.dropFirst()).allSatisfy { !clash($0, $1) }
    }

    /// Two pairs repeat if they share the rule or the color set (in any arrangement).
    private func clash(_ a: (segment: Int, index: Int), _ b: (segment: Int, index: Int)) -> Bool {
        let pa = show![a.segment].pairs[a.index], pb = show![b.segment].pairs[b.index]
        return pa.rule == pb.rule || pa.colors.sorted() == pb.colors.sorted()
    }

    /// Activate a pair for play: its rule and colors, then a fresh seed (R-X4).
    private func playPair(at position: Int, reason: String?) {
        let (segment, index, rank) = playOrder[position]
        playPosition = position
        let entered = segment != playSegment
        playSegment = segment
        pairs = show![segment].pairs
        let pair = pairs[index]
        pairIndex = index
        if let rule = try? Rule(id: pair.rule), rule != automaton.rule { setRule(rule) }
        undoMark = undoStack.count  // R-K19: U returns to the pair as played
        showColors(name: pair.colorset, colors: pair.colors)
        // R-X4: the longest-lived recorded seed for this rule at exactly this
        // width, when the file has one; a random row otherwise. R-X8: the
        // seed of the item's rank.
        let seeds = playableSeeds(segment, index)
        initCells(with: rank.map { seeds[$0].row } ?? show![segment].seeds[pair.rule]?[cols]?.first?.row)
        playElapsed = 0  // the pair's screen time starts now
        if entered && show!.count > 1 { output("playing \(show![segment].file)") }  // R-O13: another file
        let which = rank.map { ", seed \($0 + 1)/\(seeds.count), \(seeds[$0].generations) generations" } ?? ""
        let why = reason.map { " (\($0))" } ?? ""
        output("pair \(index + 1)/\(pairs.count) \(label(pair))\(which)\(why)")  // R-O13
    }

    /// `i` under `--longest` (R-X8): the seed on screen from its first row again.
    private func restartSeed() {
        guard let position = playPosition, let rank = playOrder[position].seed else { return initCells() }
        initCells(with: playableSeeds(playOrder[position].segment, playOrder[position].index)[rank].row)
    }

    private func nextPlayPair(reason: String) {  // R-X2, R-X3: on through the pass, then a new pass
        var position = (playPosition ?? -1) + 1
        if position >= playOrder.count {
            newPass()
            position = 0
        }
        playPair(at: position, reason: reason)
    }

    private func playStep(_ step: Int) {  // R-X6: N/P move through the pass by hand, wrapping
        guard !playOrder.isEmpty else { return }
        if step > 0 {
            nextPlayPair(reason: "next")
        } else {
            let n = playOrder.count
            playPair(at: (((playPosition ?? 0) - 1) % n + n) % n, reason: "previous")
        }
    }

    /// Call at program exit: odca-select writes its file; review saves (R-V5).
    public func finish() {
        if selectMode { saveLooks() }
        if reviewMode { saveReview() }
    }

    /// R-K16: bake the active set's arrangement into its library entry (by
    /// name; a set not yet in the file is added, keeping its slot if it has
    /// one). No program binds this in 3.0.0; kept for the color set tool.
    private func saveColorSet() {
        let name = activeName
        let arranged = arrangedActiveColors()
        var file = store.loadColorSetFile()
        if let i = file.sets.firstIndex(where: { $0.name == name }) {
            file.sets[i].colors = arranged
        } else {
            file.sets.append(ColorSetEntry(slot: activeSet?.slot, name: name, colors: arranged))
        }
        store.saveColorSetFile(file)
        arrangementByName[name] = 0
        activeSet?.colors = arranged
        colorSets = store.loadColorSets()
        pool = poolOrder()
        output("saved color set \(name)")  // R-O10
    }

    private func selectColorSet(_ slot: Int) {
        if reviewMode { return }  // R-V1: digit keys are disabled during review
        guard let set = colorSets[slot] else { return }  // R-K9: undefined slot is a no-op
        colorSet = slot
        activeSet = ColorSetEntry(slot: slot, name: set.name, colors: set.colors)
    }

    /// Color and pair keys shared by the paused and running states (R-K10).
    private func handleColorKey(_ key: Key) -> Bool {
        switch key {
        case .c: cycleColors(1)
        case .C: cycleColors(-1)
        case .S:
            if selectMode { appendPair() } else if !reviewMode && !playMode { saveColorSet() }
        case .N:
            if playMode { playStep(1) } else if reviewMode { reviewStep(1) }
        case .P:
            if playMode { playStep(-1) } else if reviewMode { reviewStep(-1) }
        case .X: if selectMode { deletePair() } else if reviewMode { dropReview() }
        case .R: if selectMode { toggleGrouped() }
        case .poolPrev: if reviewMode { reviewStep(-1) } else { poolStep(-1) }  // R-K17
        case .poolNext: if reviewMode { reviewStep(1) } else { poolStep(1) }
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
            if longest {  // R-X8: a seed plays to its extinction or its confirmed cycle, then the next
                // The screenful-based repetition and stagnation are ignored: only
                // the streak restarts, so Brent's keeps pace with the recording.
                if boringByExtinction || cyclePeriod != nil { nextPlayPair(reason: reason) } else { boringStreak = 0 }
            } else if playMode && !playOrder.isEmpty && playElapsed >= playTimeout {
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
        let (extinction, minorityPopulation) = Session.census(of: row, rule: automaton.rule)
        minorityCounts.append(minorityPopulation)
        let window = Session.stagnationScreens * rows
        if minorityCounts.count > window { minorityCounts.removeFirst() }
        var stagnant = false
        if minorityCounts.count == window {
            let lo = minorityCounts.min()!, hi = minorityCounts.max()!
            let mean = Double(minorityCounts.reduce(0, +)) / Double(window)
            stagnant = mean > 0 && Double(hi - lo) / mean < Session.stagnationSwing
        }

        let reason: String?
        if let extinction = extinction {
            reason = extinction
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
        boringByExtinction = extinction != nil
    }

    /// The extinction clause of R-A1 on one row: the reason text when some
    /// producible state has no cells and no other is a living minority, else
    /// nil; and the living-minority population, for the stagnation test.
    /// Shared with odca-evolve, whose whole notion of boring this is (R-E2).
    static func census(of row: [UInt8], rule: Rule) -> (extinction: String?, minorityPopulation: Int) {
        var census = [Int](repeating: 0, count: Rule.stateCount)
        for c in row { census[Int(c)] += 1 }
        let producible = Set(rule.states.map { Int($0) }).sorted()
        let extinct = producible.filter { census[$0] == 0 }
        let minority = producible.filter {
            census[$0] > 0 && Double(census[$0]) < Session.minorityFraction * Double(row.count)
        }
        let population = minority.reduce(0) { $0 + census[$1] }
        guard !extinct.isEmpty && minority.isEmpty else { return (nil, population) }
        let names = extinct.map(String.init).joined(separator: ", ")
        return ("state\(extinct.count > 1 ? "s" : "") \(names) extinct", population)
    }

    /// R-A1's extinction clause alone: the reason a row is boring by
    /// extinction, or nil.
    public static func extinction(in row: [UInt8], rule: Rule) -> String? {
        census(of: row, rule: rule).extinction
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
        flashRemaining = max(0, flashRemaining - dt)  // display only: runs while paused (R-U10)
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
        if playMode && !longest && !playOrder.isEmpty  // R-X3: watchdog expired and the grace period observed
            && playElapsed >= playTimeout && sinceInit >= playGrace {
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

    /// Make `rule` current and the occupant of the cycle's unsaved slot (R-B3).
    /// Make `rule` current and the occupant of the unsaved slot (R-B3). An
    /// arrival (r, or entering the slot) is where U unwinds to (R-K19); a
    /// mutation made on the slot is an edit, and U undoes it too.
    private func setUnsavedRule(_ rule: Rule, arrival: Bool = true) {
        unsavedRule = rule
        unsavedSet = activeSet
        pairIndex = nil
        viewPosition = nil
        setRule(rule)
        if arrival { undoMark = undoStack.count }
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
        let mutant = automaton.rule.mutated(using: &rng)
        if selectMode && pairIndex != nil {
            setRule(mutant)  // the pair under review is now changed: 's' and 'S' save it as a new pair
        } else {
            setUnsavedRule(mutant, arrival: false)
        }
    }

    private func undo() {  // R-K4
        if let rule = undoStack.popLast() { setRule(rule) }
    }

    private func undoAll() {  // R-K19: every change since the cycle position last moved, at once
        let mark = min(undoMark, undoStack.count)
        guard undoStack.count > mark else { return }
        let rule = undoStack[mark]
        undoStack.removeSubrange(mark...)
        setRule(rule)
        if selectMode && pairIndex == nil { unsavedRule = rule }  // the slot's mutations are undone with it
    }

    /// Re-seed (R-K6): random cells, or `row` when given and it fits the
    /// width — a recorded seed on arriving at a pair (R-X4).
    private func initCells(with row: [UInt8]? = nil) {
        if let row = row, row.count == cols, (try? automaton.reset(cells: row)) != nil {
            // seeded
        } else {
            automaton.resetRandom(using: &rng)
        }
        pushRow(automaton.cells)
        resetBoredom()
        sinceInit = 0  // R-X3: any initialization restarts the grace period
    }

    // MARK: - Keys (R-K)

    /// Returns false when the program should quit.
    public func handleKey(_ key: Key) -> Bool {
        if key == .q { return false }
        if paused {  // R-K10: space, Return, s, and the color and pair keys are live
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
        if longest, [.r, .m, .u, .U, .a].contains(key) { return true }  // R-X8: the rule is the seed's
        switch key {
        case .space:
            paused = true
        case .r:
            newRule()
        case .m:
            mutateRule()
        case .u:
            undo()
        case .U:
            undoAll()  // R-K19
        case .s:
            if selectMode { savePair() }  // R-W4; otherwise nothing to save into
        case .i:
            if longest { restartSeed() } else { initCells() }
        case .n:
            if playMode { playStep(1) } else { selectPair(step: 1) }
        case .p:
            if playMode { playStep(-1) } else { selectPair(step: -1) }
        case .a:  // R-K12
            autoInit.toggle()
            output("auto-init \(autoInit ? "on" : "off")")  // R-O6
        case .c, .C, .S, .N, .P, .X, .R, .poolPrev, .poolNext, .digit:
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
